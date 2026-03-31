#!/usr/bin/env bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# -- Bells-and-whistles mute indicator ----------------------------------------
# Find the plugin install path by parsing installed_plugins.json with python3.
# The mute marker files live one level above the versioned install dir (i.e.
# in the directory that contains all version subdirectories), so they survive
# upgrades.  Files: .mute_all (global) and .mute_tty_<TTY_ID> (per TTY/tab).
speaker_symbol=""
BNW_INSTALL_PATH=$(python3 - <<'PYEOF' 2>/dev/null
import json, sys, os
try:
    data = json.load(open(os.path.join(os.environ['HOME'], '.claude/plugins/installed_plugins.json')))
    plugins = data.get('plugins', {})
    for key, entries in plugins.items():
        if 'bells-and-whistles' in key:
            if entries and isinstance(entries, list):
                print(entries[0].get('installPath', ''))
            sys.exit(0)
except Exception:
    pass
PYEOF
)

if [ -n "$BNW_INSTALL_PATH" ]; then
    # Mute files live one level above the versioned install dir
    MUTE_DIR=$(dirname "$BNW_INSTALL_PATH")

    # Determine current TTY ID (used for per-tab mute files)
    MY_TTY=""
    if [ -n "$TMUX_PANE" ]; then
        MY_TTY=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null)
    else
        _raw=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
        [ -n "$_raw" ] && [ "$_raw" != "?" ] && MY_TTY="/dev/$_raw"
    fi
    TTY_ID=""
    [ -n "$MY_TTY" ] && TTY_ID=$(echo "$MY_TTY" | sed 's|^/dev/||; s|/|_|g')

    # Check mute state: per-TTY takes priority, then global, then unmuted
    is_muted=0
    if [ -n "$TTY_ID" ] && [ -f "${MUTE_DIR}/.mute_tty_${TTY_ID}" ]; then
        is_muted=1
    elif [ -f "${MUTE_DIR}/.mute_all" ]; then
        is_muted=1
    fi

    if [ "$is_muted" -eq 1 ]; then
        speaker_symbol=$'\xf0\x9f\x94\x87'   # UTF-8: muted speaker
    else
        speaker_symbol=$'\xf0\x9f\x94\x8a'   # UTF-8: speaker with sound
    fi
fi
# ------------------------------------------------------------------------------

# Model display name and effort level
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
effort=$(jq -r '.effortLevel // "default"' ~/.claude/settings.json 2>/dev/null)

# Git info (repo name, branch, PR number if on GitHub)
git_info=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    git_repo=$(basename "$git_root")
    git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

    # Look up PR for current branch via gh CLI (skip locks, silent on error)
    git_pr=""
    if command -v gh > /dev/null 2>&1; then
        pr_num=$(GIT_OPTIONAL_LOCKS=0 gh pr view --json number --jq '.number' 2>/dev/null)
        [ -n "$pr_num" ] && git_pr="#${pr_num}"
    fi

    # Build colored git segment
    if [ -n "$git_pr" ]; then
        git_info=" \033[2m(\033[0m\033[33m${git_repo}\033[0m\033[2m:\033[0m\033[96m${git_branch}\033[0m \033[35m${git_pr}\033[0m\033[2m)\033[0m"
    else
        git_info=" \033[2m(\033[0m\033[33m${git_repo}\033[0m\033[2m:\033[0m\033[96m${git_branch}\033[0m\033[2m)\033[0m"
    fi
fi

