#!/usr/bin/env bash
# pane-focus-in hook: looking at a pane clears its "done" (green) state to
# "idle" (grey). "Finished and you saw it" is different from "finished and
# you haven't looked yet" -- this is what tells them apart.
set -u

script_dir=${BASH_SOURCE[0]%/*}
# shellcheck source=./helpers.sh
. "$script_dir/helpers.sh"

pane=${1:-${TMUX_PANE:-}}
[ -n "$pane" ] || exit 0

dir=$(cm_state_dir)
file=$(cm_state_file "$dir" "$pane")
[ -r "$file" ] || exit 0

IFS= read -r line <"$file" || exit 0
state=$(cm_read_field "$line" state) || exit 0
[ "$state" = "done" ] || exit 0

new_line=${line/state=done/state=idle}
# since is intentionally left untouched: it still marks when Claude actually
# stopped, not when the pane happened to regain focus.
tmp="$file.$$"
printf '%s\n' "$new_line" >"$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null

exit 0
