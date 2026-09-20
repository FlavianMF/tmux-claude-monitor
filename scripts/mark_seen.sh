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
[ -f "$file" ] || exit 0

grep -qxF 'state=done' "$file" 2>/dev/null || exit 0

# One key=value per line now (not one line total) -- rewrite only the line
# that's exactly "state=done", leave every other line (name, cwd, since...)
# untouched. since is intentionally left alone: it still marks when Claude
# actually stopped, not when the pane happened to regain focus.
tmp="$file.$$"
while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "state=done" ] && line="state=idle"
    printf '%s\n' "$line"
done <"$file" >"$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null

exit 0
