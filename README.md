# tmux-claude-monitor

A second tmux status line that shows, at a glance, what every Claude Code
session in your **current tmux session** is doing right now:

- 🔴 pulsing red — Claude is working
- 🟡 blinking yellow — Claude is waiting on you (a permission prompt, a
  question)
- 🟢 green — Claude just finished
- ⚪ grey — idle, or finished and already seen
- 🟠 solid orange — the Claude Code daemon reports this session as `blocked`
- ✕ solid red — the daemon reports it `failed`

Each indicator shows `tmux-session-name · claude-session-name:%pane-id` (the
Claude-side name only when one's available) and how long it's been in that
state, and can be clicked (or picked from a menu) to jump straight to that
pane.

Panes belonging to **other** tmux sessions aren't shown inline — they're
folded into a `+N elsewhere` badge at the end of the line, so the bar stays
about what you're looking at. Click the badge, or `<prefix>+m`, to reach
them.

State comes entirely from Claude Code's own hooks and its daemon's per-job
state file — no polling, no transcript parsing, no scraping pane content.

## How it works

```
Claude Code hook  →  hooks/claude-state.sh  →  one state file per pane
                          ↑ also reads               ↓
                ~/.claude/jobs/<id>/state.json   tmux status-format[1]
                    (daemon: name, state)        ← scripts/render.sh  (1×/s)
```

- `hooks/claude-state.sh` is wired into Claude Code's `settings.json` under
  six events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `Notification`, `Stop`, `SessionEnd`). Each invocation writes (or removes)
  one small state file per tmux pane at
  `${XDG_STATE_HOME:-~/.local/state}/tmux-claude-monitor/panes/` — one
  `key=value` per line (not one line total, so a value can safely contain a
  space, e.g. a generated session name or a `cwd` with one in it).
  On `SessionStart`/`UserPromptSubmit` (the only events where it can
  meaningfully change) it also reads `~/.claude/jobs/<first-8-hex-of-
  session_id>/state.json` — the Claude Code daemon's own live state for that
  session — for a human-readable session name and the daemon's own
  `state`/`tempo`, falling back to the last `ai-title` entry in the
  session's transcript if that file isn't there. Every other event carries
  those fields forward unchanged instead of re-deriving them, so a `Stop` or
  `Notification` never blanks out an already-resolved name.
- `scripts/render.sh` runs once a second, invoked with the *viewing* tmux
  session's name baked into its own command line (`status-format[1]` is a
  global tmux option, but tmux expands `#{session_name}` per attached client
  before running the job, so each session ends up polling its own,
  independently cached job). It prunes state files whose pane no longer
  exists or whose Claude process has died — server-wide, regardless of which
  session is asking, so a pane never gets orphaned just because its owning
  tmux session closed — then renders only the panes that belong to the
  viewing session, folding everyone else's into the `+N elsewhere` badge.
- `scripts/mark_seen.sh` is wired to tmux's `pane-focus-in` hook: looking at
  a pane that finished (green) clears it to idle (grey). "Finished and you
  saw it" and "finished and you haven't looked" are different states.
- `scripts/pane_picker.sh` is the cross-session reach: `<prefix>+m` lists
  *every* live Claude pane server-wide; the `+N elsewhere` badge calls the
  same script with `--exclude-session` to list just what the main row is
  hiding.

## Install

Via [TPM](https://github.com/tmux-plugins/tpm), add to `.tmux.conf`:

```tmux
set -g @plugin 'FlavianMF/tmux-claude-monitor'
```

then `prefix + I`.

Then wire the hook into Claude Code's `~/.claude/settings.json` — merge the
contents of [`hooks/settings-snippet.json`](hooks/settings-snippet.json) into
its `hooks` key (or into a plugin's own `hooks.json` if you're packaging this
as a Claude Code plugin instead).

No other dependencies: pure POSIX-ish `bash` + `awk`-free text parsing, no
`jq` required.

## Using it

- Click an indicator to jump to that pane.
- Click the `+N elsewhere` badge (only shown when another session has a live
  Claude pane) to pick from *those* panes specifically.
- `<prefix> + m` opens a menu of **every** live Claude Code pane server-wide
  — the reliable keyboard fallback if a click on a custom status range ever
  doesn't land on your terminal/tmux combination, and the general
  "reach anywhere" tool regardless of the badge.

## Options

Set any of these with `set -g <option> <value>` in `.tmux.conf`, before or
after loading the plugin:

| Option | Default | Meaning |
|---|---|---|
| `@claude_monitor_max_items` | `6` | Indicators (in the viewing session) shown before folding the rest into `+N` |
| `@claude_monitor_name_width` | `8` | Max characters of the tmux session name per indicator |
| `@claude_monitor_claude_name_width` | `18` | Max characters of the Claude-generated session name per indicator |
| `@claude_monitor_show_elapsed` | `yes` | Show time-in-state next to each dot |
| `@claude_monitor_state_dir` | `$XDG_STATE_HOME/tmux-claude-monitor/panes` | Where state files live |
| `@claude_monitor_color_working` | `@thm_red` → `colour1` | Working-state color (animates through 3 shades if `@thm_maroon`/`@thm_peach` are set — e.g. by [catppuccin/tmux](https://github.com/catppuccin/tmux)) |
| `@claude_monitor_color_waiting` | `@thm_yellow` → `colour3` | Waiting-state color |
| `@claude_monitor_color_done` | `@thm_green` → `colour2` | Done-state color |
| `@claude_monitor_color_idle` | `@thm_overlay_0` → `colour8` | Idle-state color |
| `@claude_monitor_color_blocked` | `@thm_peach` → `colour208` | `blocked` overlay color (from the daemon's own state, not the hook's 4-state model) |
| `@claude_monitor_color_failed` | `@thm_red` → `colour1` | `failed` overlay color |

Works standalone (falls back to plain `colourN` values) or picks up a loaded
catppuccin theme automatically via its `@thm_*` variables.

## Requirements

- tmux ≥ 3.0 (uses `status-format[]`, multi-row `status`, `range=user|`)
- `bash`, `/proc` (Linux; not tested on macOS/BSD, where the liveness check
  would need a `ps`-based fallback)
- Claude Code with hooks enabled; the Claude-side session name needs the
  Claude Code daemon (`~/.claude/jobs/`) or a readable transcript file —
  without either, indicators just fall back to the tmux session name alone

## License

MIT
