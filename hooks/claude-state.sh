#!/usr/bin/env bash
# Claude Code hook -> per-pane state file consumed by the tmux status line.
#
# Wired from ~/.claude/settings.json as:
#   bash "$HOME/.tmux/plugins/tmux-claude-monitor/hooks/claude-state.sh" <EventName>
#
# Design constraints:
#   - stdin is only ever parsed on SessionStart/UserPromptSubmit (the only
#     events where the Claude-side session name can change); every other
#     event -- including PreToolUse, which fires on every single tool call --
#     drains it unread, exactly like before
#   - PreToolUse fires on every tool call, so the no-op path must not touch disk
#   - always exits 0: a monitor must never be able to break the session
set -u

event=${1:-}

# Only capture stdin on the two events that actually need it (Claude's own
# session name/title can change turn-to-turn; it doesn't change mid-turn, so
# there's no reason to pay JSON-scraping cost on PreToolUse/PostToolUse).
# Every other event keeps draining unread, unchanged from before.
case $event in
    SessionStart | UserPromptSubmit) payload=$(cat 2>/dev/null) ;;
    *)
        [ -t 0 ] || cat >/dev/null 2>&1
        payload=""
        ;;
esac

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

# Also doubles as the source for "carry the Claude-side fields forward" below
# on events that don't recompute them.
cm_load_state_file "$file" old_

# Same state as before: nothing to redraw, nothing to write. This is the hot
# path (PreToolUse during a long turn) and it must stay free.
[ "$old_state" = "$state" ] && exit 0

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

# Claude's own session name/state, from the daemon's per-job file, with a
# transcript-tail fallback. Only recomputed on SessionStart/UserPromptSubmit
# (payload is non-empty exactly then); every other real transition carries
# forward whatever was already on disk, so a Stop/Notification never blanks
# a name that was already resolved.
claude_name="$old_name"
claude_name_source="$old_name_source"
daemon_state="$old_daemon_state"
tempo="$old_tempo"

if [ -n "$payload" ]; then
    claude_name="" claude_name_source="" daemon_state="" tempo=""
    session_id=$(cm_json_field "$payload" session_id)
    id8=${session_id:0:8}
    if [ -n "$id8" ]; then
        job_file="$HOME/.claude/jobs/$id8/state.json"
        if [ -r "$job_file" ]; then
            job_json=$(cat "$job_file" 2>/dev/null)
            claude_name=$(cm_json_field "$job_json" name)
            claude_name_source=$(cm_json_field "$job_json" nameSource)
            daemon_state=$(cm_json_field "$job_json" state)
            tempo=$(cm_json_field "$job_json" tempo)
        fi
    fi
    if [ -z "$claude_name" ]; then
        transcript_path=$(cm_json_field "$payload" transcript_path)
        if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
            # Bound the read: this is already the rare/fallback path (the
            # jobs/state.json lookup above covers the common case), but a
            # transcript can grow large over a long session.
            last_title_line=$(tail -c 200000 "$transcript_path" 2>/dev/null |
                grep -o '{"type":"ai-title"[^}]*}' | tail -n1)
            [ -n "$last_title_line" ] && claude_name=$(cm_json_field "$last_title_line" aiTitle)
        fi
    fi
fi

mkdir -p "$dir" 2>/dev/null
tmp="$file.$$"
{
    printf 'state=%s\n' "$state"
    printf 'since=%s\n' "$since"
    printf 'pane=%s\n' "$pane"
    printf 'pid=%s\n' "$claude_pid"
    printf 'session=%s\n' "$session"
    printf 'cwd=%s\n' "$PWD"
    printf 'name=%s\n' "$claude_name"
    printf 'name_source=%s\n' "$claude_name_source"
    printf 'daemon_state=%s\n' "$daemon_state"
    printf 'tempo=%s\n' "$tempo"
} >"$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null

# Make the transition visible immediately instead of waiting up to a full
# status-interval
[ -n "${TMUX:-}" ] && tmux refresh-client -S 2>/dev/null

exit 0
