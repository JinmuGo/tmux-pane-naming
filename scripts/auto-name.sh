#!/usr/bin/env bash
# Auto-name a pane by analyzing its content
# Pattern matching first (instant), LLM upgrade async (if available)
# Usage: auto-name.sh [-t target] [-m model] [--no-llm]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
TARGET=""
MODEL=""
NO_LLM=false
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) TARGET="$2"; shift 2 ;;
        -m) MODEL="$2"; shift 2 ;;
        --no-llm|--pattern-only) NO_LLM=true; shift ;;
        *) shift ;;
    esac
done

# ─── Helpers ───

# Cross-platform md5 hash — detect once at startup
if command -v md5sum >/dev/null 2>&1; then
    _HASH_CMD="md5sum"
elif command -v md5 >/dev/null 2>&1; then
    _HASH_CMD="md5"
else
    _HASH_CMD="cksum"
fi

_hash() {
    case "$_HASH_CMD" in
        md5sum) md5sum | cut -d' ' -f1 ;;
        md5)    md5 -r | cut -d' ' -f1 ;;
        cksum)  cksum | cut -d' ' -f1 ;;
    esac
}

# Sanitize name: lowercase, allowed chars only, max 25 chars
_sanitize_name() {
    echo "$1" | \
        tr '[:upper:]' '[:lower:]' | \
        tr ' _' '-' | \
        sed 's/[^a-z0-9:-]//g; s/--*/-/g; s/^-//; s/-$//' | \
        cut -c1-25 | \
        sed 's/-$//'
}

# Build tmux target args
_tmux_target() {
    if [ -n "$TARGET" ]; then
        echo "-t" "$TARGET"
    fi
}

# Check if all LLM dependencies are available
_check_llm_available() {
    curl -s --max-time 2 "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    command -v python3 >/dev/null 2>&1 || return 1
    return 0
}

# ─── Content fingerprint ───

_get_fingerprint() {
    local content="$1"
    echo "$content" | grep -oE '[A-Za-z0-9._/-]{3,}' | sort -u | tr '\n' '|' | _hash
}

_fingerprint_changed() {
    local new_hash="$1"
    local old_hash
    if [ -n "$TARGET" ]; then
        old_hash=$(tmux display-message -p -t "$TARGET" '#{@pane_name_hash}' 2>/dev/null)
    else
        old_hash=$(tmux display-message -p '#{@pane_name_hash}' 2>/dev/null)
    fi
    [ "$new_hash" != "$old_hash" ]
}

_save_fingerprint() {
    local hash="$1"
    if [ -n "$TARGET" ]; then
        tmux set-option -p -t "$TARGET" @pane_name_hash "$hash"
    else
        tmux set-option -p @pane_name_hash "$hash"
    fi
}

# ─── Process-based naming (uses tmux built-in info) ───

# Map a running process name to an activity label
_process_to_activity() {
    local cmd="$1"
    case "$cmd" in
        # AI tools
        claude|claude-code)     echo "ai:claude" ;;
        aider)                  echo "ai:aider" ;;
        cursor)                 echo "ai:cursor" ;;
        copilot)                echo "ai:copilot" ;;
        # Editors
        vim|nvim|vi)            echo "vim" ;;
        nano|pico)              echo "nano" ;;
        emacs)                  echo "emacs" ;;
        code)                   echo "vscode" ;;
        # Shells — not useful as activity, return empty
        bash|zsh|sh|fish|dash)  echo "" ;;
        # Dev servers / runtimes
        node|deno|bun)          echo "node" ;;
        python|python3)         echo "python" ;;
        ruby|irb)               echo "ruby" ;;
        go)                     echo "go" ;;
        java|javac|gradle|mvn)  echo "java" ;;
        cargo)                  echo "rust" ;;
        # Infra / containers
        docker|podman)          echo "docker" ;;
        kubectl|k9s|helm)       echo "k8s" ;;
        terraform|pulumi)       echo "infra" ;;
        ansible|ansible-playbook) echo "ansible" ;;
        # DB clients
        psql)                   echo "pg" ;;
        mysql)                  echo "mysql" ;;
        sqlite3)                echo "sqlite" ;;
        mongosh|mongo)          echo "mongo" ;;
        redis-cli)              echo "redis" ;;
        # Remote
        ssh|mosh)               echo "remote" ;;
        scp|rsync)              echo "transfer" ;;
        # Git
        git|lazygit|tig)        echo "git" ;;
        gh)                     echo "github" ;;
        # Monitoring / logs
        htop|top|btop|glances)  echo "monitor" ;;
        tail|less|bat|cat)      echo "read" ;;
        journalctl)             echo "logs" ;;
        # Package managers
        npm|yarn|pnpm|npx)      echo "npm" ;;
        pip|pip3|pipx)          echo "pip" ;;
        brew)                   echo "brew" ;;
        # Build tools
        make|cmake|ninja)       echo "build" ;;
        webpack|vite|esbuild)   echo "build" ;;
        # Docs
        man|tldr)               echo "docs" ;;
        # Misc
        tmux|screen)            echo "mux" ;;
        *)                      echo "" ;;
    esac
}

