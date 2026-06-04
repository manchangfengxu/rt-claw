#!/bin/bash
# SPDX-License-Identifier: MIT
#
# test-cross-matrix.sh — Cross-platform Meson option matrix (Tier 4, bare-metal)
#
# Tests Meson option combinations on vexpress-a9 and zynq-a9 platforms.
# Requires: arm-none-eabi-gcc
#
# Usage:
#   scripts/test-cross-matrix.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

PASS=0
FAIL=0

if ! command -v arm-none-eabi-gcc > /dev/null 2>&1; then
    echo "ERROR: arm-none-eabi-gcc not found in PATH"
    echo "Install ARM cross-compiler first."
    exit 1
fi

reconfigure_and_build() {
    local platform="$1"; shift
    local label="$1"; shift
    local builddir="build/${platform}-test"
    local crossfile

    case "$platform" in
        vexpress-a9) crossfile="platform/vexpress-a9/cross.ini" ;;
        zynq-a9)     crossfile="platform/zynq-a9/cross.ini" ;;
        *)
            echo "  FAIL: Unknown platform: $platform"
            FAIL=$((FAIL + 1))
            return
            ;;
    esac

    echo "--- ${platform}: ${label} ---"
    rm -rf "$builddir"
    if meson setup "$builddir" --cross-file "$crossfile" "$@" > /dev/null 2>&1 && \
       meson compile -C "$builddir" > /dev/null 2>&1; then
        echo "  PASS: ${platform}: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${platform}: ${label}"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$builddir"
}

echo "=== Cross-Platform Meson Matrix ==="
echo ""

# --- vexpress-a9 (RT-Thread) ---
echo "--- vexpress-a9 combos ---"
reconfigure_and_build vexpress-a9 "default"
reconfigure_and_build vexpress-a9 "minimal" \
    -Dswarm=false -Dsched=false -Dskill=false \
    -Dtool_gpio=false -Dtool_system=false -Dtool_sched=false \
    -Dtool_net=false
reconfigure_and_build vexpress-a9 "full+ota" -Dota=true
reconfigure_and_build vexpress-a9 "heartbeat" -Dheartbeat=true

echo ""

# --- zynq-a9 (FreeRTOS) ---
echo "--- zynq-a9 combos ---"
reconfigure_and_build zynq-a9 "default"
reconfigure_and_build zynq-a9 "minimal" \
    -Dswarm=false -Dsched=false -Dskill=false \
    -Dtool_gpio=false -Dtool_system=false -Dtool_sched=false \
    -Dtool_net=false
reconfigure_and_build zynq-a9 "full+ota" -Dota=true

echo ""
echo "--- Negative: feishu/telegram override rejected at configure time ---"

expect_im_rejected() {
    local platform="$1"; shift
    local label="$1"; shift
    local builddir="build/${platform}-im-reject"
    local crossfile

    case "$platform" in
        vexpress-a9) crossfile="platform/vexpress-a9/cross.ini" ;;
        zynq-a9)     crossfile="platform/zynq-a9/cross.ini" ;;
    esac

    echo "--- ${platform}: ${label} (expect configure error) ---"
    rm -rf "$builddir"

    local output
    output=$(meson setup "$builddir" --cross-file "$crossfile" \
             -Dfeishu=true -Dtelegram=true 2>&1) || true

    if echo "$output" | grep -q "not supported on bare-metal"; then
        echo "  PASS: ${platform}: ${label} (Meson rejected feishu/telegram)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${platform}: ${label} (override was NOT rejected)"
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$builddir"
}

expect_im_rejected vexpress-a9 "feishu/telegram override"
expect_im_rejected zynq-a9 "feishu/telegram override"

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "  STATUS: FAILED"
    exit 1
fi

echo "  STATUS: OK"
exit 0
