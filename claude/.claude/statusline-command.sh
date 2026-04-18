#!/bin/bash
# Bar style: "lines" | "blocks" | "smooth"
BAR_STYLE="blocks"

input=$(cat || echo '{}')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
context_total=$(echo "$input" | jq -r '((.context_window.context_window_size // 0) / 1000 | floor)')

# Use 2.0.70+ context_window.current_usage (most accurate)
current_usage=$(echo "$input" | jq -r '.context_window.current_usage // empty')
if [ -n "$current_usage" ] && [ "$current_usage" != "null" ]; then
    # Sum all token fields from current_usage
    context_tokens=$(echo "$input" | jq -r '
        .context_window.current_usage |
        ((.input_tokens // 0) + (.output_tokens // 0) +
         (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
    ')
    context_used=$((context_tokens / 1000))
    context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
    context_pct=$((100 * context_tokens / context_size))
else
    # Fallback: Get actual context from transcript's cache_read_input_tokens
    transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
        last_line=$(grep '"isSidechain":false' "$transcript_path" | grep '"usage"' | tail -1)
        if [ -n "$last_line" ]; then
            cache_read=$(echo "$last_line" | grep -oP '"cache_read_input_tokens":\K[0-9]+' | head -1 || echo "0")
            cache_create=$(echo "$last_line" | grep -oP '"cache_creation_input_tokens":\K[0-9]+' | head -1 || echo "0")
            input_tok=$(echo "$last_line" | grep -oP '"input_tokens":\K[0-9]+' | head -1 || echo "0")
            [ -z "$cache_read" ] && cache_read=0
            [ -z "$cache_create" ] && cache_create=0
            [ -z "$input_tok" ] && input_tok=0
            context_tokens=$((cache_read + cache_create + input_tok))
            context_used=$((context_tokens / 1000))
            context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
            context_pct=$((100 * context_tokens / context_size))
        else
            context_used=0
            context_pct=0
        fi
    else
        context_used=0
        context_pct=0
    fi
fi
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0 | . * 100 | floor | . / 100')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
[[ ! "$duration_ms" =~ ^[0-9]+$ ]] && duration_ms=0
duration_min=$((duration_ms / 60000))

git_info=""
if git -c core.useBuiltinFSMonitor=false rev-parse --git-dir > /dev/null 2>&1; then
    repo=$(basename "$(git -c core.useBuiltinFSMonitor=false rev-parse --show-toplevel 2>/dev/null)")
    branch=$(git -c core.useBuiltinFSMonitor=false symbolic-ref --short HEAD 2>/dev/null || git -c core.useBuiltinFSMonitor=false rev-parse --short HEAD 2>/dev/null)

    # Check for uncommitted changes
    if ! git -c core.useBuiltinFSMonitor=false diff --quiet 2>/dev/null || ! git -c core.useBuiltinFSMonitor=false diff --cached --quiet 2>/dev/null; then
        git_color="250;179;135"  # yellow/orange
    else
        git_color="166;227;161"  # green
    fi

    # Get line diff stats (added/removed)
    diff_stats=$(git -c core.useBuiltinFSMonitor=false diff --shortstat 2>/dev/null)
    added=$(echo "$diff_stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    removed=$(echo "$diff_stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")
    [ -z "$added" ] && added="0"
    [ -z "$removed" ] && removed="0"

    # Ahead/behind upstream
    upstream=$(git -c core.useBuiltinFSMonitor=false rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    ahead=$(echo "$upstream" | cut -f1)
    behind=$(echo "$upstream" | cut -f2)
    [ -z "$ahead" ] && ahead="0"
    [ -z "$behind" ] && behind="0"

    if [ ${#branch} -gt 25 ]; then
        branch="${branch:0:22}..."
    fi

    # Build git info string
    diff_info=""
    if [ "$added" != "0" ] || [ "$removed" != "0" ]; then
        diff_info=$(printf " \033[38;2;100;100;100m│\033[0m (\033[38;2;166;227;161m+%s\033[0m,\033[38;2;243;139;168m-%s\033[0m)" "$added" "$removed")
    fi

    upstream_info=""
    if [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then
        upstream_info=$(printf " \033[38;2;100;100;100m│\033[0m \033[38;2;137;180;250m↑%s\033[0m \033[38;2;250;179;135m↓%s\033[0m" "$ahead" "$behind")
    fi

    branch_icon=$'\ue0a0'
    git_info=$(printf " \033[38;2;100;100;100m│\033[0m \033[38;2;250;179;135m%s\033[0m \033[38;2;%sm%s\033[0m%b%b" "$branch_icon" "$git_color" "$branch" "$diff_info" "$upstream_info")
fi

sep="\033[38;2;100;100;100m │\033[0m"
# Line 1: Model, Context
printf "\033[38;2;136;192;208m%s\033[0m" "$model"

# Context bar
if [ "$context_pct" != "0" ] && [ "$context_pct" != "null" ]; then
    pct_int=${context_pct%.*}
    [[ ! "$pct_int" =~ ^[0-9]+$ ]] && pct_int=0
    if [ "$pct_int" -lt 50 ]; then
        bar_color="166;227;161"  # green
    elif [ "$pct_int" -lt 80 ]; then
        bar_color="250;179;135"  # yellow
    else
        bar_color="243;139;168"  # red
    fi

    bar_width=12
    filled=$((pct_int * bar_width / 100))
    empty=$((bar_width - filled))
    filled_bar=""
    empty_bar=""

    case "$BAR_STYLE" in
        lines)
            for ((i=0; i<filled; i++)); do filled_bar+="━"; done
            for ((i=0; i<empty; i++)); do empty_bar+="━"; done
            printf "$sep \033[38;2;140;140;140mctx:\033[0m \033[38;2;%sm%s\033[38;2;60;60;60m%s\033[0m \033[38;2;140;140;140m%s%%\033[0m \033[38;2;100;100;100m(\033[38;2;%sm%sk\033[0m\033[38;2;100;100;100m/\033[38;2;190;190;190m%sk\033[0m\033[38;2;100;100;100m)\033[0m" "$bar_color" "$filled_bar" "$empty_bar" "$pct_int" "$bar_color" "$context_used" "$context_total"
            ;;
        blocks)
            for ((i=0; i<filled; i++)); do filled_bar+="█"; done
            for ((i=0; i<empty; i++)); do empty_bar+="░"; done
            printf "$sep \033[38;2;140;140;140mctx:\033[0m \033[38;2;%sm%s\033[38;2;60;60;60m%s\033[0m \033[38;2;140;140;140m%s%%\033[0m \033[38;2;100;100;100m(\033[38;2;%sm%sk\033[0m\033[38;2;100;100;100m/\033[38;2;190;190;190m%sk\033[0m\033[38;2;100;100;100m)\033[0m" "$bar_color" "$filled_bar" "$empty_bar" "$pct_int" "$bar_color" "$context_used" "$context_total"
            ;;
        smooth)
            filled_bar=$(printf "%${filled}s")
            empty_bar=$(printf "%${empty}s")
            printf "$sep \033[38;2;140;140;140mctx:\033[0m \033[48;2;%sm%s\033[48;2;50;50;50m%s\033[0m \033[38;2;140;140;140m%s%%\033[0m \033[38;2;100;100;100m(\033[38;2;%sm%sk\033[0m\033[38;2;100;100;100m/\033[38;2;190;190;190m%sk\033[0m\033[38;2;100;100;100m)\033[0m" "$bar_color" "$filled_bar" "$empty_bar" "$pct_int" "$bar_color" "$context_used" "$context_total"
            ;;
    esac
fi

# Cost and duration
printf "$sep \033[38;2;140;140;140m$\033[38;2;166;227;161m%s\033[0m" "$cost"
printf "$sep \033[38;2;140;140;140m󰥔\033[0m \033[38;2;180;180;180m%sm\033[0m" "$duration_min"

# Line 2: Git, pwd
printf "\n"
printf "\033[38;2;140;140;140mcwd:\033[0m \033[38;2;203;166;247m%s\033[0m" "$cwd"
printf "%s" "$git_info"
