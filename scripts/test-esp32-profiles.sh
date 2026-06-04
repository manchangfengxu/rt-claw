#!/bin/bash
# SPDX-License-Identifier: MIT
#
# test-esp32-profiles.sh — ESP32 sdkconfig profile build test (Tier 3)
#
# Tests alternate sdkconfig profiles (demo, feishu) for ESP32-C3 and ESP32-S3
# QEMU builds. Uses backup+trap for reliable restore.
# Requires: ESP-IDF environment sourced.
#
# Usage:
#   scripts/test-esp32-profiles.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

PASS=0
FAIL=0
BACKUP_FILES=()

cleanup() {
    local rc=$?
    for bak in "${BACKUP_FILES[@]}"; do
        local orig="${bak%.bak}"
        if [ -f "$bak" ]; then
            mv "$bak" "$orig"
        fi
    done
    exit $rc
}
trap cleanup EXIT

if ! command -v idf.py > /dev/null 2>&1; then
    echo "ERROR: idf.py not found. Source ESP-IDF environment first:"
    echo "  source ~/esp/esp-idf/export.sh"
    exit 1
fi

test_profile() {
    local platform="$1"
    local board="$2"
    local profile="$3"
    local make_target="$4"
    local defaults_dir="platform/${platform}/boards/${board}"
    local defaults_file="${defaults_dir}/sdkconfig.defaults"
    local profile_file="${defaults_dir}/sdkconfig.defaults.${profile}"
    local build_dir="build/${platform}-${board}"
    local backup="${defaults_file}.bak"

    echo "--- ${platform}/${board}: ${profile} ---"

    if [ ! -f "$profile_file" ]; then
        echo "  SKIP: $profile_file not found"
        return
    fi

    # Backup original (only once per file)
    if [ ! -f "$backup" ]; then
        cp "$defaults_file" "$backup"
        BACKUP_FILES+=("$backup")
    fi

    # Swap profile in
    cp "$profile_file" "$defaults_file"
    rm -rf "$build_dir"

    if make "$make_target" > /dev/null 2>&1; then
        echo "  PASS: ${platform}/${board}: ${profile}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${platform}/${board}: ${profile}"
        FAIL=$((FAIL + 1))
    fi

    # Restore from backup immediately
    cp "$backup" "$defaults_file"
}

expect_build_fail() {
    local platform="$1"
    local board="$2"
    local label="$3"
    local make_target="$4"
    local defaults_dir="platform/${platform}/boards/${board}"
    local defaults_file="${defaults_dir}/sdkconfig.defaults"
    local build_dir="build/${platform}-${board}"
    local backup="${defaults_file}.bak"

    echo "--- ${platform}/${board}: ${label} (expect failure) ---"

    if [ ! -f "$backup" ]; then
        cp "$defaults_file" "$backup"
        BACKUP_FILES+=("$backup")
    fi

    # Point to a nonexistent partition table — ESP-IDF will fail
    # during build when the partition CSV cannot be found.
    sed -i '/^CONFIG_PARTITION_TABLE/d' "$defaults_file"
    echo "CONFIG_PARTITION_TABLE_CUSTOM=y" >> "$defaults_file"
    echo 'CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="nonexistent_corrupted_partition.csv"' >> "$defaults_file"
    rm -rf "$build_dir"

    if make "$make_target" > /dev/null 2>&1; then
        echo "  FAIL: ${label} (should have errored but succeeded)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: ${label} (correctly failed)"
        PASS=$((PASS + 1))
    fi

    # Restore
    cp "$backup" "$defaults_file"
}

echo "=== ESP32 sdkconfig Profile Builds ==="
echo ""

# ESP32-C3 QEMU profiles
echo "--- ESP32-C3 QEMU ---"
test_profile esp32c3 qemu "demo" "build-esp32c3-qemu"
test_profile esp32c3 qemu "feishu" "build-esp32c3-qemu"

echo ""

# ESP32-S3 QEMU profiles
echo "--- ESP32-S3 QEMU ---"
test_profile esp32s3 qemu "demo" "build-esp32s3-qemu"
test_profile esp32s3 qemu "feishu" "build-esp32s3-qemu"

# Negative: corrupted profile should cause build failure
echo ""
echo "--- Negative: corrupted profile ---"
expect_build_fail esp32c3 qemu "corrupted C3 profile" "build-esp32c3-qemu"
expect_build_fail esp32s3 qemu "corrupted S3 profile" "build-esp32s3-qemu"

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
