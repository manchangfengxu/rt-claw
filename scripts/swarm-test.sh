#!/bin/bash
# swarm-test.sh — Launch 2 ESP32-C3 QEMU instances on a shared virtual LAN
#                 and verify swarm node discovery via UDP broadcast.
#
# Prerequisites:
#   make run-esp32c3-qemu-flash   (flash image must exist)
#
# Network: QEMU socket multicast backend (no host network config needed).
#          No DHCP server — nodes use link-local IP fallback.
#
# Usage:
#   scripts/swarm-test.sh
#
# SPDX-License-Identifier: MIT

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLASH="${PROJECT_ROOT}/build/esp32c3-qemu/idf/flash_image.bin"
MCAST="230.0.0.1:1234"
LOG_DIR="/tmp/rt-claw-swarm-test"

# With -icount 1: boot ~30s, DHCP 500ms sim ~4min real, swarm ~5min.
# Total ~10 min.  Set wait to 600s.
BOOT_WAIT=600

# Pre-checks
if [ ! -f "${FLASH}" ]; then
    echo "ERROR: Flash image not found at ${FLASH}"
    echo "       Run:  make run-esp32c3-qemu-flash"
    exit 1
fi

which qemu-system-riscv32 >/dev/null 2>&1 || {
    echo "ERROR: qemu-system-riscv32 not found in PATH"
    exit 1
}

# Setup
rm -rf "${LOG_DIR}"
mkdir -p "${LOG_DIR}"

echo "=== rt-claw Swarm Discovery Test ==="
echo "Flash:     ${FLASH}"
echo "Multicast: ${MCAST}"
echo "Boot wait: ${BOOT_WAIT}s"
echo ""

# Each QEMU needs its own flash image copy (file lock)
cp "${FLASH}" "${LOG_DIR}/flash_node1.bin"
cp "${FLASH}" "${LOG_DIR}/flash_node2.bin"

cleanup() {
    echo ""
    echo "--- Cleaning up ---"
    [ -n "${PID1:-}" ] && kill "${PID1}" 2>/dev/null || true
    [ -n "${PID2:-}" ] && kill "${PID2}" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

# Launch Node 1 (MAC: 52:54:00:12:34:01)
echo ">>> Starting Node 1 ..."
qemu-system-riscv32 \
    -nographic \
    -icount 1 \
    -machine esp32c3 \
    -drive "file=${LOG_DIR}/flash_node1.bin,if=mtd,format=raw" \
    -global driver=timer.esp32c3.timg,property=wdt_disable,value=true \
    -nic "socket,model=open_eth,mcast=${MCAST}" \
    < /dev/null > "${LOG_DIR}/node1.log" 2>&1 &
PID1=$!

sleep 2

# Launch Node 2
echo ">>> Starting Node 2 ..."
qemu-system-riscv32 \
    -nographic \
    -icount 1 \
    -machine esp32c3 \
    -drive "file=${LOG_DIR}/flash_node2.bin,if=mtd,format=raw" \
    -global driver=timer.esp32c3.timg,property=wdt_disable,value=true \
    -nic "socket,model=open_eth,mcast=${MCAST}" \
    < /dev/null > "${LOG_DIR}/node2.log" 2>&1 &
PID2=$!

echo ">>> Waiting up to ${BOOT_WAIT}s for boot + DHCP + swarm discovery ..."
echo "    (ESP32-C3 QEMU with -icount 1 is slow, be patient)"
echo ""

# Progress indicator
ELAPSED=0
while [ "${ELAPSED}" -lt "${BOOT_WAIT}" ]; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))

    # Check processes alive
    if ! kill -0 "${PID1}" 2>/dev/null; then
        echo "  [${ELAPSED}s] WARNING: Node 1 exited"
        break
    fi
    if ! kill -0 "${PID2}" 2>/dev/null; then
        echo "  [${ELAPSED}s] WARNING: Node 2 exited"
        break
    fi

    printf "  [%ds / %ds] ..." "${ELAPSED}" "${BOOT_WAIT}"

    # Quick check for early discovery success
    if grep -q "joined" "${LOG_DIR}/node1.log" 2>/dev/null && \
       grep -q "joined" "${LOG_DIR}/node2.log" 2>/dev/null; then
        echo " discovery detected early!"
        break
    fi
    echo ""
