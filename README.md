# tmux-sentinel

A tmux plugin that watches over your sessions — auto-names panes by analyzing terminal content and alerts you when programs are waiting for input.

## Features

- **Input-waiting detection**: Monitors when programs (Claude Code, Aider, etc.) are waiting for your input and shows a visual indicator on window tabs and pane borders
- **Smart auto-naming**: Analyzes pane content and generates descriptive names automatically
- **Zero-dependency mode**: Pattern matching detects AI tools, projects, git branches, and activities using only bash
- **LLM mode (optional)**: Uses a local ollama model for more accurate naming when available
- **AI session detection**: Recognizes Claude, Aider, Copilot, ChatGPT, Cursor, Gemini sessions
- **Manual naming**: Name panes with a simple keybinding prompt
- **Customizable colors**: Match your tmux theme with fg/bg options
- Background watch daemon for continuous auto-naming

## Requirements

- tmux 3.2+
- **Optional**: [ollama](https://ollama.ai) + `jq` + `python3` for LLM-powered naming

## Installation

### With TPM

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'JinmuGo/tmux-sentinel'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/JinmuGo/tmux-sentinel ~/.tmux/plugins/tmux-sentinel
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-sentinel/sentinel.tmux
```

Reload: `tmux source-file ~/.tmux.conf`

## Usage

### Keybindings

| Keybinding | Action |
|---|---|
| `prefix + N` | Manual name input (opens prompt) |
| `prefix + Alt-N` | Auto-name current pane |
| `prefix + Ctrl-n` | Auto-name all AI session panes |
| `prefix + Alt-n` | Clear pane name |

### Programmatic Usage

```bash
# Auto-name current pane
~/.tmux/plugins/tmux-sentinel/scripts/auto-name.sh

# Auto-name a specific pane
~/.tmux/plugins/tmux-sentinel/scripts/auto-name.sh -t %3

# Auto-name all unnamed AI session panes
~/.tmux/plugins/tmux-sentinel/scripts/auto-name-all.sh

# Start background watcher (auto-names every 60s)
~/.tmux/plugins/tmux-sentinel/scripts/watch-panes.sh 60 &

# Manual rename
~/.tmux/plugins/tmux-sentinel/scripts/rename-pane.sh "my-server"
~/.tmux/plugins/tmux-sentinel/scripts/rename-pane.sh -t %3 "my-server"

# Clear name
~/.tmux/plugins/tmux-sentinel/scripts/clear-pane-name.sh

# List all named panes
~/.tmux/plugins/tmux-sentinel/scripts/list-pane-names.sh
```

## Configuration

Add these to `~/.tmux.conf` before the plugin is loaded:

```tmux
# ─── Naming ───

# Ollama model for LLM naming (default: qwen2.5:0.5b)
set -g @sentinel-model "qwen2.5:0.5b"

# Key to trigger manual rename prompt (default: N)
set -g @sentinel-key "N"

# Label foreground color (default: #1a1b26)
set -g @sentinel-fg "#1a1b26"

# Label background color (default: #7aa2f7)
set -g @sentinel-bg "#7aa2f7"

# Border status position: top or bottom (default: bottom)
set -g @sentinel-border-status "bottom"

# ─── Input-waiting detection ───

# Enable/disable waiting detection (default: on)
set -g @sentinel-waiting "on"

# Check interval in seconds (default: 3)
set -g @sentinel-waiting-interval "3"

# Waiting indicator icon (default: ⏳)
set -g @sentinel-waiting-icon "⏳"

# Waiting label colors (default: Tokyo Night warning)
set -g @sentinel-waiting-fg "#1a1b26"
set -g @sentinel-waiting-bg "#e0af68"

# Bell notification on state transition (default: on, set "off" to disable)
set -g @sentinel-waiting-bell "on"
```

### Color presets

| Theme | fg | bg |
|---|---|---|
| Tokyo Night (default) | `#1a1b26` | `#7aa2f7` |
| Catppuccin Mocha | `#1e1e2e` | `#89b4fa` |
| Dracula | `#282a36` | `#bd93f9` |
| Nord | `#2e3440` | `#88c0d0` |
| Gruvbox | `#282828` | `#d79921` |
| Rose Pine | `#191724` | `#c4a7e7` |

## Input-waiting detection

The plugin monitors all panes and detects when a program is waiting for your input. This is especially useful when running multiple AI coding assistants (Claude Code, Aider) across tmux windows.

### How it works

A background daemon scans all panes every N seconds and checks for waiting indicators:

| Program | Detection method |
|---|---|
| Claude Code | `-- INSERT --` or `-- NORMAL --` mode visible (only shown at input prompt) |
| Aider | `aider> ` prompt at bottom of pane |
| Generic | `(y/n)`, `password:`, `Enter ...` prompts |

### Visual indicators

- **Window tab**: Prepends icon to window name in status bar (visible from any window)
- **Pane border**: Changes to warning color (yellow) with icon when waiting
- **Bell alert**: Rings tmux bell when a pane transitions to waiting (triggers `!` on window tab)

### Detected wait types

| Type | Meaning |
|---|---|
| `input` | Program is at its input prompt, waiting for a new message |
| `permission` | Program needs approval (e.g., Claude Code tool permission) |
| `confirm` | Yes/no confirmation prompt |
| `secret` | Password or token input |
| `prompt` | Generic interactive prompt |

### Programmatic usage

```bash
# Check a specific pane
~/.tmux/plugins/tmux-sentinel/scripts/check-waiting.sh %3

# Start the watching daemon manually (3s interval)
~/.tmux/plugins/tmux-sentinel/scripts/watch-waiting.sh 3 &

# Query pane waiting state
tmux display-message -p -t %3 '#{@pane_waiting}'

# Query window waiting state
tmux display-message -p -t :1 '#{@window_waiting}'
```

## How auto-naming works

### Pattern matching (default, zero dependencies)

Analyzes pane content using regex to detect:

| Category | Detected patterns |
|---|---|
| AI tools | Claude Code, Aider, Copilot, ChatGPT, Cursor, Gemini |
| Projects | Directory paths, git repo names |
| Git | Branch names (feat/, fix/, main, develop) |
| Activities | test, build, docker, k8s, git, db, logs, dev-server, ssh, edit |

Generates names like `claude:my-project`, `api-server:test`, `docker`.

### LLM mode (optional, requires ollama)

When ollama is running, the plugin sends the last 30 lines of pane content to a local model for more context-aware naming. Falls back to pattern matching if ollama is unavailable.

Recommended lightweight model:

```bash
ollama pull qwen2.5:0.5b  # 393MB, fast enough for naming
```

All processing happens locally. No data leaves your machine.

## License

MIT
