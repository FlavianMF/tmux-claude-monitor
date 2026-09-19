#!/usr/bin/env bash
# tmux-claude-monitor — TPM entrypoint.
# Adds a second status-line row with one indicator per live Claude Code pane:
# a pulsing red dot while it's working, a blinking yellow dot while it's
# waiting on you, a green dot when it just finished, a grey dot once you've
# looked at it. State comes entirely from Claude Code hooks (see hooks/) --
# this file only wires the rendering side.
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

tmux set -g status 2
tmux set -g status-format[1] "#[align=left]#(bash '$CURRENT_DIR/scripts/render.sh')"
tmux set -g status-interval 1

# done -> idle the moment you actually look at that pane. `-a` (append) is
# required: `-g` alone on set-hook would clobber any other global
# pane-focus-in hook instead of adding to it.
tmux set-hook -ga pane-focus-in "run-shell -b \"bash '$CURRENT_DIR/scripts/mark_seen.sh' '#{pane_id}'\""

# --- Mouse: click an indicator to jump to its pane -------------------------
# range=user|X only ever reports mouse_status_range == X on OUR ranges; the
# three built-in range types (session/window/pane, e.g. tmux's own window
# list) report the literal words "session"/"window"/"pane" instead (see
# tmux(1) FORMATS/range=). This branches back to the normal click-to-select
# behaviour for everything that isn't one of our indicators, so the rest of
# the status line keeps working exactly as before.
tmux bind-key -T root MouseDown1Status \
    if-shell -F "#{||:#{==:#{mouse_status_range},pane},#{||:#{==:#{mouse_status_range},window},#{==:#{mouse_status_range},session}}}" \
        "select-window -t =" \
        "run-shell -b \"tmux switch-client -t '#{mouse_status_range}' \; select-pane -t '#{mouse_status_range}'\""

# --- Keyboard fallback: <prefix> + m opens a picker -------------------------
# Mouse ranges on a custom status-format line are new-ish tmux territory; if
# the click ever doesn't land on a given terminal/tmux combination, this is
# the guaranteed way to reach the same result without touching a mouse.
tmux bind-key m run-shell -b "bash '$CURRENT_DIR/scripts/pane_picker.sh'"
