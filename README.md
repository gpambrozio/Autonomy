# Autonomy

An alternative to `claude -p` for running unattended Claude Code sessions
that can be observed (and intervened in) live through `tmux`. The Claude
TUI runs as normal in a tmux pane, while a Claude Code plugin's hooks
drive the session toward completion autonomously.

## What it does

When loaded into a session, the plugin installs four hooks:

- **SessionStart** — runs `hooks/session-start-context.sh`, which injects
  a short context message telling Claude to work autonomously rather than
  dropping into plan mode or asking clarifying questions. The exact
  wording depends on `CLAUDE_AUTO_QUESTIONS_OK` (see below).
- **PreToolUse (`AskUserQuestion`)** — runs
  `hooks/handle-ask-question.sh`. When `CLAUDE_AUTO_QUESTIONS_OK` is not
  `1`, the hook denies the tool call with a stock "use your best
  judgement and continue" reason that Claude sees in place of a tool
  result. When the env var is `1`, the call is allowed through.
- **Stop** — runs `hooks/handle-stop.py`, which reads the
  `last_assistant_message` field from the hook input. If the message is
  the literal word `done`, the script types `/exit` into the controlling
  tmux pane to end the session; if Claude Code then shows its
  "Background work is running" confirmation dialog (because background
  tasks are still alive), the script presses Enter again to pick the
  default "Exit anyway" option so the session really ends. Otherwise it
  types a nudge prompt asking Claude to confirm it has nothing left to
  do.
- **StopFailure** — runs `hooks/handle-stop-failure.sh`, which keeps a
  per-session retry counter at `$TMPDIR/<session-id>`. Up to five
  consecutive failures it types `Up` + `Enter` to re-submit the previous
  prompt after a 10s wait. On the sixth failure it gives up and types
  `/exit`, confirming the "Background work is running" dialog the same
  way as the Stop handler if it appears.

All keystroke side-effects target the current tmux pane via `$TMUX_PANE`,
so the wrapper script must be run from inside tmux.

## Layout

```
.claude-plugin/plugin.json                       plugin manifest
hooks/hooks.json                                 hook registrations
hooks/session-start-context.sh                   SessionStart dispatcher
hooks/autonomous-context.txt                     SessionStart text when questions are OK
hooks/autonomous-context-no-questions.txt        SessionStart text when questions are blocked
hooks/handle-ask-question.sh                     PreToolUse handler for AskUserQuestion
hooks/handle-stop.py                             Stop handler (Python 3)
hooks/handle-stop-failure.sh                     StopFailure handler (bash)
bin/claude-auto                                  wrapper around `claude` + transcript dump
bin/claude-trust-watch                           auto-confirms the folder-trust dialog
bin/claude-transcript                            JSONL transcript -> readable narration
```

## The folder-trust prompt

Starting `claude` in a directory it has not been trusted for pops a
blocking dialog before the session exists:

```
Quick safety check: Is this a project you created or one you trust?
> 1. Yes, I trust this folder
  2. No, exit
```

No hook can answer it — the plugin isn't loaded yet at that point — so
`claude-auto` starts `bin/claude-trust-watch` in the background instead.
The watcher polls `tmux capture-pane` for the dialog and presses Enter to
take the default-highlighted "Yes, I trust this folder" option, then
exits. If the dialog never appears (the usual case for an already trusted
directory) it gives up quietly after 60 seconds.

To recognise the dialog it requires both a trust-prompt line and the
`Enter to confirm` footer of a select dialog, so ordinary session output
that mentions trusting a folder can't trigger a stray Enter.

- `CLAUDE_AUTO_TRUST=0` — don't start the watcher; leave the dialog for a
  human.
- `CLAUDE_AUTO_TRUST_TIMEOUT=<seconds>` — how long the watcher waits for
  the dialog before giving up (default 60).

```
CLAUDE_AUTO_TRUST=0 claude-auto "your prompt here"
```

## Allowing or blocking questions

By default Autonomy assumes nobody is watching: the `AskUserQuestion`
tool is denied at the PreToolUse hook with a stock "use your best
judgement and continue" reason, and the SessionStart context tells
Claude not to try in the first place.

If you do want to leave a human in the loop for blocked cases, export
`CLAUDE_AUTO_QUESTIONS_OK=1` in the shell that invokes `claude-auto`:

```
CLAUDE_AUTO_QUESTIONS_OK=1 claude-auto "your prompt here"
```

With the var set to `1`, `AskUserQuestion` is allowed through and the
injected context softens to "ask only if absolutely necessary." Any
other value (including unset) keeps the strict default.

## How to use

### `bin/claude-auto`

The entry point. Wraps `claude` with the flags Autonomy needs:

- `--session-id <fresh-uuid>`
- `--plugin-url <Autonomy main.zip on GitHub>` (so the hooks above are
  active)

Because the plugin is fetched from the published GitHub zip rather than
your local checkout, changes you make to the hooks here only take effect
once they are pushed to `main`. To try local changes first, run `claude`
directly with `--plugin-dir <this-repo>` instead of `claude-auto`.

Permission handling is left to you — pass `--dangerously-skip-permissions`
(or any other permission-related flag) through to `claude` if you want it.

After Claude exits it dumps the session narration via `claude-transcript`.
By default the narration prints to stdout; pass `--log <file>` to append
it to a file instead.

When `claude-auto` is called from a shell whose stdout is piped (for
example `claude-auto … | tee log.txt`), it dups the inherited tty stdin
into stdout and stderr so the Claude TUI still renders on the user's
terminal instead of being captured into the pipe. Only the
`claude-transcript` output goes through the wrapper's stdout.

```
claude-auto "your prompt here"
claude-auto --log session.log --effort max --model opus "/some-command"
```

### `bin/claude-transcript`

Helper used by `claude-auto` to produce the post-session dump. Reads a
Claude Code session JSONL and prints a chronological list of user
prompts and assistant narrative text. Tool calls, tool results, thinking
blocks, and bookkeeping records are skipped.

Looks for transcripts under `$CLAUDE_CONFIG_DIR/projects/...` when the
env var is set, otherwise `~/.claude/projects/...`.

```
claude-transcript <UUID>
claude-transcript <UUID> --raw      # no truncation of long messages
```

## Requirements

- macOS or Linux with `tmux` available on `$PATH`.
- Python 3.7+ for `handle-stop.py` and `claude-transcript`.
- `claude` CLI installed.
