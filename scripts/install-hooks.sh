#!/bin/bash
# SPDX-License-Identifier: MIT
#
# install-hooks.sh — install git hooks for rt-claw development
#
# Usage:
#   scripts/install-hooks.sh           Install hooks
#   scripts/install-hooks.sh --remove  Remove hooks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

install_hooks() {
    # --- pre-commit hook ---
    cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
# rt-claw pre-commit hook: run checkpatch on staged changes

SCRIPT_DIR="$(git rev-parse --show-toplevel)/scripts"

if [ -x "$SCRIPT_DIR/check-patch.sh" ]; then
    "$SCRIPT_DIR/check-patch.sh" --staged
    if [ $? -ne 0 ]; then
        echo ""
        echo "Code style issues found. Fix them before committing."
        echo "Use 'git commit --no-verify' to bypass (not recommended)."
        exit 1
    fi
fi
HOOK
    chmod +x "$HOOKS_DIR/pre-commit"

    # --- commit-msg hook ---
    cat > "$HOOKS_DIR/commit-msg" << 'HOOK'
#!/bin/bash
# rt-claw commit-msg hook: validate commit message format

MSG_FILE="$1"
MSG=$(cat "$MSG_FILE")

FIRST_LINE=$(head -n1 "$MSG_FILE")
errors=0

# Check: first line should follow "subsystem: description" pattern
if ! echo "$FIRST_LINE" | grep -qE '^[a-zA-Z0-9_/.-]+: '; then
    echo "WARNING: commit subject should follow 'subsystem: description' format"
    echo "  Example: 'osal: add mutex timeout support'"
    echo "  Got: '$FIRST_LINE'"
fi

# Check: first line length
if [ ${#FIRST_LINE} -gt 76 ]; then
    echo "ERROR: commit subject exceeds 76 characters (${#FIRST_LINE})"
    errors=$((errors + 1))
fi

# Check: Signed-off-by
if ! grep -q "^Signed-off-by: .* <.*@.*>" "$MSG_FILE"; then
    echo "ERROR: missing Signed-off-by line"
    echo "  Use 'git commit -s' to add it automatically"
    errors=$((errors + 1))
fi

if [ $errors -gt 0 ]; then
    exit 1
fi
HOOK
    chmod +x "$HOOKS_DIR/commit-msg"

    echo -e "${GREEN}Git hooks installed:${NC}"
    echo "  - pre-commit  (code style check on staged changes)"
    echo "  - commit-msg  (commit message format validation)"
    echo ""
    echo -e "${YELLOW}Note:${NC} Use 'git commit --no-verify' to bypass hooks if needed."
}

remove_hooks() {
    rm -f "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/commit-msg"
    echo "Git hooks removed."
}

case "${1:-}" in
    --remove|-r)
        remove_hooks
        ;;
    --help|-h)
        sed -n '3,9p' "$0" | sed 's/^# \?//'
        ;;
    *)
        install_hooks
        ;;
esac
