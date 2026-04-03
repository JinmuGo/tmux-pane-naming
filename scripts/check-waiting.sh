#!/usr/bin/env bash
# Detect if a pane's foreground program is waiting for user input.
# Sets the pane option @pane_waiting to the wait type (input|permission|prompt)
# or unsets it when the pane is not waiting.
#
# Usage: check-waiting.sh [pane_id]

TARGET="${1:-}"

# ─── Helpers ───

_tmux_opt() {
    local flag="$1" opt="$2"
    shift 2
    if [ -n "$TARGET" ]; then
        tmux "$flag" -p -t "$TARGET" "$opt" "$@" 2>/dev/null
    else
        tmux "$flag" -p "$opt" "$@" 2>/dev/null
    fi
}

_set_waiting() {
    _tmux_opt set-option @pane_waiting "$1"
}

_clear_waiting() {
    _tmux_opt set-option -u @pane_waiting
}

_get_process() {
    if [ -n "$TARGET" ]; then
        tmux display-message -p -t "$TARGET" '#{pane_current_command}' 2>/dev/null
    else
        tmux display-message -p '#{pane_current_command}' 2>/dev/null
    fi
}

_capture() {
    local lines="${1:-15}"
    local args=(-p -l "$lines")
    [ -n "$TARGET" ] && args+=(-t "$TARGET")
    tmux capture-pane "${args[@]}" 2>/dev/null
}

# ─── Detection ───

detect_claude_waiting() {
    local content="$1"

    # Claude Code shows "-- INSERT --" or "-- NORMAL --" only when at the
    # input prompt. While generating or running tools, these are NOT visible.
    if echo "$content" | grep -qE -- "-- INSERT --|-- NORMAL --"; then
        # Distinguish permission prompts from regular input
        if echo "$content" | grep -qiE "Allow|Deny|approve|reject"; then
            echo "permission"
        else
            echo "input"
        fi
        return 0
    fi
    return 1
}

detect_aider_waiting() {
    local content="$1"
    local last_lines
    last_lines=$(echo "$content" | tail -5)

    # Aider shows "aider> " or "> " when waiting for input
    if echo "$last_lines" | grep -qE '(aider|architect)> *$|^> *$'; then
        echo "input"
        return 0
    fi
    return 1
}

detect_generic_waiting() {
    local content="$1"
    local last_line
    last_line=$(echo "$content" | grep -v '^[[:space:]]*$' | tail -1)

    # Common interactive prompt patterns
    # Avoid false positives by requiring the pattern at the end of the line
    if echo "$last_line" | grep -qE '\(y/n\) *$|\(Y/N\) *$|\(yes/no\) *$'; then
        echo "confirm"
        return 0
    fi
    if echo "$last_line" | grep -qE '[Pp]assword: *$|[Tt]oken: *$|[Ss]ecret: *$'; then
        echo "secret"
        return 0
    fi
    if echo "$last_line" | grep -qE '[Ee]nter .*: *$|[Pp]ress .* to continue'; then
        echo "prompt"
        return 0
    fi
    return 1
}

# ─── Main ───

proc=$(_get_process)

# Shells are always "waiting" at their prompt — skip
case "$proc" in
    bash|zsh|sh|fish|dash|login)
        _clear_waiting
        exit 0
        ;;
esac

content=$(_capture 20)
[ -z "$content" ] && exit 0

waiting=""

# Claude Code / claude
if [ "$proc" = "claude" ] || [ "$proc" = "claude-code" ] \
    || echo "$content" | grep -qE "Claude Code|Model:.*claude"; then
    waiting=$(detect_claude_waiting "$content")
fi

# Aider
if [ -z "$waiting" ]; then
    if [ "$proc" = "aider" ] || echo "$content" | grep -qiE "aider>|Aider v"; then
        waiting=$(detect_aider_waiting "$content")
    fi
fi

# Generic interactive programs (not shells, not editors)
if [ -z "$waiting" ]; then
    case "$proc" in
        vim|nvim|vi|nano|emacs|less|man|htop|top|btop) ;; # skip always-interactive
        *) waiting=$(detect_generic_waiting "$content") ;;
    esac
fi

# Apply result
if [ -n "$waiting" ]; then
    _set_waiting "$waiting"
else
    _clear_waiting
fi
