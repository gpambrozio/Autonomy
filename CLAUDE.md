# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

An alternative to `claude -p` for running unattended sessions that remain
observable inside `tmux`. The real Claude TUI runs in a tmux pane; a
Claude Code plugin's hooks drive the session toward `/exit` autonomously
by sending keystrokes to the pane.

There is no build step, no test suite, and no linter configuration. The
project ships two shell/Python entry points and a handful of hook scripts.

## End-to-end flow

`bin/claude-auto` is the only entry point users invoke. It:

1. Generates a fresh lowercase UUID for `--session-id`.
2. Spawns `claude --session-id <uuid> --plugin-url <Autonomy main.zip on GitHub>` plus any extra args. Permission handling is left to the caller — pass `--dangerously-skip-permissions` (or anything else) in the forwarded args if desired. Because the plugin is fetched from the published GitHub zip rather than the local checkout, edits to the hooks in this repo only take effect once they are pushed to `main`.
3. When stdout/stderr are piped (e.g. `claude-auto … | tee log.txt`), dups the inherited tty stdin onto fds 1 and 2 so the Bun-bundled TUI still renders on the terminal. Bare `/dev/tty` is not used because Bun crashes when wrapping it in `tty.WriteStream`.
4. After `claude` exits, runs `bin/claude-transcript --raw <uuid>` and either prints to stdout or appends to `--log <file>`.
5. Propagates Claude's exit code.

The plugin loaded via `--plugin-url` is this repo, published as a zip on GitHub. `hooks/hooks.json` registers four hooks against `CLAUDE_PLUGIN_ROOT`: SessionStart, PreToolUse (for `AskUserQuestion`), Stop, and StopFailure. To test local hook changes before pushing, run `claude` directly with `--plugin-dir <repo-root>` instead of going through `claude-auto`.

## The folder-trust watcher

An untrusted cwd makes `claude` show a "Quick safety check: Is this a project
you created or one you trust?" select dialog *before* the session exists, so
none of the plugin's hooks can answer it. `bin/claude-auto` therefore starts
`bin/claude-trust-watch` in the background (unless `CLAUDE_AUTO_TRUST=0`) and
kills it once `claude` exits.

The watcher polls `tmux capture-pane` every 0.5s for up to
`CLAUDE_AUTO_TRUST_TIMEOUT` seconds (default 60) and sends a bare `Enter`,
which takes the default-highlighted "Yes, I trust this folder" option. It
exits as soon as the dialog is gone, or silently at the timeout when the
directory was already trusted.

Detection requires *both* a trust-prompt line ("I trust this folder", "trust
the files in this folder", "Is this a project you created or one you trust")
*and* the `Enter to confirm` select-dialog footer — the footer is what keeps
normal session output that happens to mention trusting a folder from
triggering a stray `Enter` into Claude's prompt box. If a Claude Code update
rewords the dialog, `pane_shows_trust_prompt` is the thing to update.

Unlike the pane pokes in `hooks/`, this one lives in `bin/` and so does **not**
ship in the plugin zip — a local edit here takes effect immediately, no push
to `main` required.

## The `CLAUDE_AUTO_QUESTIONS_OK` switch

Two of the hooks branch on the `CLAUDE_AUTO_QUESTIONS_OK` env var, which is inherited from the caller's shell through `claude-auto` and into the hook subprocesses:

- **`CLAUDE_AUTO_QUESTIONS_OK=1`** — `hooks/session-start-context.sh` cats `autonomous-context.txt` (the original "ask only if absolutely necessary" wording), and `hooks/handle-ask-question.sh` exits 0 with no output (allows the tool through with no opinion).
- **Anything else (incl. unset, the default)** — SessionStart instead cats `autonomous-context-no-questions.txt` (strict no-questions wording), and the PreToolUse hook on `AskUserQuestion` prints a `PreToolUse` decision JSON with `permissionDecision: deny` and a `permissionDecisionReason` telling Claude to use its best judgement. The reason text is surfaced to Claude in place of a tool result, so the model continues without ever pausing for a human.

If you tweak the strict wording, keep it consistent between `autonomous-context-no-questions.txt` and the `permissionDecisionReason` in `handle-ask-question.sh` — Claude sees the latter only when it actually tries to ask.

## The Stop-hook completion protocol

This is the load-bearing piece — read it before changing anything in `hooks/`.

`hooks/handle-stop.py` reads the Stop hook's JSON from stdin and inspects `last_assistant_message`:

- **`"done"`** → types `/exit` + `Enter` into `$TMUX_PANE`, ending the session.
- **`"waiting"`** → does nothing; the session sits idle until something else resumes it (intended for cases where Claude has dispatched a background job and shouldn't be /exit'd).
- **anything else** → types the `NUDGE` string asking Claude to reply with `"done"` or `"waiting"` on its next turn, then `Enter`. The next Stop event re-checks.

Notes that bite:
- The handler sleeps 1s before `send-keys` so the Stop event settles in the TUI before keystrokes arrive at the prompt box.
- A second 1s sleep separates the text from the `Enter` keypress — sending `Enter` immediately after text only inserts a newline in Claude's prompt box; the pause makes it submit.
- `/exit` is not unconditional: with background tasks/agents still running, the TUI shows a "Background work is running" select dialog instead of exiting. Its default-highlighted option is "Exit anyway", so a plain `Enter` confirms. Both `handle-stop.py` (`confirm_exit_dialog`) and the give-up path of `handle-stop-failure.sh` poll `tmux capture-pane` for up to ~5s after submitting `/exit` and send that extra `Enter` when the dialog text ("Background work is running" / "Exit anyway") is visible. If a Claude Code update rewords the dialog, these matchers are the thing to update.
- The hook is registered with `"async": true` in `hooks/hooks.json`.
- `hooks/autonomous-context.txt` does **not** currently spell out the `done`/`waiting` protocol — Claude learns it from the nudge on the first Stop. If you change the protocol words, update both `handle-stop.py` and the nudge text.

## StopFailure retry counter

`hooks/handle-stop-failure.sh` keeps a per-session counter at `${TMPDIR:-/tmp}/${CLAUDE_CODE_SESSION_ID}`:

- Counts ≤ 5: sleep 10s, send `Up` to the pane, sleep 1s, then send `Enter` to re-submit the previous prompt. The 1s gap mirrors `handle-stop.py` — sending `Enter` immediately after `Up` can land before the TUI has restored the prior prompt into the input box.
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
