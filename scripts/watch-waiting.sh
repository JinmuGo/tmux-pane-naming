#!/usr/bin/env bash
# Background daemon that periodically scans all panes for input-waiting state.
# Sets per-pane @pane_waiting and per-window @window_waiting options.
# When a pane transitions to waiting, optionally rings the tmux bell.
#
# Usage: watch-waiting.sh [interval_seconds]
# Stop:  tmux set-environment -g -u SENTINEL_WAITING_PID

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${1:-3}"

# Store PID so it can be stopped
tmux set-environment -g SENTINEL_WAITING_PID "$$"

cleanup() {
    tmux set-environment -g -u SENTINEL_WAITING_PID 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

# Check if bell notification is enabled
bell_enabled=$(tmux show-option -gqv "@sentinel-waiting-bell" 2>/dev/null)

while true; do
    # Check if we should stop (PID mismatch = replaced by newer instance)
    stored_pid=$(tmux show-environment -g SENTINEL_WAITING_PID 2>/dev/null | cut -d= -f2)
    if [ "$stored_pid" != "$$" ]; then
        exit 0
    fi

    # ─── Scan all panes ───
    while IFS=$'\t' read -r pane_id window_target; do
        # Save previous state for transition detection
        prev=$(tmux display-message -p -t "$pane_id" '#{@pane_waiting}' 2>/dev/null)

        # Run detection
        "$SCRIPT_DIR/check-waiting.sh" "$pane_id"

        # Check new state
        curr=$(tmux display-message -p -t "$pane_id" '#{@pane_waiting}' 2>/dev/null)

        # Transition: not-waiting → waiting → ring bell on the window
        if [ -z "$prev" ] && [ -n "$curr" ] && [ "$bell_enabled" != "off" ]; then
            # Write BEL to the pane's tty to trigger tmux's monitor-bell
            pane_tty=$(tmux display-message -p -t "$pane_id" '#{pane_tty}' 2>/dev/null)
            if [ -n "$pane_tty" ] && [ -e "$pane_tty" ]; then
                printf '\a' > "$pane_tty" 2>/dev/null
            fi
        fi
    done < <(tmux list-panes -a -F '#{pane_id}	#{session_name}:#{window_index}' 2>/dev/null)

    # ─── Aggregate per-window flags ───
    while IFS= read -r win; do
        has_waiting=""
        while IFS= read -r pane_id; do
            pw=$(tmux display-message -p -t "$pane_id" '#{@pane_waiting}' 2>/dev/null)
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
    done < <(tmux list-windows -a -F '#{session_name}:#{window_index}' 2>/dev/null)

    sleep "$INTERVAL"
done
