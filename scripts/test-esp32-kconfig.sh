#!/bin/bash
# SPDX-License-Identifier: MIT
#
# test-esp32-kconfig.sh — ESP32 Kconfig custom variation builds (Tier 5)
#
# Tests custom sdkconfig variations for ESP32-C3 and ESP32-S3 QEMU.
# Each variation creates a temporary sdkconfig.defaults, builds, then restores.
# Requires: ESP-IDF environment sourced.
#
# Usage:
#   scripts/test-esp32-kconfig.sh [--c3-only | --s3-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

PASS=0
FAIL=0
RUN_C3=true
RUN_S3=true
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

for arg in "$@"; do
    case "$arg" in
        --c3-only) RUN_S3=false ;;
        --s3-only) RUN_C3=false ;;
        --help|-h)
            echo "Usage: $0 [--c3-only | --s3-only]"
            exit 0
            ;;
    esac
done

if ! command -v idf.py > /dev/null 2>&1; then
    echo "ERROR: idf.py not found. Source ESP-IDF environment first:"
    echo "  source ~/esp/esp-idf/export.sh"
    exit 1
fi

# Generate a temporary sdkconfig.defaults with custom overrides.
# Takes platform/board paths and a list of "KEY=val" pairs as arguments.
build_kconfig_combo() {
    local platform="$1"
    local board="$2"
    local label="$3"
    local make_target="$4"
    shift 4

    local defaults_dir="platform/${platform}/boards/${board}"
    local defaults_file="${defaults_dir}/sdkconfig.defaults"
    local build_dir="build/${platform}-${board}"
    local backup="${defaults_file}.bak"

    echo "--- ${platform}/${board}: ${label} ---"

    # Backup original (register for trap-based restore)
    if [ ! -f "$backup" ]; then
        cp "$defaults_file" "$backup"
        BACKUP_FILES+=("$backup")
    else
        cp "$defaults_file" "$backup"
    fi

    # Apply overrides: append to defaults, later values win in sdkconfig
    for override in "$@"; do
        local key="${override%%=*}"
        local val="${override#*=}"
        # Remove existing line if present, then append new value
        sed -i "/^CONFIG_${key}=/d; /^# CONFIG_${key} is not set/d" "$defaults_file"
        if [ "$val" = "y" ]; then
            echo "CONFIG_${key}=y" >> "$defaults_file"
        elif [ "$val" = "n" ]; then
            echo "# CONFIG_${key} is not set" >> "$defaults_file"
        else
            echo "CONFIG_${key}=\"${val}\"" >> "$defaults_file"
        fi
    done

    rm -rf "$build_dir"

    if make "$make_target" > /dev/null 2>&1; then
        echo "  PASS: ${platform}/${board}: ${label}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${platform}/${board}: ${label}"
        FAIL=$((FAIL + 1))
    fi

    # Restore original
    mv "$backup" "$defaults_file"
}

echo "=== ESP32 Kconfig Custom Variations ==="
echo ""

