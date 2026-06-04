#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
#
# Generate Meson cross-file for Zephyr from compile_commands.json.
# Extracts the exact compiler flags Zephyr uses so that Meson-compiled
# rt-claw OSAL code sees the same definitions and include paths.
#
# Usage:
#   python3 scripts/gen-zephyr-cross.py [board]

import argparse
import json
import os
import shlex
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PAIRED_FLAGS = {
    '-imacros', '-isystem', '-include', '-idirafter',
    '-iquote', '-isysroot', '--sysroot', '-specs',
}

SKIP_FLAGS = {'-o', '-c', '-MF', '-MT', '-MD', '-MQ'}


def parse_args():
    parser = argparse.ArgumentParser(
        description='Generate Meson cross-file for Zephyr.')
    parser.add_argument('board', nargs='?', default='qemu_cortex_a9',
                        help='Zephyr board name (default: qemu_cortex_a9)')
    return parser.parse_args()


def extract_flags(cc_json_path):
    """Extract compiler and flags from compile_commands.json."""
    with open(cc_json_path) as f:
        commands = json.load(f)

    if not commands:
        return None, []

    cmd_str = commands[0].get('command', '')
    parts = shlex.split(cmd_str)

    if not parts:
        return None, []

    cc = parts[0]
    cflags = []
    i = 1

    while i < len(parts):
        p = parts[i]

        if p in SKIP_FLAGS:
            i += 2
            continue

        if p.endswith('.c') or p.endswith('.c.obj') or p.endswith('.o'):
            i += 1
            continue

        for prefix in PAIRED_FLAGS:
            if p == prefix and i + 1 < len(parts):
                cflags.append(p)
                cflags.append(parts[i + 1])
                i += 2
                break
            if p.startswith(prefix + '=') or (
                    p.startswith(prefix) and len(p) > len(prefix)):
                cflags.append(p)
                i += 1
                break
        else:
            if (p.startswith('-I') or p.startswith('-D') or
                    p.startswith('-m') or p.startswith('-f') or
                    p.startswith('-std') or p.startswith('-W') or
                    p.startswith('--param') or
                    p.startswith('--sysroot')):
                cflags.append(p)
            i += 1

    return cc, cflags


def main():
    args = parse_args()
    board = args.board

    board_build_dir = os.path.join(PROJECT_ROOT, 'build',
                                   f'zephyr-{board}')
    meson_build_dir = os.path.join(board_build_dir, 'meson')
    cc_json = os.path.join(board_build_dir, 'zephyr',
                           'compile_commands.json')
    cross_file = os.path.join(board_build_dir, 'cross.ini')

    if not os.path.exists(cc_json):
        print(f'ERROR: {cc_json} not found.', file=sys.stderr)
        print('Run the Zephyr CMake build first.', file=sys.stderr)
        sys.exit(1)

    cc, cflags = extract_flags(cc_json)
    if not cc:
        print('ERROR: Could not extract compiler', file=sys.stderr)
        sys.exit(1)

    cflags.append('-DCLAW_PLATFORM_ZEPHYR')
    cflags.append('-DCLAW_HAS_GENERATED_CONFIG')

    cflags = [f for f in cflags if '-Werror' not in f]
    cflags = [f for f in cflags if '-specs=' not in f]

    cc_dir = os.path.dirname(cc)
    prefix = os.path.basename(cc).replace('-gcc', '-')
    ar = os.path.join(cc_dir, prefix + 'ar')
    strip_tool = os.path.join(cc_dir, prefix + 'strip')

    os.makedirs(meson_build_dir, exist_ok=True)

    with open(cross_file, 'w') as f:
        f.write('[binaries]\n')
        f.write(f"c = '{cc}'\n")
        f.write(f"ar = '{ar}'\n")
        f.write(f"strip = '{strip_tool}'\n")
        f.write('\n')
        f.write('[built-in options]\n')

        cflags_repr = ', '.join(f"'{x}'" for x in cflags)
        f.write(f'c_args = [{cflags_repr}]\n')
        f.write("c_link_args = []\n")
        f.write('\n')
        f.write('[host_machine]\n')
        f.write("system = 'zephyr'\n")
        f.write("cpu_family = 'arm'\n")

        cpu = 'armv7-a' if 'cortex_a9' in board else 'arm'
        f.write(f"cpu = '{cpu}'\n")
        f.write("endian = 'little'\n")

    print(f'Cross-file written to {cross_file}')
    print(f'  Compiler: {cc}')
    print(f'  Board: {board}')
    print(f'  Flags: {len(cflags)} c_args')


if __name__ == '__main__':
    main()
