#!/usr/bin/env bash
# <prefix> + m: menu of every live Claude Code pane, pick one to jump to it.
# Guaranteed-to-work fallback for the mouse-click-on-indicator UX, for
# terminals/tmux builds where a click on a range=user status region doesn't
# land correctly. Also what the "+N elsewhere" status-bar badge invokes
# (via --exclude-session) to jump to a pane outside the viewing session.
#
# Deliberately always sweeps every session server-wide (tmux list-panes -a)
# regardless of --exclude-session -- this script's whole purpose is
# cross-session reach, unlike render.sh's main row which is session-scoped.
# --exclude-session only affects which entries make it into the menu, not
# what's scanned/pruned.
set -u

script_dir=${BASH_SOURCE[0]%/*}
# shellcheck source=./helpers.sh
. "$script_dir/helpers.sh"

exclude_session=""
if [ "${1:-}" = "--exclude-session" ]; then
    exclude_session=${2:-}
fi

dir=$(cm_state_dir)
[ -d "$dir" ] || { tmux display-message "claude-monitor: no active Claude Code panes"; exit 0; }

live_panes=" $(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr '\n' ' ') "
now=$(printf '%(%s)T' -1)

menu_args=(-T "#[align=centre]Claude Code panes")
found=0
shopt -s nullglob
for f in "$dir"/pane-*.state; do
    cm_load_state_file "$f" cm_ || continue
    pane="%${cm_pane#%}"
    case $live_panes in
        *" $pane "*) : ;;
        *) continue ;;
    esac
    [ -n "$exclude_session" ] && [ "$cm_session" = "$exclude_session" ] && continue

    elapsed=$(cm_elapsed $((now - cm_since)))
    found=1
    if [ -n "$cm_name" ]; then
        label="${cm_session}:${pane} ${cm_name}  [${cm_state}, ${elapsed}]"
    else
        label="${cm_session}:${pane}  [${cm_state}, ${elapsed}]"
    fi
    # display-menu item: name, key, command. Empty key -> no shortcut char.
    menu_args+=("$label" "" "run-shell \"tmux switch-client -t '$pane' \; select-pane -t '$pane'\"")
done
shopt -u nullglob

if [ "$found" -eq 0 ]; then
    if [ -n "$exclude_session" ]; then
        tmux display-message "claude-monitor: no active Claude Code panes outside this session"
    else
        tmux display-message "claude-monitor: no active Claude Code panes"
    fi
    exit 0
fi

tmux display-menu "${menu_args[@]}"
