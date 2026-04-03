#!/usr/bin/env bash
# Background daemon that periodically auto-names unnamed AI panes
# Usage: watch-panes.sh [interval_seconds]
# Stop:  tmux set-environment -g -u SENTINEL_NAMING_PID

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL="${1:-60}"

# Store PID so it can be stopped
tmux set-environment -g SENTINEL_NAMING_PID "$$"

cleanup() {
    tmux set-environment -g -u SENTINEL_NAMING_PID 2>/dev/null
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    # Check if we should stop
    stored_pid=$(tmux show-environment -g SENTINEL_NAMING_PID 2>/dev/null | cut -d= -f2)
    if [ "$stored_pid" != "$$" ]; then
        exit 0
    fi

    "$SCRIPT_DIR/auto-name-all.sh" 2>/dev/null
    sleep "$INTERVAL"
done
