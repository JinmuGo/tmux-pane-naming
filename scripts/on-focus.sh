#!/usr/bin/env bash
# Triggered on pane-focus-in: auto-name via fingerprint-based change detection
# Names ALL panes (not just AI sessions), skips manually named panes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip if pane was manually named
manual=$(tmux display-message -p '#{@pane_name_manual}' 2>/dev/null)
if [ "$manual" = "1" ]; then
    exit 0
fi

# Run auto-name with auto-trigger flag (suppresses display-message)
AUTO_TRIGGER=1 "$SCRIPT_DIR/auto-name.sh" --no-llm &