# Get project name from pane's current working directory
_project_from_cwd() {
    local target="$1"
    local cwd
    if [ -n "$target" ]; then
        cwd=$(tmux display-message -p -t "$target" '#{pane_current_path}' 2>/dev/null)
    else
        cwd=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)
    fi
    [ -z "$cwd" ] && return

    # Use basename of CWD, skip if it's $HOME
    if [ "$cwd" = "$HOME" ] || [ "$cwd" = "/" ]; then
        return
    fi

    basename "$cwd"
}

# Get the foreground process name of a pane
_pane_process() {
    local target="$1"
    if [ -n "$target" ]; then
        tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null
    else
        tmux display-message -p '#{pane_current_command}' 2>/dev/null
    fi
}

# Detect name using process + CWD (fast, no content parsing needed)
detect_name_by_process() {
    local proc="$1"
    local project="$2"
    local activity

    activity=$(_process_to_activity "$proc")

    # If the process is a shell, no useful activity from process alone
    if [ -z "$activity" ]; then
        # Only return project if available
        if [ -n "$project" ]; then
            echo "$project"
        fi
        return
    fi

    # Build name: activity or project:activity
    if [ -n "$project" ]; then
        # For AI tools, use ai-tool:project format
        case "$activity" in
            ai:*) echo "${activity#ai:}:${project}" ;;
            *)    echo "${project}:${activity}" ;;
        esac
    else
        echo "$activity"
    fi
}

# ─── Pattern-based naming (content fallback) ───

