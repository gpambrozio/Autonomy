#!/bin/bash
#
# cron-daily-digest.sh - Cron-friendly recurring task.
#
# Runs an autonomous Claude session once and writes the transcript to a
# date-stamped file. Designed to be scheduled from cron or launchd. The
# script self-bootstraps a detached tmux session, so cron does not need to
# already be inside tmux.
#
# Example crontab (every weekday at 8:00 AM):
#   0 8 * * 1-5 /Users/you/Autonomy/examples/cron-daily-digest.sh >> /tmp/digest-cron.log 2>&1
#
# What this particular script does: asks Claude to summarize yesterday's
# commits across a list of repos and write a markdown digest. Edit PROMPT
# and REPOS to fit your workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_AUTO="$SCRIPT_DIR/../bin/claude-auto"

# Where to drop daily digests. One file per run.
DIGEST_DIR="${DIGEST_DIR:-$HOME/autonomy-digests}"
mkdir -p "$DIGEST_DIR"

TODAY="$(date +%Y-%m-%d)"
OUT_LOG="$DIGEST_DIR/$TODAY-transcript.log"
DIGEST_FILE="$DIGEST_DIR/$TODAY-digest.md"

# Repos to scan. Override REPOS env var with a colon-separated list to
# customize without editing the script.
REPOS="${REPOS:-$HOME/code/project-a:$HOME/code/project-b}"

PROMPT="You are running unattended. For each of these git repos, list the commits authored in the last 24 hours and write a concise markdown digest to $DIGEST_FILE. Group by repo; include commit hash, author, subject. If there are no recent commits in a repo, note that. Repos: $REPOS"

# cron has no tty. Make sure claude-auto's tmux check still passes by
# spawning a detached session ourselves.
SESSION="autonomy-digest-$(date +%Y%m%d-%H%M%S)"

tmux new-session -d -s "$SESSION" \
    "'$CLAUDE_AUTO' --log '$OUT_LOG' --dangerously-skip-permissions '$PROMPT'; exit"

echo "[$(date)] launched $SESSION; log -> $OUT_LOG"

# Block until the session is gone, with a safety timeout so a hung run
# can't wedge cron forever.
TIMEOUT_SECS="${TIMEOUT_SECS:-1800}"   # 30 minutes
start=$(date +%s)
while tmux has-session -t "$SESSION" 2>/dev/null; do
    now=$(date +%s)
    if (( now - start > TIMEOUT_SECS )); then
        echo "[$(date)] timeout after ${TIMEOUT_SECS}s; killing $SESSION" >&2
        tmux kill-session -t "$SESSION" 2>/dev/null || true
        exit 124
    fi
    sleep 10
done

echo "[$(date)] done; digest at $DIGEST_FILE"
