#!/usr/bin/env bash
# Renders status-format[1]: one indicator per live Claude Code pane IN THE
# VIEWING TMUX SESSION, plus a "+N elsewhere" badge for every other session's
# panes. Invoked once per second via #(...) from claude_monitor.tmux, with
# the viewing session's name as $1 (see claude_monitor.tmux for why that
# argument is what makes this naturally per-session).
set -u

script_dir=${BASH_SOURCE[0]%/*}
# shellcheck source=./helpers.sh
. "$script_dir/helpers.sh"

opt() { tmux show-option -gqv "$1" 2>/dev/null; }

# Falls back to asking tmux directly so this stays runnable by hand
# (`bash render.sh`, no argument) from inside a real tmux session.
viewing_session=${1:-$(tmux display-message -p '#{session_name}' 2>/dev/null)}

dir=$(cm_state_dir)
[ -d "$dir" ] || exit 0

max_items=$(opt "@claude_monitor_max_items"); max_items=${max_items:-6}
name_width=$(opt "@claude_monitor_name_width"); name_width=${name_width:-8}
claude_name_width=$(opt "@claude_monitor_claude_name_width"); claude_name_width=${claude_name_width:-18}
show_elapsed=$(opt "@claude_monitor_show_elapsed"); show_elapsed=${show_elapsed:-yes}

color_working1=$(opt "@claude_monitor_color_working")
[ -n "$color_working1" ] || color_working1=$(opt "@thm_red")
[ -n "$color_working1" ] || color_working1="colour1"
color_working2=$(opt "@thm_maroon"); [ -n "$color_working2" ] || color_working2="colour9"
color_working3=$(opt "@thm_peach"); [ -n "$color_working3" ] || color_working3="colour3"
color_waiting=$(opt "@claude_monitor_color_waiting"); [ -n "$color_waiting" ] || color_waiting=$(opt "@thm_yellow"); [ -n "$color_waiting" ] || color_waiting="colour3"
color_waiting_dim=$(opt "@thm_surface_2"); [ -n "$color_waiting_dim" ] || color_waiting_dim="colour8"
color_done=$(opt "@claude_monitor_color_done"); [ -n "$color_done" ] || color_done=$(opt "@thm_green"); [ -n "$color_done" ] || color_done="colour2"
color_idle=$(opt "@claude_monitor_color_idle"); [ -n "$color_idle" ] || color_idle=$(opt "@thm_overlay_0"); [ -n "$color_idle" ] || color_idle="colour8"
# blocked/failed: overlay colors for the daemon's own richer state
# (~/.claude/jobs/<id>/state.json), layered on top of the 4 states above --
# see hooks/claude-state.sh. Fixed/static (no animation), so they read as
# categorically different from the pulsing "working" red on sight alone.
color_blocked=$(opt "@claude_monitor_color_blocked"); [ -n "$color_blocked" ] || color_blocked=$(opt "@thm_peach"); [ -n "$color_blocked" ] || color_blocked="colour208"
color_failed=$(opt "@claude_monitor_color_failed"); [ -n "$color_failed" ] || color_failed=$(opt "@thm_red"); [ -n "$color_failed" ] || color_failed="colour1"
bg=$(opt "@thm_bg"); [ -n "$bg" ] || bg="default"
fg_label=$(opt "@thm_fg"); [ -n "$fg_label" ] || fg_label="default"

now=$(printf '%(%s)T' -1)
frame=$(( now % 4 ))
blink=$(( now % 2 ))

# One tmux round-trip to know which panes are actually still alive, server
# wide. This stays UNSCOPED on purpose, independent of $viewing_session: it
# drives which state FILES get pruned from disk, not what gets displayed. If
# this were scoped to the viewing session, a pane whose owning tmux session
# has since closed would never be "owned" by anyone's render.sh call again --
# nothing would ever reap it. Every session's render.sh sweeps the whole
# directory every second; only the display step below is session-scoped.
live_panes=" $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr '\n' ' ') "

# cm_truncate <text> <max-chars>
cm_truncate() {
    local text=$1 max=$2
    if [ "${#text}" -gt "$max" ]; then
        printf '%s' "${text:0:$((max - 1))}…"
    else
        printf '%s' "$text"
    fi
}

out=""
count=0
overflow_done=0
other_count=0
other_has_waiting=0
shopt -s nullglob
for f in "$dir"/pane-*.state; do
    cm_load_state_file "$f" cm_ || continue
    pane="%${cm_pane#%}"

    # Prune: pane gone from tmux, or the claude process behind it is dead.
    # This is what makes a `kill -9` on claude disappear from the bar without
    # ever relying on SessionEnd having fired. Unscoped -- see note above.
    case $live_panes in
        *" $pane "*) : ;;
        *)
            rm -f "$f"
            continue
            ;;
    esac
    if [ -n "$cm_pid" ] && [ ! -d "/proc/$cm_pid" ]; then
        rm -f "$f"
        continue
    fi

    case $cm_state in
        working | waiting | done | idle) : ;;
        *) continue ;;
    esac

    # Display-only filter: everything above this point still ran for every
    # live pane server-wide (pruning must). Only from here on do we care
    # whether this pane belongs to the session that's actually looking.
    if [ "$cm_session" != "$viewing_session" ]; then
        other_count=$((other_count + 1))
        [ "$cm_state" = waiting ] && other_has_waiting=1
        continue
    fi

    count=$((count + 1))
    if [ "$count" -gt "$max_items" ]; then
        # Overflow: fold the rest into a plain counter instead of truncating
        # mid-list, so what's shown stays fully readable. `continue` rather
        # than `break` -- files for OTHER sessions can still appear later in
        # glob order, and other_count/other_has_waiting above must keep
        # accumulating across the whole directory regardless of where this
        # session's own overflow point falls. The recount itself only runs
        # once (guarded by overflow_done), not on every remaining iteration.
        if [ "$overflow_done" -eq 0 ]; then
            overflow_done=1
            # Recount filtered to THIS session only (other-session panes are
            # handled separately via the "+N elsewhere" badge below, so they
            # must not be subtracted here too) -- unlike v1, this number is
            # actually actionable from where you're looking.
            rest=0
            for g in "$dir"/pane-*.state; do
                grep -qxF "session=$viewing_session" "$g" 2>/dev/null && rest=$((rest + 1))
            done
            remaining=$((rest - max_items))
            if [ "$remaining" -gt 0 ]; then
                overflow="#[fg=${fg_label},bg=${bg}] +${remaining} "
                out="${out}${overflow//%/%%}"
            fi
        fi
        continue
    fi

    case $cm_state in
        working)
            case $frame in
                0) glyph="●"; color=$color_working1 ;;
                1) glyph="●"; color=$color_working2 ;;
                2) glyph="●"; color=$color_working3 ;;
                *) glyph="●"; color=$color_working2 ;;
            esac
            ;;
        waiting)
            if [ "$blink" -eq 0 ]; then glyph="◍"; color=$color_waiting; else glyph="◍"; color=$color_waiting_dim; fi
            ;;
        done) glyph="●"; color=$color_done ;;
        idle) glyph="○"; color=$color_idle ;;
    esac

    # Daemon overlay: only overrides when the daemon explicitly reports one
    # of its two richer states. "failed" in particular is the one thing this
    # monitor couldn't show at all before -- the hook's own 4-state model has
    # no way to produce it on its own.
    case $cm_daemon_state in
        failed) glyph="✕"; color=$color_failed ;;
        blocked) glyph="◐"; color=$color_blocked ;;
    esac

    tmux_label=$(cm_truncate "$cm_session" "$name_width")
    if [ -n "$cm_name" ]; then
        claude_label=$(cm_truncate "$cm_name" "$claude_name_width")
        label="${tmux_label} · ${claude_label}"
    else
        label=$tmux_label
    fi

    elapsed_str=""
    if [ "$show_elapsed" = "yes" ]; then
        delta=$((now - cm_since))
        elapsed_str=" $(cm_elapsed "$delta")"
    fi

    item="#[range=user|${pane}]#[fg=${fg_label},bg=${bg}]${label}:${pane} #[fg=${color},bg=${bg}]${glyph}#[fg=${fg_label},bg=${bg}]${elapsed_str}#[norange] "
    # The whole item is about to be re-parsed by tmux as a format string (it
    # runs the final status-format through strftime, same mechanism that
    # makes %H:%M work in status-right). Pane ids are literally "%<digits>",
    # so an unescaped one gets mangled into strftime width-padding garbage.
    # Escaping every literal % as %% here is what makes it survive intact.
    item=${item//%/%%}
    out="${out}${item}"
done
shopt -u nullglob

# "+N elsewhere": a single clickable/keyboard-reachable summary for every
# OTHER session's Claude panes, instead of showing them inline. Escalates to
# the same color as "waiting" when something over there actually needs you --
# that's the same urgency class as a waiting pane in this session, not a new
# color semantic. Otherwise uses the muted done/idle color. Hidden entirely
# when there's nothing to fold.
if [ "$other_count" -gt 0 ]; then
    if [ "$other_has_waiting" -eq 1 ]; then
        badge_color=$color_waiting
    else
        badge_color=$color_done
    fi
    badge="#[range=user|xsessions]#[fg=${badge_color},bg=${bg}]+${other_count} elsewhere#[norange] "
    out="${out}${badge//%/%%}"
fi

printf '%s' "$out"
