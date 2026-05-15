# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

An alternative to `claude -p` for running unattended sessions that remain
observable inside `tmux`. The real Claude TUI runs in a tmux pane; a
Claude Code plugin's hooks drive the session toward `/exit` autonomously
by sending keystrokes to the pane.

There is no build step, no test suite, and no linter configuration. The
project ships two shell/Python entry points and three hook scripts.

## End-to-end flow

`bin/claude-auto` is the only entry point users invoke. It:

1. Generates a fresh lowercase UUID for `--session-id`.
2. Spawns `claude --dangerously-skip-permissions --session-id <uuid> --plugin-dir <repo-root>` plus any extra args.
3. When stdout/stderr are piped (e.g. `claude-auto … | tee log.txt`), dups the inherited tty stdin onto fds 1 and 2 so the Bun-bundled TUI still renders on the terminal. Bare `/dev/tty` is not used because Bun crashes when wrapping it in `tty.WriteStream`.
4. After `claude` exits, runs `bin/claude-transcript --raw <uuid>` and either prints to stdout or appends to `--log <file>`.
5. Propagates Claude's exit code.

The plugin loaded via `--plugin-dir` is this repo itself. `hooks/hooks.json` registers three hooks against `CLAUDE_PLUGIN_ROOT`.

## The Stop-hook completion protocol

This is the load-bearing piece — read it before changing anything in `hooks/`.

`hooks/handle-stop.py` reads the Stop hook's JSON from stdin and inspects `last_assistant_message`:

- **`"done"`** → types `/exit` + `Enter` into `$TMUX_PANE`, ending the session.
- **`"waiting"`** → does nothing; the session sits idle until something else resumes it (intended for cases where Claude has dispatched a background job and shouldn't be /exit'd).
- **anything else** → types the `NUDGE` string asking Claude to reply with `"done"` or `"waiting"` on its next turn, then `Enter`. The next Stop event re-checks.

Notes that bite:
- The handler sleeps 1s before `send-keys` so the Stop event settles in the TUI before keystrokes arrive at the prompt box.
- A second 1s sleep separates the text from the `Enter` keypress — sending `Enter` immediately after text only inserts a newline in Claude's prompt box; the pause makes it submit.
- The hook is registered with `"async": true` in `hooks/hooks.json`.
- `hooks/autonomous-context.txt` does **not** currently spell out the `done`/`waiting` protocol — Claude learns it from the nudge on the first Stop. If you change the protocol words, update both `handle-stop.py` and the nudge text.

## StopFailure retry counter

`hooks/handle-stop-failure.sh` keeps a per-session counter at `${TMPDIR:-/tmp}/${CLAUDE_CODE_SESSION_ID}`:

- Counts ≤ 5: sleep 10s, then `tmux send-keys -t $TMUX_PANE Up Enter` to re-submit the previous prompt.
- Count > 5: delete the counter file, sleep 1s, send `/exit Enter`.

The counter file is keyed by the session ID, so parallel sessions don't collide. Counter cleanup only happens on the give-up path; a session that succeeds leaves stale counters in `$TMPDIR` — fine, since the next session has a different UUID.

## tmux is mandatory

Every side effect in the hooks targets the current tmux pane via `$TMUX_PANE`. If `claude-auto` is run outside tmux, `handle-stop.py` logs and no-ops; `handle-stop-failure.sh` will fail because `tmux send-keys` has no target. The README's "Requirements" section lists tmux for this reason.

## `claude-transcript` conventions

- Looks for `<session-id>.jsonl` under `$CLAUDE_CONFIG_DIR/projects/*/` (env var) or `~/.claude/projects/*/`. The session lives under whichever project dir matches the cwd at session start — the script iterates project dirs rather than computing the encoded cwd.
- Filters out tool calls, tool results, thinking blocks, sidechain bookkeeping, and "meta" user messages (anything that is wholly a `<system-reminder>…</system-reminder>` or starts with `<command-name>` — these are CLI-injected, not real user input).
- Default truncation is 2000 chars per message; `--raw` disables it. `claude-auto` always passes `--raw`.

## Running things

```
bin/claude-auto "your prompt"                         # prints transcript to stdout after exit
bin/claude-auto --log out.log --model opus "/cmd"    # appends transcript to out.log
bin/claude-transcript <uuid>                          # standalone narration dump (truncated)
bin/claude-transcript <uuid> --raw                    # no truncation
```

`--log` is consumed by `claude-auto` itself; everything else after the flags is forwarded verbatim to `claude`.