detect_name_by_pattern() {
    local content="$1"
    local ai_tool="" project="" activity=""

    # 1. Detect AI tool from content (for cases where process is a shell
    #    but AI tool is running inside it, e.g. claude in interactive mode)
    if echo "$content" | grep -qiE "(claude-code|Claude Code|Model:.*claude)"; then
        ai_tool="claude"
    elif echo "$content" | grep -qiE "(aider>|Aider v|aider/)"; then
        ai_tool="aider"
    elif echo "$content" | grep -qiE "(copilot|github.copilot)"; then
        ai_tool="copilot"
    elif echo "$content" | grep -qiE "(chatgpt|openai)"; then
        ai_tool="chatgpt"
    elif echo "$content" | grep -qiE "(gemini|google.ai)"; then
        ai_tool="gemini"
    elif echo "$content" | grep -qiE "cursor"; then
        ai_tool="cursor"
    fi

    # 2. Extract project from content (fallback when CWD didn't work)
    project=$(echo "$content" | grep -oE '(Programming|projects|repos|src|code|workspace)/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+' | tail -1 | awk -F/ '{print $NF}')
    if [ -z "$project" ]; then
        project=$(echo "$content" | grep -oE 'cd [~./]*[A-Za-z0-9/_-]+' | tail -1 | awk -F/ '{print $NF}')
    fi
    if [ -z "$project" ]; then
        project=$(echo "$content" | grep -oE '\(?(main|master|develop|feat/[A-Za-z0-9_-]+|fix/[A-Za-z0-9_-]+|feature/[A-Za-z0-9_-]+)\)?' | tail -1 | tr -d '()')
    fi

    # 3. Detect activity from content
    local dev_match
    dev_match=$(echo "$content" | grep -oiE '(npm test|jest|pytest|cargo test|go test|rspec|vitest|npm run build|cargo build|go build|make |webpack|vite build|docker|docker-compose|podman|kubectl|k9s|helm|npm install|yarn add|pip install|cargo add|brew install|git push|git pull|git merge|git rebase|git diff|git log|git status|git stash|ssh |scp |rsync |tail -f|journalctl|logs|psql|mysql|sqlite|mongosh|redis-cli|vim |nvim |nano |emacs |node |python3? |ruby |go run|cargo run|java |deno |npm start|yarn start|npm run dev|yarn dev|pnpm dev)' | tail -1)

    if [ -n "$dev_match" ]; then
        case "$dev_match" in
            *test*|*jest*|*pytest*|*rspec*|*vitest*) activity="test" ;;
            *build*|*make*|*webpack*|*vite*) activity="build" ;;
            *docker*|*podman*) activity="docker" ;;
            *kubectl*|*k9s*|*helm*) activity="k8s" ;;
            *install*|*add*) activity="deps" ;;
            *"git push"*|*"git pull"*|*"git merge"*|*"git rebase"*) activity="git-sync" ;;
            *"git diff"*|*"git log"*|*"git status"*|*"git stash"*) activity="git" ;;
            *ssh*|*scp*|*rsync*) activity="remote" ;;
            *"tail -f"*|*journalctl*|*logs*) activity="logs" ;;
            *psql*|*mysql*|*sqlite*|*mongosh*|*redis*) activity="db" ;;
            *vim*|*nvim*|*nano*|*emacs*) activity="edit" ;;
            *start*|*dev*) activity="dev-server" ;;
            *node*|*python*|*ruby*|*"go run"*|*"cargo run"*|*java*|*deno*) activity="run" ;;
        esac
    fi

    # 4. Build the name
    local name=""
    if [ -n "$ai_tool" ] && [ -n "$project" ]; then
        name="${ai_tool}:${project}"
    elif [ -n "$ai_tool" ] && [ -n "$activity" ]; then
        name="${ai_tool}:${activity}"
    elif [ -n "$ai_tool" ]; then
        name="${ai_tool}"
    elif [ -n "$project" ] && [ -n "$activity" ]; then
        name="${project}:${activity}"
    elif [ -n "$project" ]; then
        name="${project}"
    elif [ -n "$activity" ]; then
        name="${activity}"
    fi

    echo "$name"
}

# ─── LLM-based naming (requires ollama) ───

detect_name_by_llm() {
    local content="$1"

    if [ -z "$MODEL" ]; then
        MODEL=$(tmux show-option -gqv "@pane-naming-model")
    fi
    if [ -z "$MODEL" ]; then
        MODEL="qwen2.5:0.5b"
    fi

    local trimmed
    trimmed=$(echo "$content" | tail -30 | head -c 2000)

    local prompt="Analyze this terminal session and generate a short descriptive name (2-4 words, lowercase, hyphens). Capture WHAT is being worked on. Examples: api-auth-fix, react-dashboard, docker-setup.

Terminal:
${trimmed}

Reply ONLY the name."

    local response_file
    response_file=$(mktemp)

    curl -s --max-time 15 "${OLLAMA_HOST}/api/chat" \
        -d "$(jq -n \
            --arg model "$MODEL" \
            --arg prompt "$prompt" \
            '{
                model: $model,
                messages: [{role: "user", content: $prompt}],
                stream: false,
                think: false,
                options: {temperature: 0.3, num_predict: 30}
            }')" \
        > "$response_file" 2>/dev/null

    if [ ! -s "$response_file" ]; then
        rm -f "$response_file"
        return 1
    fi

    # Pass file path as argument to python, not string interpolation
    local name
    name=$(python3 - "$response_file" <<'PYEOF'
import json, sys
fpath = sys.argv[1]
with open(fpath, 'r') as f:
    data = json.JSONDecoder(strict=False).decode(f.read())
content = data.get('message', {}).get('content', '')
content = content.strip().strip('"').strip("'").split('\n')[0].strip()
print(content[:25])
PYEOF
    )

    rm -f "$response_file"
    echo "$name"
}

