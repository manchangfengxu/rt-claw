#!/bin/bash

set -euo pipefail

targets="${1:-esp32s3}"
extra_tools="${2:-none}"

ESP_ROOT="${ESP_ROOT:-$HOME/esp}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$ESP_ROOT/esp-idf}"
ESP_IDF_TAG="${ESP_IDF_TAG:-v5.4}"

mkdir -p "$ESP_ROOT"

if [ ! -d "$ESP_IDF_DIR/.git" ]; then
    git clone -b "$ESP_IDF_TAG" --depth 1 --recursive \
        https://github.com/espressif/esp-idf.git "$ESP_IDF_DIR"
fi

cd "$ESP_IDF_DIR"
git submodule update --init --recursive --depth 1
./install.sh "$targets"

if [ "$extra_tools" != "none" ]; then
    IFS=',' read -r -a tools <<< "$extra_tools"
    for tool in "${tools[@]}"; do
        if [ -n "$tool" ]; then
            python3 tools/idf_tools.py install "$tool"
        fi
    done
fi
