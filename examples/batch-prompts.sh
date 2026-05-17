#!/bin/bash
#
# batch-prompts.sh - Run claude-auto over a list of prompts.
#
# Reads a prompt file (one prompt per line, blank lines and lines starting
# with `#` ignored) and runs each prompt sequentially in its own detached
# tmux session. Each run gets its own dated transcript log under LOG_DIR.
#
# Usage:
#   ./batch-prompts.sh prompts.txt
#
# Example prompts.txt:
#   # Each line is one autonomous run.
#   Audit ~/code/foo for outdated npm dependencies and write the report to /tmp/foo-deps.md
#   Summarize the last 7 days of commits in ~/code/bar into /tmp/bar-week.md
#
# Optional env vars:
#   LOG_DIR       Directory for transcript logs (default: ./batch-logs).
#   CLAUDE_ARGS   Extra args forwarded to claude-auto.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_AUTO="$SCRIPT_DIR/../bin/claude-auto"

PROMPT_FILE="${1:?usage: batch-prompts.sh <prompt-file>}"
LOG_DIR="${LOG_DIR:-$PWD/batch-logs}"
CLAUDE_ARGS="${CLAUDE_ARGS:---dangerously-skip-permissions}"

mkdir -p "$LOG_DIR"

idx=0
while IFS= read -r prompt || [[ -n "$prompt" ]]; do
    # Skip blank lines and comments.
    [[ -z "${prompt// }" ]] && continue
    [[ "$prompt" =~ ^[[:space:]]*# ]] && continue

    idx=$((idx + 1))
    stamp="$(date +%Y%m%d-%H%M%S)"
    session="autonomy-batch-$stamp-$idx"
    log="$LOG_DIR/$stamp-$idx.log"

    echo "[$idx] $(date +%H:%M:%S) starting: ${prompt:0:80}"
    echo "      session: $session"
    echo "      log:     $log"

    tmux new-session -d -s "$session" \
        "'$CLAUDE_AUTO' --log '$log' $CLAUDE_ARGS '$prompt'; exit"

    # Wait for this run to finish before starting the next. Sequential is the
    # safe default — Claude's permission/auth state and CWD are shared. See
    # parallel-repos.sh for the parallel variant.
    while tmux has-session -t "$session" 2>/dev/null; do
        sleep 5
    done

    echo "[$idx] $(date +%H:%M:%S) done"
done <"$PROMPT_FILE"

echo
echo "Processed $idx prompt(s). Logs in: $LOG_DIR"
