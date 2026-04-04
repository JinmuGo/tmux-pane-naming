#!/usr/bin/env bash
# Claude Code hook for tmux-sentinel HITL detection.
# Receives JSON on stdin with hook_event_name.
#
# Stop                → Claude finished responding → set waiting
# UserPromptSubmit    → User sent input            → clear waiting
# Notification        → Permission prompt, etc.    → set waiting (permission)
#
# Requires: $TMUX_PANE (set automatically inside tmux)

# Bail if not inside tmux
[ -z "$TMUX" ] && exit 0
[ -z "$TMUX_PANE" ] && exit 0

# Read JSON from stdin
input=$(cat)
event=$(echo "$input" | grep -o '"hook_event_name":"[^"]*"' | head -1 | cut -d'"' -f4)

# Read sentinel config
waiting_bg=$(tmux show-option -gqv "@sentinel-waiting-bg" 2>/dev/null)
[ -z "$waiting_bg" ] && waiting_bg="#e0af68"
bell_enabled=$(tmux show-option -gqv "@sentinel-waiting-bell" 2>/dev/null)

# ─── Helpers ───

_set_waiting() {
    local wait_type="$1"
    tmux set-option -p -t "$TMUX_PANE" @pane_waiting "$wait_type" 2>/dev/null
    # Highlight pane border
    tmux set-option -p -t "$TMUX_PANE" pane-active-border-style "fg=${waiting_bg}" 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" pane-border-style "fg=${waiting_bg}" 2>/dev/null
    # Ring bell for cross-window alert
    if [ "$bell_enabled" != "off" ]; then
        local pane_tty
        pane_tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
        if [ -n "$pane_tty" ] && [ -e "$pane_tty" ]; then
            printf '\a' > "$pane_tty" 2>/dev/null
        fi
    fi
    _update_window
}

_clear_waiting() {
    tmux set-option -p -t "$TMUX_PANE" -u @pane_waiting 2>/dev/null
    # Reset border
    tmux set-option -p -t "$TMUX_PANE" -u pane-active-border-style 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" -u pane-border-style 2>/dev/null
    _update_window
}

_update_window() {
    # Aggregate @pane_waiting across all panes in this window
    local win
    win=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}' 2>/dev/null)
    [ -z "$win" ] && return

    local has_waiting=""
    while IFS= read -r pid; do
        local pw
        pw=$(tmux display-message -p -t "$pid" '#{@pane_waiting}' 2>/dev/null)
        if [ -n "$pw" ]; then
            has_waiting="$pw"
            break
        fi
    done < <(tmux list-panes -t "$win" -F '#{pane_id}' 2>/dev/null)

    if [ -n "$has_waiting" ]; then
        tmux set-option -w -t "$win" @window_waiting "$has_waiting" 2>/dev/null
    else
        tmux set-option -w -t "$win" -u @window_waiting 2>/dev/null
    fi
}

# ─── Event handling ───

case "$event" in
    Stop)
        _set_waiting "input"
        ;;
    UserPromptSubmit)
        _clear_waiting
        ;;
    Notification)
        # Check notification type
        ntype=$(echo "$input" | grep -o '"notification_type":"[^"]*"' | head -1 | cut -d'"' -f4)
        case "$ntype" in
            permission_prompt)
                _set_waiting "permission"
                ;;
        esac
        ;;
esac

exit 0
