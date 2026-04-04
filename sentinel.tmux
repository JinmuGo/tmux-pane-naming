#!/usr/bin/env bash

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default options
default_key="N"
default_fg="#1a1b26"
default_bg="#7aa2f7"
default_border_status="bottom"
default_waiting_fg="#1a1b26"
default_waiting_bg="#e0af68"
default_waiting_icon="⏳"
default_waiting_interval="3"

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local value
    value=$(tmux show-option -gqv "$option")
    if [ -z "$value" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

# Read user options
key=$(get_tmux_option "@sentinel-key" "$default_key")
fg=$(get_tmux_option "@sentinel-fg" "$default_fg")
bg=$(get_tmux_option "@sentinel-bg" "$default_bg")
border_status=$(get_tmux_option "@sentinel-border-status" "$default_border_status")
waiting_fg=$(get_tmux_option "@sentinel-waiting-fg" "$default_waiting_fg")
waiting_bg=$(get_tmux_option "@sentinel-waiting-bg" "$default_waiting_bg")
waiting_icon=$(get_tmux_option "@sentinel-waiting-icon" "$default_waiting_icon")
waiting_mode=$(get_tmux_option "@sentinel-waiting" "on")
waiting_interval=$(get_tmux_option "@sentinel-waiting-interval" "$default_waiting_interval")

# Build pane border format with optional waiting indicator
# When @pane_waiting is set → warning color + icon
# Otherwise → normal color
# Store formats as tmux options to avoid comma conflicts in #{?} conditionals
tmux set-option -g @sentinel-fmt-normal "#[fg=${fg},bg=${bg},bold] #{@pane_name} #[default]"
tmux set-option -g @sentinel-fmt-waiting "#[fg=${waiting_fg},bg=${waiting_bg},bold] ${waiting_icon} #{@pane_name} #[default]"

# Enable pane border status
tmux set-option -g pane-border-status "$border_status"

# Set pane border format — use #{E:} to expand stored formats
tmux set-option -g pane-border-format "#{?@pane_name,#{?@pane_waiting,#{E:@sentinel-fmt-waiting},#{E:@sentinel-fmt-normal}},}"

# ─── Window status bar waiting indicator ───
# When a window has a pane waiting for input, prepend a small marker to the window name.
# Replace #W with #{?@window_waiting,* #W,#W} in both formats.
if [ "$waiting_mode" != "off" ]; then
    waiting_marker=$(get_tmux_option "@sentinel-waiting-marker" "*")

    current_ws_fmt=$(tmux show-option -gv window-status-format 2>/dev/null)
    if ! echo "$current_ws_fmt" | grep -q "@window_waiting"; then
        new_ws_fmt=$(echo "$current_ws_fmt" | sed "s/#W/#{?@window_waiting,${waiting_marker} #W,#W}/g")
        tmux set-option -g window-status-format "$new_ws_fmt"
    fi

    current_wsc_fmt=$(tmux show-option -gv window-status-current-format 2>/dev/null)
    if ! echo "$current_wsc_fmt" | grep -q "@window_waiting"; then
        new_wsc_fmt=$(echo "$current_wsc_fmt" | sed "s/#W/#{?@window_waiting,${waiting_marker} #W,#W}/g")
        tmux set-option -g window-status-current-format "$new_wsc_fmt"
    fi
fi

# prefix + N → manual name input (sets @pane_name_manual flag)
tmux bind-key "$key" command-prompt -p "Pane name:" \
    "set-option -p @pane_name '%%' \\; set-option -p @pane_name_manual 1"

# prefix + M-n → clear pane name + manual flag
tmux bind-key M-n set-option -p -u @pane_name \\\; set-option -p -u @pane_name_manual \\\; set-option -p -u @pane_name_hash

# prefix + M-N → auto-name current pane
tmux bind-key M-N run-shell "$CURRENT_DIR/scripts/auto-name.sh"

# prefix + C-n → auto-name all panes
tmux bind-key C-n run-shell "$CURRENT_DIR/scripts/auto-name-all.sh"

# ─── Auto-naming trigger ───
# Options: off, focus, interval, both (default: focus)
auto_mode=$(get_tmux_option "@sentinel-auto" "focus")
auto_interval=$(get_tmux_option "@sentinel-auto-interval" "60")

# Stop any existing watch daemon
old_pid=$(tmux show-environment -g SENTINEL_NAMING_PID 2>/dev/null | cut -d= -f2)
if [ -n "$old_pid" ] && [ "$old_pid" != "-SENTINEL_NAMING_PID" ]; then
    kill "$old_pid" 2>/dev/null
    tmux set-environment -g -u SENTINEL_NAMING_PID 2>/dev/null
fi

# Use namespaced hook index to avoid clobbering other plugins' hooks
hook_name="after-select-pane[42]"

case "$auto_mode" in
    focus)
        tmux set-hook -g "$hook_name" "run-shell '$CURRENT_DIR/scripts/on-focus.sh'"
        ;;
    interval)
        "$CURRENT_DIR/scripts/watch-panes.sh" "$auto_interval" </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null
        ;;
    focus+interval|both)
        tmux set-hook -g "$hook_name" "run-shell '$CURRENT_DIR/scripts/on-focus.sh'"
        "$CURRENT_DIR/scripts/watch-panes.sh" "$auto_interval" </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null
        ;;
    off|*)
        tmux set-hook -gu "$hook_name" 2>/dev/null
        ;;
esac

# ─── Input-waiting detection ───
# Detection is driven by Claude Code hooks (Stop, UserPromptSubmit, Notification)
# via scripts/sentinel-hook.sh — no background daemon needed.
# Stop any leftover daemon from previous versions.
if [ "$waiting_mode" != "off" ]; then
    old_waiting_pid=$(tmux show-environment -g SENTINEL_WAITING_PID 2>/dev/null | cut -d= -f2)
    if [ -n "$old_waiting_pid" ] && [ "$old_waiting_pid" != "-SENTINEL_WAITING_PID" ]; then
        kill "$old_waiting_pid" 2>/dev/null
        tmux set-environment -g -u SENTINEL_WAITING_PID 2>/dev/null
    fi

    # Enable bell monitoring for cross-window alerts
    tmux set-option -g monitor-bell on
    tmux set-option -g bell-action other
fi

# Register the plugin directory for programmatic access
tmux set-environment -g TMUX_SENTINEL_DIR "$CURRENT_DIR"