# --- ESP32-C3 QEMU variations ---
if [ "$RUN_C3" = true ]; then
    echo "=== ESP32-C3 QEMU ==="

    # T5.1 Minimal: shell only
    build_kconfig_combo esp32c3 qemu "minimal (shell only)" build-esp32c3-qemu \
        RTCLAW_SWARM_ENABLE=n \
        RTCLAW_SCHED_ENABLE=n \
        RTCLAW_SKILL_ENABLE=n \
        RTCLAW_LCD_ENABLE=n \
        RTCLAW_FEISHU_ENABLE=n \
        RTCLAW_TELEGRAM_ENABLE=n \
        RTCLAW_TOOL_GPIO=n \
        RTCLAW_TOOL_SYSTEM=n \
        RTCLAW_TOOL_SCHED=n \
        RTCLAW_TOOL_NET=n \
        RTCLAW_TOOL_LCD=n

    # T5.2 IM-only: shell + Feishu + Telegram
    build_kconfig_combo esp32c3 qemu "IM-only" build-esp32c3-qemu \
        RTCLAW_SWARM_ENABLE=n \
        RTCLAW_SCHED_ENABLE=n \
        RTCLAW_SKILL_ENABLE=n \
        RTCLAW_LCD_ENABLE=n \
        RTCLAW_FEISHU_ENABLE=y \
        RTCLAW_TELEGRAM_ENABLE=y \
        RTCLAW_TOOL_GPIO=n \
        RTCLAW_TOOL_SYSTEM=n \
        RTCLAW_TOOL_SCHED=n \
        RTCLAW_TOOL_NET=n \
        RTCLAW_TOOL_LCD=n

    # T5.3 Full + OTA
    build_kconfig_combo esp32c3 qemu "full + OTA" build-esp32c3-qemu \
        RTCLAW_SWARM_ENABLE=y \
        RTCLAW_SCHED_ENABLE=y \
        RTCLAW_SKILL_ENABLE=y \
        RTCLAW_LCD_ENABLE=y \
        RTCLAW_FEISHU_ENABLE=y \
        RTCLAW_TELEGRAM_ENABLE=y \
        RTCLAW_OTA_ENABLE=y \
        RTCLAW_TOOL_GPIO=y \
        RTCLAW_TOOL_SYSTEM=y \
        RTCLAW_TOOL_SCHED=y \
        RTCLAW_TOOL_NET=y \
        RTCLAW_TOOL_LCD=y

    # T5.4 No shell (headless)
    build_kconfig_combo esp32c3 qemu "no shell (headless)" build-esp32c3-qemu \
        RTCLAW_SHELL_ENABLE=n \
        RTCLAW_FEISHU_ENABLE=y

    # T5.5 Heartbeat
    build_kconfig_combo esp32c3 qemu "heartbeat" build-esp32c3-qemu \
        RTCLAW_SCHED_ENABLE=y \
        RTCLAW_HEARTBEAT_ENABLE=y

    echo ""
fi

# --- ESP32-S3 QEMU variations ---
if [ "$RUN_S3" = true ]; then
    echo "=== ESP32-S3 QEMU ==="

    # T5.6 Minimal: shell only
    build_kconfig_combo esp32s3 qemu "minimal (shell only)" build-esp32s3-qemu \
        RTCLAW_SWARM_ENABLE=n \
        RTCLAW_SCHED_ENABLE=n \
        RTCLAW_SKILL_ENABLE=n \
        RTCLAW_LCD_ENABLE=n \
        RTCLAW_FEISHU_ENABLE=n \
        RTCLAW_TELEGRAM_ENABLE=n \
        RTCLAW_TOOL_GPIO=n \
        RTCLAW_TOOL_SYSTEM=n \
        RTCLAW_TOOL_SCHED=n \
        RTCLAW_TOOL_NET=n \
        RTCLAW_TOOL_LCD=n

    # T5.7 Mouse tools
    build_kconfig_combo esp32s3 qemu "mouse tools" build-esp32s3-qemu \
        RTCLAW_USB_HID_MOUSE=y \
        RTCLAW_TOOL_MOUSE=y

    # T5.8 Full + OTA + Mouse
    build_kconfig_combo esp32s3 qemu "full + OTA + mouse" build-esp32s3-qemu \
        RTCLAW_SWARM_ENABLE=y \
        RTCLAW_SCHED_ENABLE=y \
        RTCLAW_SKILL_ENABLE=y \
        RTCLAW_LCD_ENABLE=y \
        RTCLAW_FEISHU_ENABLE=y \
        RTCLAW_TELEGRAM_ENABLE=y \
        RTCLAW_OTA_ENABLE=y \
        RTCLAW_USB_HID_MOUSE=y \
        RTCLAW_TOOL_GPIO=y \
        RTCLAW_TOOL_SYSTEM=y \
        RTCLAW_TOOL_SCHED=y \
        RTCLAW_TOOL_NET=y \
        RTCLAW_TOOL_LCD=y \
        RTCLAW_TOOL_MOUSE=y

    # T5.9 IM-only
    build_kconfig_combo esp32s3 qemu "IM-only" build-esp32s3-qemu \
        RTCLAW_SWARM_ENABLE=n \
        RTCLAW_SCHED_ENABLE=n \
        RTCLAW_SKILL_ENABLE=n \
        RTCLAW_LCD_ENABLE=n \
        RTCLAW_FEISHU_ENABLE=y \
        RTCLAW_TELEGRAM_ENABLE=y \
        RTCLAW_TOOL_GPIO=n \
        RTCLAW_TOOL_SYSTEM=n \
        RTCLAW_TOOL_SCHED=n \
        RTCLAW_TOOL_NET=n \
        RTCLAW_TOOL_LCD=n

    echo ""
