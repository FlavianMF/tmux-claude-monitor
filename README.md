# tmux-claude-monitor

A second tmux status line that shows, at a glance, what every Claude Code
session across your tmux server is doing right now:

- 🔴 pulsing red — Claude is working
- 🟡 blinking yellow — Claude is waiting on you (a permission prompt, a
  question)
- 🟢 green — Claude just finished
- ⚪ grey — idle, or finished and already seen

Each indicator shows `session-name:%pane-id`, how long it's been in that
state, and can be clicked (or picked from a menu) to jump straight to that
pane.

State comes entirely from Claude Code's own hooks — no polling, no
transcript parsing, no scraping pane content.

## How it works

```
Claude Code hook  →  hooks/claude-state.sh  →  one state file per pane
                                                       ↓
                          tmux status-format[1]  ←  scripts/render.sh  (1×/s)
```

- `hooks/claude-state.sh` is wired into Claude Code's `settings.json` under
  six events (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `Notification`, `Stop`, `SessionEnd`). Each invocation writes (or removes)
  one small state file per tmux pane at
  `${XDG_STATE_HOME:-~/.local/state}/tmux-claude-monitor/panes/`.
- `scripts/render.sh` reads every state file once a second, drops entries
  whose pane no longer exists or whose Claude process has died (so a
  `kill -9` disappears from the bar even without `SessionEnd` ever firing),
  and prints the status-line string.
- `scripts/mark_seen.sh` is wired to tmux's `pane-focus-in` hook: looking at
  a pane that finished (green) clears it to idle (grey). "Finished and you
  saw it" and "finished and you haven't looked" are different states.

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
- `<prefix> + m` opens a menu of every live Claude Code pane — the reliable
  fallback if a click on a custom status range ever doesn't land on your
  terminal/tmux combination.

## Options

Set any of these with `set -g <option> <value>` in `.tmux.conf`, before or
after loading the plugin:

| Option | Default | Meaning |
|---|---|---|
| `@claude_monitor_max_items` | `6` | Indicators shown before folding the rest into `+N` |
| `@claude_monitor_name_width` | `8` | Max characters of the session name per indicator |
| `@claude_monitor_show_elapsed` | `yes` | Show time-in-state next to each dot |
| `@claude_monitor_state_dir` | `$XDG_STATE_HOME/tmux-claude-monitor/panes` | Where state files live |
| `@claude_monitor_color_working` | `@thm_red` → `colour1` | Working-state color (animates through 3 shades if `@thm_maroon`/`@thm_peach` are set — e.g. by [catppuccin/tmux](https://github.com/catppuccin/tmux)) |
| `@claude_monitor_color_waiting` | `@thm_yellow` → `colour3` | Waiting-state color |
| `@claude_monitor_color_done` | `@thm_green` → `colour2` | Done-state color |
| `@claude_monitor_color_idle` | `@thm_overlay_0` → `colour8` | Idle-state color |

Works standalone (falls back to plain `colourN` values) or picks up a loaded
catppuccin theme automatically via its `@thm_*` variables.

## Requirements

- tmux ≥ 3.0 (uses `status-format[]`, multi-row `status`, `range=user|`)
- `bash`, `/proc` (Linux; not tested on macOS/BSD, where the liveness check
  would need a `ps`-based fallback)
- Claude Code with hooks enabled

## License

MIT
