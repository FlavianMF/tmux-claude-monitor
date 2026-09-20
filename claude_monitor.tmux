#!/usr/bin/env bash
# tmux-claude-monitor — TPM entrypoint.
# Adds a second status-line row with one indicator per live Claude Code pane
# IN THE CURRENT TMUX SESSION: a pulsing red dot while it's working, a
# blinking yellow dot while it's waiting on you, a green dot when it just
# finished, a grey dot once you've looked at it, plus an orange/red overlay
# for the daemon's own blocked/failed states. Panes belonging to OTHER tmux
# sessions are folded into a "+N elsewhere" badge instead of shown inline --
# click it, or use <prefix>+m, to reach them. State comes entirely from
# Claude Code hooks (see hooks/) -- this file only wires the rendering side.
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

tmux set -g status 2
# '#{session_name}' is intentionally left unexpanded here -- tmux resolves it
# per attached client BEFORE running the job, so each tmux session ends up
# with a textually different #(...) command string. tmux's job cache is
# keyed by that exact string, so this is what makes the render naturally
# per-session: session A's status line runs (and caches) its own job,
# independently of session B's.
tmux set -g status-format[1] "#[align=left]#(bash '$CURRENT_DIR/scripts/render.sh' '#{session_name}')"
tmux set -g status-interval 1

# done -> idle the moment you actually look at that pane. `-a` (append) is
# required: `-g` alone on set-hook would clobber any other global
# pane-focus-in hook instead of adding to it.
tmux set-hook -ga pane-focus-in "run-shell -b \"bash '$CURRENT_DIR/scripts/mark_seen.sh' '#{pane_id}'\""

# --- Mouse: click an indicator to jump to its pane, or the "+N elsewhere" --
# --- badge to pick from every OTHER session's panes ------------------------
# range=user|X only ever reports mouse_status_range == X on OUR ranges; the
# three built-in range types (session/window/pane, e.g. tmux's own window
# list) report the literal words "session"/"window"/"pane" instead (see
# tmux(1) FORMATS/range=). The outermost check below catches our own
# "xsessions" badge range first (cheap literal compare, can't collide with a
# pane id -- those always start with "%" -- or with the three built-in
# words); everything else falls through to the existing pane-click-vs-native
# branch, completely unchanged.
tmux bind-key -T root MouseDown1Status \
    if-shell -F "#{==:#{mouse_status_range},xsessions}" \
        "run-shell -b \"bash '$CURRENT_DIR/scripts/pane_picker.sh' --exclude-session '#{session_name}'\"" \
        "if-shell -F \"#{||:#{==:#{mouse_status_range},pane},#{||:#{==:#{mouse_status_range},window},#{==:#{mouse_status_range},session}}}\" \
            \"select-window -t =\" \
            \"run-shell -b \\\"tmux switch-client -t '#{mouse_status_range}' \\\\; select-pane -t '#{mouse_status_range}'\\\"\""

# --- Keyboard fallback: <prefix> + m opens a picker of EVERY Claude pane ---
# --- server-wide (no session filter -- this is the "reach anywhere" path) --
# Mouse ranges on a custom status-format line are new-ish tmux territory; if
# the click ever doesn't land on a given terminal/tmux combination, this is
# the guaranteed way to reach the same result without touching a mouse. It's
# also, unfiltered, the keyboard equivalent of the "+N elsewhere" badge (just
# with your own session's panes included too) -- no separate keybinding was
# added for the filtered version, since this already gets you everywhere.
tmux bind-key m run-shell -b "bash '$CURRENT_DIR/scripts/pane_picker.sh'"