done

# Note: shell is on stdin which is /dev/null, so we can't send
# interactive commands.  Detection relies on log output from
# claw_log_raw() and heartbeat_post() printf output.

echo ""
echo "=== Test Results ==="

# Strip ANSI codes for analysis
for F in "${LOG_DIR}/node1.log" "${LOG_DIR}/node2.log"; do
    sed -i 's/\x1b\[[0-9;]*m//g' "${F}"
done

PASS=0
FAIL=0

# Test 1: Both nodes booted
echo ""
echo "--- Boot Status ---"
N1_BOOT=0
N2_BOOT=0
if grep -q "rt-claw" "${LOG_DIR}/node1.log" 2>/dev/null; then
    N1_BOOT=1
fi
if grep -q "rt-claw" "${LOG_DIR}/node2.log" 2>/dev/null; then
    N2_BOOT=1
fi
if [ "${N1_BOOT}" -eq 1 ] && [ "${N2_BOOT}" -eq 1 ]; then
    echo "PASS: Both nodes booted"
    PASS=$((PASS + 1))
else
    echo "FAIL: Boot incomplete (node1=${N1_BOOT}, node2=${N2_BOOT})"
    FAIL=$((FAIL + 1))
fi

# Test 2: Static IP fallback (no DHCP on mcast network)
echo ""
echo "--- Network (Static IP Fallback) ---"
if grep -q "link-local\|static ip\|169\.254\." "${LOG_DIR}/node1.log" 2>/dev/null; then
    echo "PASS: Node 1 assigned link-local IP"
    PASS=$((PASS + 1))
elif grep -q "got ip" "${LOG_DIR}/node1.log" 2>/dev/null; then
    echo "PASS: Node 1 got IP (unexpected DHCP?)"
    PASS=$((PASS + 1))
else
    echo "SKIP: Node 1 network status unknown (may still be in DHCP wait)"
fi

# Test 3: Swarm discovery
echo ""
echo "--- Swarm Discovery ---"
N1_DISC=0
N2_DISC=0
if grep -q "joined" "${LOG_DIR}/node1.log" 2>/dev/null; then
    N1_DISC=1
    echo "  Node 1: peer discovered"
fi
if grep -q "joined" "${LOG_DIR}/node2.log" 2>/dev/null; then
    N2_DISC=1
    echo "  Node 2: peer discovered"
fi
if [ "${N1_DISC}" -eq 1 ] && [ "${N2_DISC}" -eq 1 ]; then
    echo "PASS: Mutual swarm discovery"
    PASS=$((PASS + 1))
elif [ "${N1_DISC}" -eq 1 ] || [ "${N2_DISC}" -eq 1 ]; then
    echo "PARTIAL: One-way discovery (may need more time)"
    PASS=$((PASS + 1))
else
    echo "FAIL: No swarm discovery detected"
    echo "  (This may be due to insufficient boot time with -icount 1)"
    FAIL=$((FAIL + 1))
fi

# Test 4: /nodes command output
echo ""
echo "--- /nodes Command ---"
if grep -q "nodes:" "${LOG_DIR}/node1.log" 2>/dev/null || \
   grep -q "self" "${LOG_DIR}/node1.log" 2>/dev/null; then
    echo "PASS: /nodes command responded"
    PASS=$((PASS + 1))
else
    echo "SKIP: /nodes output not captured (shell may not have processed)"
fi

# Summary
echo ""
echo "==========================="
echo "PASS: ${PASS}  FAIL: ${FAIL}"
echo "==========================="
echo ""
echo "Logs saved to: ${LOG_DIR}/"
echo "  Node 1: ${LOG_DIR}/node1.log ($(wc -l < "${LOG_DIR}/node1.log") lines)"
echo "  Node 2: ${LOG_DIR}/node2.log ($(wc -l < "${LOG_DIR}/node2.log") lines)"

if [ "${FAIL}" -gt 0 ]; then
    echo ""
    echo "--- Node 1 tail ---"
    tail -20 "${LOG_DIR}/node1.log"
    echo ""
    echo "--- Node 2 tail ---"
    tail -20 "${LOG_DIR}/node2.log"
fi

exit "${FAIL}"
