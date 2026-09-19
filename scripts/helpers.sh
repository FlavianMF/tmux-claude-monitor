#!/usr/bin/env bash
# Shared helpers for tmux-claude-monitor.
# Sourced by render.sh, mark_seen.sh and hooks/claude-state.sh.

cm_state_dir() {
    local dir
    dir=$(tmux show-option -gqv "@claude_monitor_state_dir" 2>/dev/null)
    if [ -z "$dir" ]; then
        dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-claude-monitor/panes"
    fi
    printf '%s' "$dir"
}

# State dir without asking tmux: used by the Claude Code hook, which must stay
# cheap (PreToolUse fires on every single tool call).
cm_state_dir_fast() {
    printf '%s' "${CLAUDE_MONITOR_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-claude-monitor/panes}"
}

# %6 -> pane-6.state  (a pane id is always %<digits>)
cm_state_file() {
    local dir=$1 pane=$2
    printf '%s/pane-%s.state' "$dir" "${pane#%}"
}

cm_read_field() {
    local line=$1 key=$2 kv
    for kv in $line; do
        case $kv in
            "$key"=*) printf '%s' "${kv#*=}"; return 0 ;;
        esac
    done
    return 1
}

# Human elapsed time, at most 6 chars: 42s / 2m14s / 3h07m
cm_elapsed() {
    local s=$1
    ((s < 0)) && s=0
    if ((s < 60)); then
        printf '%ds' "$s"
    elif ((s < 3600)); then
        printf '%dm%02ds' $((s / 60)) $((s % 60))
    else
        printf '%dh%02dm' $((s / 3600)) $(((s % 3600) / 60))
    fi
}