# ─── Main ───

# Step 1: Process + CWD based naming (instant, no content capture needed)
proc=$(_pane_process "$TARGET")
project=$(_project_from_cwd "$TARGET")
name=$(detect_name_by_process "$proc" "$project")

# Sanitize early so all downstream comparisons use the final form
if [ -n "$name" ]; then
    name=$(_sanitize_name "$name")
fi

# Quick exit: if we already have a name and it matches current — skip entirely
if [ -n "$name" ]; then
    current_name=""
    if [ -n "$TARGET" ]; then
        current_name=$(tmux display-message -p -t "$TARGET" '#{@pane_name}' 2>/dev/null)
    else
        current_name=$(tmux display-message -p '#{@pane_name}' 2>/dev/null)
    fi
    if [ "$name" = "$current_name" ]; then
        exit 0
    fi
fi

# Sanitize project for consistent comparison
if [ -n "$project" ]; then
    project=$(_sanitize_name "$project")
fi

# Step 2: Content-based fallback if process detection wasn't enough
if [ -z "$name" ] || [ "$name" = "$project" ]; then
    # Build tmux capture command
    capture_args=(-p -J -S -50)
    if [ -n "$TARGET" ]; then
        capture_args+=(-t "$TARGET")
    fi

    # Capture pane content
    pane_content=$(tmux capture-pane "${capture_args[@]}" 2>/dev/null)

    if [ -n "$pane_content" ]; then
        # Check fingerprint — skip if content hasn't changed
        new_hash=$(_get_fingerprint "$pane_content")
        if _fingerprint_changed "$new_hash"; then
            _save_fingerprint "$new_hash"

            # Content pattern matching
            content_name=$(detect_name_by_pattern "$pane_content")
            if [ -n "$content_name" ]; then
                name="$content_name"
            fi

            # Step 3: LLM upgrade (async, non-blocking)
            # Apply the synchronous name first, then let LLM overwrite later
            if [ -n "$name" ]; then
                if [ -n "$TARGET" ]; then
                    tmux set-option -p -t "$TARGET" @pane_name "$name"
                else
                    tmux set-option -p @pane_name "$name"
                fi
            fi

            if [ "$NO_LLM" = false ] && _check_llm_available; then
                (
                    llm_name=$(detect_name_by_llm "$pane_content")
                    if [ -n "$llm_name" ]; then
                        llm_name=$(_sanitize_name "$llm_name")
                        # Only upgrade if the name would actually change
                        local cur
                        if [ -n "$TARGET" ]; then
                            cur=$(tmux display-message -p -t "$TARGET" '#{@pane_name}' 2>/dev/null)
                        else
                            cur=$(tmux display-message -p '#{@pane_name}' 2>/dev/null)
                        fi
                        if [ "$llm_name" != "$cur" ]; then
                            if [ -n "$TARGET" ]; then
                                tmux set-option -p -t "$TARGET" @pane_name "$llm_name"
                            else
                                tmux set-option -p @pane_name "$llm_name"
                            fi
                        fi
                    fi
                ) &
                # Name already applied above; clear to avoid double-write below
                name=""
            fi
        elif [ -z "$name" ]; then
            # Content unchanged and no process-based name — skip
            exit 0
        fi
    fi
fi

# Apply the name
if [ -n "$name" ]; then
    name=$(_sanitize_name "$name")
    if [ -n "$TARGET" ]; then
        tmux set-option -p -t "$TARGET" @pane_name "$name"
    else
        tmux set-option -p @pane_name "$name"
    fi
fi

# Show result only for manual triggers (not focus/interval)
if [ -z "$AUTO_TRIGGER" ] && [ -n "$name" ]; then
    tmux display-message "pane named: ${name}"
fi
