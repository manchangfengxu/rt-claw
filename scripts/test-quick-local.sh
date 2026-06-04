#!/bin/bash
# SPDX-License-Identifier: MIT
#
# test-quick-local.sh — quick local build + smoke validation (Tier 1 + 2)
#
# Verifies default builds for non-ESP platforms and runs a Linux smoke test.
# ESP32 builds are skipped unless ESP-IDF is sourced.
#
# Usage:
#   scripts/test-quick-local.sh              Run all available platforms
#   scripts/test-quick-local.sh --with-esp   Include ESP32 builds (requires ESP-IDF)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

PASS=0
FAIL=0
SKIP=0
WITH_ESP=false

for arg in "$@"; do
    case "$arg" in
        --with-esp) WITH_ESP=true ;;
        --help|-h)
            echo "Usage: $0 [--with-esp]"
            echo "  --with-esp   Include ESP32 builds (requires ESP-IDF environment)"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

run_build() {
    local label="$1"
    local target="$2"
    echo "--- Build: $label ---"
    if make "$target" > /dev/null 2>&1; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label"
        FAIL=$((FAIL + 1))
    fi
}

check_tool() {
    command -v "$1" > /dev/null 2>&1
}

echo "=== Tier 1: Default Builds ==="

# Always available: Linux (no cross-compiler needed)
run_build "Linux (native)" "build-linux"

# ARM platforms: need arm-none-eabi-gcc
if check_tool arm-none-eabi-gcc; then
    run_build "vexpress-a9 (RT-Thread)" "vexpress-a9-qemu"
    run_build "zynq-a9 (FreeRTOS)" "build-zynq-a9-qemu"
else
    echo "  ERROR: arm-none-eabi-gcc not found in PATH"
    echo "  Install ARM cross-compiler to run ARM platform builds."
    FAIL=$((FAIL + 2))
fi

# ESP32 platforms: need ESP-IDF
if [ "$WITH_ESP" = true ]; then
    if check_tool idf.py; then
        run_build "ESP32-C3 QEMU" "build-esp32c3-qemu"
        run_build "ESP32-C3 devkit" "build-esp32c3-devkit"
        run_build "ESP32-C3 xiaozhi-xmini" "build-esp32c3-xiaozhi-xmini"
        run_build "ESP32-S3 QEMU" "build-esp32s3-qemu"
        run_build "ESP32-S3 (real hw)" "build-esp32s3"
    else
        echo "  ERROR: idf.py not found. Source ESP-IDF environment first:"
        echo "    source ~/esp/esp-idf/export.sh"
        FAIL=$((FAIL + 5))
    fi
fi

echo ""
echo "=== Tier 2: Smoke Run (Linux) ==="

if check_tool timeout; then
    echo "--- Smoke: Linux shell + /help ---"
    if timeout 10 make run-linux <<< '/help' > /dev/null 2>&1; then
        echo "  PASS: Linux smoke test"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Linux smoke test"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  SKIP: timeout command not available"
    SKIP=$((SKIP + 1))
fi

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"

if [ "$FAIL" -gt 0 ]; then
    echo "  STATUS: FAILED"
    exit 1
fi

echo "  STATUS: OK"
exit 0
