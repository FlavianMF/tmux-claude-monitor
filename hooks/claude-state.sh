#!/usr/bin/env bash
# Claude Code hook -> per-pane state file consumed by the tmux status line.
#
# Wired from ~/.claude/settings.json as:
#   bash "$HOME/.tmux/plugins/tmux-claude-monitor/hooks/claude-state.sh" <EventName>
#
# Design constraints:
#   - never reads the stdin JSON (everything needed is in the environment), but
#     must drain it so Claude Code never gets SIGPIPE on the write side
#   - PreToolUse fires on every tool call, so the no-op path must not touch disk
#   - always exits 0: a monitor must never be able to break the session
set -u

event=${1:-}

# Drain stdin without parsing it.
[ -t 0 ] || cat >/dev/null 2>&1

pane=${TMUX_PANE:-}
[ -n "$pane" ] || exit 0

case $event in
    SessionStart)     state=idle ;;
    UserPromptSubmit) state=working ;;
    PreToolUse | PostToolUse) state=working ;;
    Notification)     state=waiting ;;
    Stop)             state=done ;;
    SessionEnd)       state=__remove__ ;;
    *)                exit 0 ;;
esac

script_dir=${BASH_SOURCE[0]%/*}
# shellcheck source=../scripts/helpers.sh
. "$script_dir/../scripts/helpers.sh"

dir=$(cm_state_dir_fast)
file=$(cm_state_file "$dir" "$pane")

if [ "$state" = "__remove__" ]; then
    rm -f "$file"
    [ -n "${TMUX:-}" ] && tmux refresh-client -S 2>/dev/null
    exit 0
fi

prev_state=""
if [ -r "$file" ]; then
    IFS= read -r prev_line <"$file" || prev_line=""
    prev_state=$(cm_read_field "$prev_line" state) || prev_state=""
fi

# Same state as before: nothing to redraw, nothing to write. This is the hot
# path (PreToolUse during a long turn) and it must stay free.
[ "$prev_state" = "$state" ] && exit 0

now=$(printf '%(%s)T' -1)
since=$now

# Walk up the process tree to the claude process itself. render.sh uses this pid
# to prune entries when claude dies without ever firing SessionEnd (kill -9).
claude_pid=""
probe=$PPID
for _ in 1 2 3 4 5; do
    [ -r "/proc/$probe/comm" ] || break
    IFS= read -r comm <"/proc/$probe/comm" || break
    case $comm in
        claude | node)
            claude_pid=$probe
            break
            ;;
    esac
    IFS= read -r stat_line <"/proc/$probe/stat" || break
    stat_line=${stat_line#*') '} # drop "<pid> (<comm>) ", comm may contain spaces
    probe=${stat_line#* }        # field after the state char is ppid
    probe=${probe%% *}
    case $probe in
        "" | 0 | 1) break ;;
    esac
done

session=""
[ -n "${TMUX:-}" ] && session=$(tmux display-message -p -t "$pane" '#{session_name}' 2>/dev/null)

mkdir -p "$dir" 2>/dev/null
tmp="$file.$$"
printf 'state=%s since=%s pane=%s pid=%s session=%s cwd=%s\n' \
    "$state" "$since" "$pane" "$claude_pid" "$session" "$PWD" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$file" 2>/dev/null

# Make the transition visible immediately instead of waiting up to a full
# status-interval
[ -n "${TMUX:-}" ] && tmux refresh-client -S 2>/dev/null

exit 0
