#!/usr/bin/env bash
# Shared helpers for tmux-claude-monitor.
# Sourced by render.sh, mark_seen.sh, pane_picker.sh and hooks/claude-state.sh.

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

# Every field a state file may carry. Kept as one space-separated list (not an
# associative array) so this stays portable to older bash (e.g. bash 3.2 on
# stock macOS) -- everything here only ever needs `printf -v` and word-split
# iteration, both available since bash 3.1.
cm_state_fields="state since pane pid session cwd name name_source daemon_state tempo"

# cm_load_state_file <file> <prefix>
# One key=value per line (NOT space-separated on one line -- values like a
# Claude-generated session name or a cwd with a space in it must survive
# intact). Splits only on the FIRST '=' per line. Populates ${prefix}<field>
# as plain variables for every field in cm_state_fields, resetting all of
# them to "" first so a loop that reuses the same prefix across many files
# never leaks a previous iteration's value into a field the current file
# doesn't have. Unknown lines (future fields, or a stray blank line) are
# silently ignored -- forward/backward compatible on purpose.
cm_load_state_file() {
    local file=$1 prefix=$2 fld line key val
    for fld in $cm_state_fields; do
        printf -v "${prefix}${fld}" '%s' ''
    done
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        key=${line%%=*}
        val=${line#*=}
        case " $cm_state_fields " in
            *" $key "*) printf -v "${prefix}${key}" '%s' "$val" ;;
        esac
    done <"$file"
}

# cm_json_field <json-text> <key>
# Pulls "<key>":"<value>" out of a JSON blob without a jq dependency -- same
# hand-rolled-text-parsing spirit as the /proc walk in claude-state.sh. Only
# handles string values and doesn't unescape backslashes/quotes inside them;
# good enough for session ids, transcript paths and short generated titles.
# If the key repeats, the FIRST match wins.
cm_json_field() {
    printf '%s' "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" |
        head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/'
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
