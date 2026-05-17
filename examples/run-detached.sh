#!/bin/bash
#
# run-detached.sh - Fire-and-forget wrapper around claude-auto.
#
# claude-auto refuses to run outside tmux. This script creates a detached
# tmux session, runs claude-auto inside it, blocks until the session is
# gone, and prints the transcript. It is the building block for invoking
# Autonomy from cron, launchd, CI, or any shell that isn't already inside
# a tmux session.
#
# Usage:
#   ./run-detached.sh "your prompt here"
#
# Optional env vars:
#   OUT_LOG       Path to the transcript log (default: /tmp/<session>.log).
#   CLAUDE_ARGS   Extra args forwarded to claude-auto (default:
#                 --dangerously-skip-permissions).
#
# Attach to watch progress live:
#   tmux attach -t <session-name printed at start>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_AUTO="$SCRIPT_DIR/../bin/claude-auto"

PROMPT="${1:?usage: run-detached.sh \"your prompt\"}"
SESSION="autonomy-$(date +%Y%m%d-%H%M%S)-$$"
OUT_LOG="${OUT_LOG:-/tmp/$SESSION.log}"
CLAUDE_ARGS="${CLAUDE_ARGS:---dangerously-skip-permissions}"

# Spawn a detached tmux session. The trailing `; exit` makes the pane (and
# therefore the session) close as soon as claude-auto returns, instead of
# leaving an idle shell around.
tmux new-session -d -s "$SESSION" \
    "'$CLAUDE_AUTO' --log '$OUT_LOG' $CLAUDE_ARGS '$PROMPT'; exit"

echo "Started detached tmux session: $SESSION"
echo "  attach:  tmux attach -t $SESSION"
echo "  log:     $OUT_LOG"
echo

# Block until the session is gone. Polling every few seconds is fine — the
# autonomous run will take minutes at minimum.
while tmux has-session -t "$SESSION" 2>/dev/null; do
    sleep 5
done

echo "Session finished. Transcript:"
echo "----"
cat "$OUT_LOG"
