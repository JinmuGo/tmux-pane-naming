#!/usr/bin/env bash
# Tests for process-based naming functions
# Run: bash tests/test_process.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# Source the functions
eval "$(awk '/^_process_to_activity\(\)/,/^}/' "$SCRIPT_DIR/scripts/auto-name.sh")"
eval "$(awk '/^detect_name_by_process\(\)/,/^}/' "$SCRIPT_DIR/scripts/auto-name.sh")"

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $test_name"
        echo "  expected: '$expected'"
        echo "  actual:   '$actual'"
    fi
}

# ─── Process to Activity mapping ───

assert_eq "process: claude" "ai:claude" "$(_process_to_activity "claude")"
assert_eq "process: aider" "ai:aider" "$(_process_to_activity "aider")"
assert_eq "process: nvim" "vim" "$(_process_to_activity "nvim")"
assert_eq "process: vim" "vim" "$(_process_to_activity "vim")"
assert_eq "process: emacs" "emacs" "$(_process_to_activity "emacs")"
assert_eq "process: code" "vscode" "$(_process_to_activity "code")"
assert_eq "process: node" "node" "$(_process_to_activity "node")"
assert_eq "process: python3" "python" "$(_process_to_activity "python3")"
assert_eq "process: go" "go" "$(_process_to_activity "go")"
assert_eq "process: cargo" "rust" "$(_process_to_activity "cargo")"
assert_eq "process: docker" "docker" "$(_process_to_activity "docker")"
assert_eq "process: kubectl" "k8s" "$(_process_to_activity "kubectl")"
assert_eq "process: k9s" "k8s" "$(_process_to_activity "k9s")"
assert_eq "process: terraform" "infra" "$(_process_to_activity "terraform")"
assert_eq "process: psql" "pg" "$(_process_to_activity "psql")"
assert_eq "process: mysql" "mysql" "$(_process_to_activity "mysql")"
assert_eq "process: redis-cli" "redis" "$(_process_to_activity "redis-cli")"
assert_eq "process: ssh" "remote" "$(_process_to_activity "ssh")"
assert_eq "process: htop" "monitor" "$(_process_to_activity "htop")"
assert_eq "process: lazygit" "git" "$(_process_to_activity "lazygit")"
assert_eq "process: gh" "github" "$(_process_to_activity "gh")"
assert_eq "process: make" "build" "$(_process_to_activity "make")"
assert_eq "process: man" "docs" "$(_process_to_activity "man")"
assert_eq "process: npm" "npm" "$(_process_to_activity "npm")"
assert_eq "process: brew" "brew" "$(_process_to_activity "brew")"

# Shells should return empty
assert_eq "process: bash (shell)" "" "$(_process_to_activity "bash")"
assert_eq "process: zsh (shell)" "" "$(_process_to_activity "zsh")"
assert_eq "process: fish (shell)" "" "$(_process_to_activity "fish")"

# Unknown should return empty
assert_eq "process: unknown" "" "$(_process_to_activity "someunknowntool")"

# ─── Name composition (detect_name_by_process) ───

assert_eq "compose: claude + project" "claude:my-app" \
    "$(detect_name_by_process "claude" "my-app")"

assert_eq "compose: nvim + project" "my-app:vim" \
    "$(detect_name_by_process "nvim" "my-app")"

assert_eq "compose: docker + project" "my-app:docker" \
    "$(detect_name_by_process "docker" "my-app")"

assert_eq "compose: ssh no project" "remote" \
    "$(detect_name_by_process "ssh" "")"

assert_eq "compose: node + project" "my-app:node" \
    "$(detect_name_by_process "node" "my-app")"

assert_eq "compose: shell + project" "my-app" \
    "$(detect_name_by_process "zsh" "my-app")"

assert_eq "compose: shell no project" "" \
    "$(detect_name_by_process "zsh" "")"

assert_eq "compose: htop no project" "monitor" \
    "$(detect_name_by_process "htop" "")"

assert_eq "compose: psql + project" "my-app:pg" \
    "$(detect_name_by_process "psql" "my-app")"

# ─── Results ───

echo ""
echo "═══════════════════════════"
echo "Results: $PASS passed, $FAIL failed (total: $((PASS + FAIL)))"
echo "═══════════════════════════"

exit $FAIL
