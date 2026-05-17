# Autonomy examples

Recipes for driving `bin/claude-auto` from outside an interactive tmux
session — cron, launchd, CI, batch jobs, or anywhere you want to fire off
autonomous runs without babysitting them.

All scripts assume `claude-auto` lives at `../bin/claude-auto` relative
to this folder and that `tmux` is on `PATH`. They forward
`--dangerously-skip-permissions` by default; override via the
`CLAUDE_ARGS` env var if you want stricter permission handling.

## `run-detached.sh`

Fire-and-forget wrapper. Spawns a detached tmux session, runs
`claude-auto` inside it, blocks until the session exits, then prints the
transcript. The building block the other examples are built on — use it
directly whenever you have one prompt to run from a non-tmux shell.

```
./run-detached.sh "Audit ~/code/foo for outdated deps and write /tmp/foo.md"
```

Attach mid-run with `tmux attach -t <session>` (the name is printed at
launch).

## `batch-prompts.sh`

Runs a list of prompts sequentially, one detached tmux session per
prompt, each with its own dated log under `LOG_DIR`. The input file is
one prompt per line; blank lines and `#` comments are ignored.

```
./batch-prompts.sh prompts.txt
```

Sequential by design — Claude's auth state and the current working
directory are shared across runs, so serializing avoids surprises. Reach
for `parallel-repos.sh` when you actually want concurrency.

## `parallel-repos.sh`

Runs the same prompt across many repos concurrently, one detached tmux
session per repo with `cwd` pinned to the repo path. Waits for all of
them to finish and prints a per-repo summary. `MAX_PARALLEL` (default 4)
caps concurrency.

```
PROMPT="Audit deps and write ./AUTONOMY-AUDIT.md" \
  ./parallel-repos.sh ~/code/repo-a ~/code/repo-b ~/code/repo-c
```

Every concurrent session is a live `claude` invocation, so raise the cap
deliberately.

## `cron-daily-digest.sh`

Cron- and launchd-friendly recurring task. Self-bootstraps a detached
tmux session (cron has no tty), writes a date-stamped transcript and
digest under `DIGEST_DIR`, and enforces a `TIMEOUT_SECS` ceiling so a
hung run can't wedge the scheduler. The shipped prompt summarizes the
last 24h of commits across a list of repos — edit `PROMPT` and `REPOS`
to fit your workflow.

```
# crontab: weekdays at 08:00
0 8 * * 1-5 /Users/you/Autonomy/examples/cron-daily-digest.sh >> /tmp/digest-cron.log 2>&1
```
