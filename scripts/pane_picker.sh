#!/usr/bin/env bash
# <prefix> + m: menu of every live Claude Code pane, pick one to jump to it.
# Guaranteed-to-work fallback for the mouse-click-on-indicator UX, for
# terminals/tmux builds where a click on a range=user status region doesn't
# land correctly.
set -u

script_dir=${BASH_SOURCE[0]%/*}
# shellcheck source=./helpers.sh
. "$script_dir/helpers.sh"

dir=$(cm_state_dir)
[ -d "$dir" ] || { tmux display-message "claude-monitor: no active Claude Code panes"; exit 0; }

live_panes=" $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr '\n' ' ') "
now=$(printf '%(%s)T' -1)

menu_args=(-T "#[align=centre]Claude Code panes")
found=0
shopt -s nullglob
for f in "$dir"/pane-*.state; do
    IFS= read -r line <"$f" 2>/dev/null || continue
    pane_num=$(cm_read_field "$line" pane) || continue
    pane="%${pane_num#%}"
    case $live_panes in
        *" $pane "*) : ;;
        *) continue ;;
    esac
    state=$(cm_read_field "$line" state) || state="?"
    since=$(cm_read_field "$line" since) || since=0
    session=$(cm_read_field "$line" session) || session="?"
    elapsed=$(cm_elapsed $((now - since)))
    found=1
    label="${session}:${pane}  [${state}, ${elapsed}]"
    # display-menu item: name, key, command. Empty key -> no shortcut char.
    menu_args+=("$label" "" "run-shell \"tmux switch-client -t '$pane' \; select-pane -t '$pane'\"")
done
shopt -u nullglob

if [ "$found" -eq 0 ]; then
    tmux display-message "claude-monitor: no active Claude Code panes"
    exit 0
fi

tmux display-menu "${menu_args[@]}"