fi

# --- Negative tests: Kconfig dependency violations ---
echo "=== Negative Tests (expect build failure) ==="

verify_kconfig_dep_resolved() {
    local platform="$1"
    local board="$2"
    local label="$3"
    local make_target="$4"
    local expect_disabled="$5"
    shift 5

    local defaults_dir="platform/${platform}/boards/${board}"
    local defaults_file="${defaults_dir}/sdkconfig.defaults"
    local build_dir="build/${platform}-${board}"
    local sdkconfig="${build_dir}/idf/sdkconfig"
    local backup="${defaults_file}.bak"

    echo "--- ${platform}/${board}: ${label} (verify dep resolved) ---"

    if [ ! -f "$backup" ]; then
        cp "$defaults_file" "$backup"
        BACKUP_FILES+=("$backup")
    else
        cp "$defaults_file" "$backup"
    fi

    for override in "$@"; do
        local key="${override%%=*}"
        local val="${override#*=}"
        sed -i "/^CONFIG_${key}=/d; /^# CONFIG_${key} is not set/d" "$defaults_file"
        if [ "$val" = "y" ]; then
            echo "CONFIG_${key}=y" >> "$defaults_file"
        elif [ "$val" = "n" ]; then
            echo "# CONFIG_${key} is not set" >> "$defaults_file"
        fi
    done

    rm -rf "$build_dir"

    if make "$make_target" > /dev/null 2>&1; then
        # Build succeeded; check that confgen resolved the dependency
        if grep -q "# CONFIG_${expect_disabled} is not set" "$sdkconfig" 2>/dev/null || \
           ! grep -q "CONFIG_${expect_disabled}=y" "$sdkconfig" 2>/dev/null; then
            echo "  PASS: ${label} (Kconfig resolved: ${expect_disabled} disabled)"
            PASS=$((PASS + 1))
        else
            echo "  FAIL: ${label} (${expect_disabled} should be disabled but is enabled)"
            FAIL=$((FAIL + 1))
        fi
    else
        # Build failed — also acceptable (hard dependency)
        echo "  PASS: ${label} (build correctly rejected)"
        PASS=$((PASS + 1))
    fi

    mv "$backup" "$defaults_file"
}

# heartbeat without sched: Kconfig should resolve by disabling heartbeat
if [ "$RUN_C3" = true ]; then
    verify_kconfig_dep_resolved esp32c3 qemu \
        "heartbeat without sched" build-esp32c3-qemu \
        RTCLAW_HEARTBEAT_ENABLE \
        RTCLAW_SCHED_ENABLE=n \
        RTCLAW_HEARTBEAT_ENABLE=y
fi

# TOOL_MOUSE without USB_HID_MOUSE: Kconfig should resolve by disabling TOOL_MOUSE
if [ "$RUN_S3" = true ]; then
    verify_kconfig_dep_resolved esp32s3 qemu \
        "TOOL_MOUSE without USB_HID_MOUSE" build-esp32s3-qemu \
        RTCLAW_TOOL_MOUSE \
        RTCLAW_USB_HID_MOUSE=n \
        RTCLAW_TOOL_MOUSE=y
fi

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
