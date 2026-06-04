#!/bin/bash
# SPDX-License-Identifier: MIT
#
# check-dco.sh — verify Signed-off-by tags on commits
#
# Usage:
#   scripts/check-dco.sh [<base>]    Check commits since <base> (default: main)
#   scripts/check-dco.sh --last [N]  Check last N commits (default: 1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[FAIL]${NC} $*"; }

check_commits() {
    local range="$1"
    local errors=0

    local log
    log=$(git -C "$PROJECT_ROOT" log --format="%H %s" "$range" 2>/dev/null)
    if [ -z "$log" ]; then
        echo "No commits to check."
        return 0
    fi

    echo "Checking Signed-off-by on commits: $range"
    echo ""

    while IFS= read -r line; do
        local sha="${line%% *}"
        local subject="${line#* }"
        local msg
        msg=$(git -C "$PROJECT_ROOT" show -s --format="%B" "$sha")

        if echo "$msg" | grep -q "^Signed-off-by: .* <.*@.*>"; then
            # Check for localhost or invalid email
            if echo "$msg" | grep "^Signed-off-by:" | grep -q "localhost"; then
                error "$sha $subject"
                echo "       Bad email address (contains 'localhost') in Signed-off-by"
                errors=$((errors + 1))
            else
                info "$sha $subject"
            fi
        else
            error "$sha $subject"
            echo "       Missing or malformed Signed-off-by tag"
            errors=$((errors + 1))
        fi
    done <<< "$log"

    echo ""
    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}$errors commit(s) failed DCO check.${NC}"
        echo ""
        echo "Every commit must include:"
        echo "  Signed-off-by: Your Name <your@email.com>"
        echo ""
        echo "Use 'git commit -s' to add it automatically."
        echo "To fix existing commits: git rebase -i <base> -x 'git commit --amend --no-edit -s'"
        return 1
    else
        echo -e "${GREEN}All commits have valid Signed-off-by tags.${NC}"
        return 0
    fi
}

cd "$PROJECT_ROOT"

case "${1:-}" in
    --last|-l)
        n="${2:-1}"
        check_commits "HEAD~${n}..HEAD"
        ;;
    --help|-h)
        sed -n '3,9p' "$0" | sed 's/^# \?//'
        ;;
    *)
        base="${1:-main}"
        ancestor=$(git merge-base "$base" HEAD 2>/dev/null || echo "$base")
        check_commits "$ancestor..HEAD"
        ;;
esac