# Groundwork project indicator (works with or without git)
gw_segment=""
gw_root="${git_root:-$cwd}"
if [ -d "$HOME/.claude/plugins/cache/groundwork-marketplace" ]; then
    if [ -f "${gw_root}/.groundwork.yml" ]; then
        gw_project=""
        # Read from home-dir session file
        gw_session_id=$(cat "$HOME/.claude/groundwork-state/current-session-id" 2>/dev/null)
        if [ -n "$gw_session_id" ]; then
            gw_session_file="$HOME/.claude/groundwork-state/session/${gw_session_id}.json"
            if [ -f "$gw_session_file" ]; then
                gw_project=$(jq -r '.project // empty' "$gw_session_file" 2>/dev/null)
            fi
        fi
        # Fallback: find most recent session file for this repo
        if [ -z "$gw_project" ]; then
            gw_sessions_dir="$HOME/.claude/groundwork-state/session"
            if [ -d "$gw_sessions_dir" ]; then
                gw_latest=$(ls -t "$gw_sessions_dir"/*.json 2>/dev/null | head -1)
                if [ -n "$gw_latest" ]; then
                    gw_project=$(jq -r '.project // empty' "$gw_latest" 2>/dev/null)
                fi
            fi
        fi
        if [ -n "$gw_project" ]; then
            gw_segment=" \033[2m|\033[0m \033[32mProject: ${gw_project}\033[0m"
        else
            gw_segment=" \033[2m|\033[0m \033[2mNo Project Selected\033[0m"
        fi
    fi
fi

# Context usage percentage (report used, not remaining)
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Context window size for absolute token display
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')

# Format context window size (e.g. 200000 -> "200k", 1000000 -> "1M")
format_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        awk "BEGIN { printf \"%.0fM\", $n/1000000 }"
    elif [ "$n" -ge 1000 ]; then
        awk "BEGIN { printf \"%.0fk\", $n/1000 }"
    else
        echo "$n"
    fi
}
ctx_size_fmt=$(format_tokens "$ctx_size")

# Current context tokens used (from current_usage.input_tokens, what used_percentage is based on)
ctx_used_abs=$(echo "$input" | jq -r '
    if .context_window.current_usage != null then
        (.context_window.current_usage.input_tokens
         + .context_window.current_usage.cache_creation_input_tokens
         + .context_window.current_usage.cache_read_input_tokens)
    else 0 end')
ctx_used_fmt=$(format_tokens "$ctx_used_abs")

# Progress bar: 10 chars wide, filled = used portion
BAR_WIDTH=10
FILLED_CHAR=$'\xe2\x96\x88'   # UTF-8 for filled block
EMPTY_CHAR=$'\xe2\x96\x91'    # UTF-8 for light shade
if [ -n "$used" ]; then
    used_int=$(printf "%.0f" "$used")
    filled=$(( used_int * BAR_WIDTH / 100 ))
    [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
    empty=$(( BAR_WIDTH - filled ))
    pct_str="${ctx_used_fmt}/${ctx_size_fmt} (${used_int}%)"
else
    filled=0
    empty=$BAR_WIDTH
    pct_str="--"
fi

bar_filled_part=""
bar_empty_part=""
for i in $(seq 1 "$filled"); do bar_filled_part="${bar_filled_part}${FILLED_CHAR}"; done
for i in $(seq 1 "$empty");  do bar_empty_part="${bar_empty_part}${EMPTY_CHAR}";   done

# Shorten home directory prefix to ~
case "$cwd" in
    "$HOME"/*) cwd="~${cwd#"$HOME"}" ;;
    "$HOME")   cwd="~" ;;
esac

# Pick bar color based on used percentage (high = bad)
if [ -n "$used" ] && [ "$(printf "%.0f" "$used")" -ge 80 ]; then
    bar_color="\033[31m"   # red when high usage
elif [ -n "$used" ] && [ "$(printf "%.0f" "$used")" -ge 50 ]; then
    bar_color="\033[33m"   # yellow when medium
else
    bar_color="\033[32m"   # green when low
fi

# Anthropic usage API: session (five_hour) and weekly (seven_day) utilization
USAGE_CACHE="$HOME/.claude/statusline-usage-cache.json"
session_util=""
weekly_util=""
{
    # Check cache age (TTL = 300 seconds)
    use_cache=0
    if [ -f "$USAGE_CACHE" ]; then
        cache_age=$(( $(date +%s) - $(date -r "$USAGE_CACHE" +%s 2>/dev/null || echo 0) ))
        [ "$cache_age" -lt 300 ] && use_cache=1
    fi

    if [ "$use_cache" -eq 1 ]; then
        usage_json=$(cat "$USAGE_CACHE")
    else
        TOKEN=$(python3 -c "
import json, sys, subprocess, os
creds_json = None
# Try credentials file first (Linux)
creds_file = os.path.join(os.environ['HOME'], '.claude', '.credentials.json')
try:
    with open(creds_file) as f:
        creds_json = json.load(f)
except Exception:
    pass
# Fall back to macOS Keychain
if creds_json is None:
    try:
        raw = subprocess.check_output(
            ['security', 'find-generic-password', '-s', 'Claude Code-credentials', '-w'],
            stderr=subprocess.DEVNULL, text=True).strip()
        creds_json = json.loads(raw)
    except Exception:
        pass
if creds_json:
    print(creds_json['claudeAiOauth']['accessToken'])
else:
    sys.exit(1)
" 2>/dev/null)
        if [ -n "$TOKEN" ]; then
            usage_json=$(curl -s --max-time 5 \
                "https://api.anthropic.com/api/oauth/usage" \
                -H "Authorization: Bearer $TOKEN" \
                -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)
            # Only cache if response looks valid
            if echo "$usage_json" | jq -e '.five_hour' > /dev/null 2>&1; then
                echo "$usage_json" > "$USAGE_CACHE" 2>/dev/null
            else
                usage_json=""
            fi
        fi
    fi

    if [ -n "$usage_json" ]; then
        session_util=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
        weekly_util=$(echo  "$usage_json" | jq -r '.seven_day.utilization  // empty' 2>/dev/null)
        session_resets_at=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
        weekly_resets_at=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
        # Round to integers
        [ -n "$session_util" ] && session_util=$(printf "%.0f" "$session_util")
        [ -n "$weekly_util"  ] && weekly_util=$(printf  "%.0f" "$weekly_util")
    fi
} 2>/dev/null

format_reset_time() {
    local resets_at="$1" mode="$2"
    python3 -c "
import sys
from datetime import datetime, timezone, timedelta

resets_at = '$resets_at'
mode = '$mode'

try:
    # Parse ISO 8601 timestamp
    ra = resets_at.replace('Z', '+00:00')
    reset_dt = datetime.fromisoformat(ra)
    now_dt = datetime.now(timezone.utc)
    diff = int((reset_dt - now_dt).total_seconds())
    if diff < 0:
        diff = 0

    if diff < 3600:
        mins = (diff + 59) // 60
        print(f' ({mins}m)')
    elif mode == 'session' or diff < 86400:
        hrs = diff // 3600
        mins = (diff % 3600 + 59) // 60
        if mins == 60:
            mins = 0
            hrs += 1
        if mins > 0:
            print(f' ({hrs}h {mins}m)')
        else:
            print(f' ({hrs}h)')
    else:
        reset_local = reset_dt.astimezone()
        now_local = now_dt.astimezone()
        tomorrow = (now_local + timedelta(days=1)).date()
        reset_date = reset_local.date()
        hr = reset_local.strftime('%I').lstrip('0') + reset_local.strftime('%p')
        if reset_date == tomorrow:
            print(f' (Tomorrow {hr})')
        else:
            day_name = reset_local.strftime('%A')
            day_num = reset_local.day
            month_name = reset_local.strftime('%B')
            print(f' ({day_name} {day_num} {month_name} {hr})')
except Exception:
    pass
" 2>/dev/null
}

session_reset_str=""
weekly_reset_str=""
[ -n "$session_resets_at" ] && session_reset_str=$(format_reset_time "$session_resets_at" "session")
[ -n "$weekly_resets_at" ]  && weekly_reset_str=$(format_reset_time "$weekly_resets_at" "weekly")

# LINE 1: model (effort)    speaker icon
printf "\033[35m%s\033[0m \033[2m(%s)\033[0m" \
    "${model}" "${effort}"
if [ -n "$speaker_symbol" ]; then
    printf "  %s" "${speaker_symbol}"
fi

# LINE 2: [Context: filled empty used/total (pct%) | Session: X% | Weekly: X%]
printf "\n"
printf "${bar_color}Context: %s\033[0m\033[2m%s\033[0m ${bar_color}%s\033[0m" \
    "${bar_filled_part}" "${bar_empty_part}" "${pct_str}"
if [ -n "$session_util" ]; then
    printf "\033[2m |\033[0m \033[36mSession: %s%%\033[2m%s\033[0m" "${session_util}" "${session_reset_str}"
fi
if [ -n "$weekly_util" ]; then
    printf "\033[2m |\033[0m \033[35mWeekly: %s%%\033[2m%s\033[0m" "${weekly_util}" "${weekly_reset_str}"
fi

# LINE 3: cwd (repo:branch | project)
printf "\n"
printf "\033[01;34m%s\033[00m" "${cwd}"
printf "%b" "${git_info}"
printf "%b" "${gw_segment}"
