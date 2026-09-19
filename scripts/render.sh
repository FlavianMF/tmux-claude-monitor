#!/usr/bin/env bash
# Renders status-format[1]: one indicator per live Claude Code pane.
# Invoked once per second via #(...) from claude_monitor.tmux.
set -u

script_dir=${BASH_SOURCE[0]%/*}
# shellcheck source=./helpers.sh
. "$script_dir/helpers.sh"

opt() { tmux show-option -gqv "$1" 2>/dev/null; }

dir=$(cm_state_dir)
[ -d "$dir" ] || exit 0

max_items=$(opt "@claude_monitor_max_items"); max_items=${max_items:-6}
name_width=$(opt "@claude_monitor_name_width"); name_width=${name_width:-8}
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
bg=$(opt "@thm_bg"); [ -n "$bg" ] || bg="default"
fg_label=$(opt "@thm_fg"); [ -n "$fg_label" ] || fg_label="default"

now=$(printf '%(%s)T' -1)
frame=$(( now % 4 ))
blink=$(( now % 2 ))

# One tmux round-trip to know which panes are actually still alive.
live_panes=" $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr '\n' ' ') "

out=""
count=0
shopt -s nullglob
for f in "$dir"/pane-*.state; do
    IFS= read -r line <"$f" 2>/dev/null || continue

    pane_num=$(cm_read_field "$line" pane) || pane_num=""
    pane="%${pane_num#%}"
    state=$(cm_read_field "$line" state) || state=""
    since=$(cm_read_field "$line" since) || since=0
    session=$(cm_read_field "$line" session) || session=""
    pid=$(cm_read_field "$line" pid) || pid=""

    # Prune: pane gone from tmux, or the claude process behind it is dead.
    # This is what makes a `kill -9` on claude disappear from the bar without
    # ever relying on SessionEnd having fired.
    case $live_panes in
        *" $pane "*) : ;;
        *)
            rm -f "$f"
            continue
            ;;
    esac
    if [ -n "$pid" ] && [ ! -d "/proc/$pid" ]; then
        rm -f "$f"
        continue
    fi

    case $state in
        working | waiting | done | idle) : ;;
        *) continue ;;
    esac

    count=$((count + 1))
    if [ "$count" -gt "$max_items" ]; then
        # Overflow: fold the rest into a plain counter instead of truncating
        # mid-list, so what's shown stays fully readable.
        rest=0
        for g in "$dir"/pane-*.state; do rest=$((rest + 1)); done
        remaining=$((rest - max_items))
        if [ "$remaining" -gt 0 ]; then
            overflow="#[fg=${fg_label},bg=${bg}] +${remaining} "
            out="${out}${overflow//%/%%}"
        fi
        break
    fi

    case $state in
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

    label=$session
    if [ "${#label}" -gt "$name_width" ]; then
        label="${label:0:$((name_width - 1))}…"
    fi

    elapsed_str=""
    if [ "$show_elapsed" = "yes" ]; then
        delta=$((now - since))
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

printf '%s' "$out"
