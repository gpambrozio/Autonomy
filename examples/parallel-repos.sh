#!/bin/bash
#
# parallel-repos.sh - Run the same autonomous task across many repos in
# parallel, one detached tmux session per repo.
#
# Each session runs in its own tmux session with cwd set to the repo, so
# Claude's tool calls operate on that repo. Sessions run concurrently;
# this script waits for all of them to finish, then prints a per-repo
# summary line.
#
# Usage:
#   ./parallel-repos.sh ~/code/repo-a ~/code/repo-b ~/code/repo-c
#
# Optional env vars:
#   PROMPT          The prompt to run in each repo. Defaults to a simple
#                   dependency audit example.
#   LOG_DIR         Directory for transcript logs (default: ./parallel-logs).
#   MAX_PARALLEL    Cap on concurrent sessions (default: 4). Set high
#                   carefully — every session is a live Claude invocation.
#   CLAUDE_ARGS     Extra args forwarded to claude-auto.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_AUTO="$SCRIPT_DIR/../bin/claude-auto"

if [[ $# -lt 1 ]]; then
    echo "usage: parallel-repos.sh <repo-path> [<repo-path>...]" >&2
    exit 2
fi

PROMPT="${PROMPT:-Audit this repo for outdated or vulnerable dependencies. Write a short markdown report to ./AUTONOMY-AUDIT.md in the repo root.}"
LOG_DIR="${LOG_DIR:-$PWD/parallel-logs}"
MAX_PARALLEL="${MAX_PARALLEL:-4}"
CLAUDE_ARGS="${CLAUDE_ARGS:---dangerously-skip-permissions}"

mkdir -p "$LOG_DIR"

# Track sessions we spawned so we can wait on exactly those.
declare -a SESSIONS=()
declare -a REPOS=()
declare -a LOGS=()

wait_until_under_cap() {
    while true; do
        local running=0
        for s in "${SESSIONS[@]}"; do
            if tmux has-session -t "$s" 2>/dev/null; then
                running=$((running + 1))
            fi
        done
        if (( running < MAX_PARALLEL )); then
            return
        fi
        sleep 5
    done
}

stamp="$(date +%Y%m%d-%H%M%S)"
idx=0
for repo in "$@"; do
    if [[ ! -d "$repo" ]]; then
        echo "skip: $repo (not a directory)" >&2
        continue
    fi
    idx=$((idx + 1))
    name="$(basename "$repo")"
    session="autonomy-par-$stamp-$idx-$name"
    log="$LOG_DIR/$stamp-$name.log"

    wait_until_under_cap

    echo "[+] launching $session ($repo)"
    # `-c "$repo"` sets the working directory for the new session so any
    # file edits Claude makes land inside the right repo.
    tmux new-session -d -s "$session" -c "$repo" \
        "'$CLAUDE_AUTO' --log '$log' $CLAUDE_ARGS '$PROMPT'; exit"

    SESSIONS+=("$session")
    REPOS+=("$repo")
    LOGS+=("$log")
done

echo
echo "Spawned ${#SESSIONS[@]} session(s). Waiting for completion..."

# Wait until none of our sessions are alive.
while true; do
    alive=0
    for s in "${SESSIONS[@]}"; do
        if tmux has-session -t "$s" 2>/dev/null; then
            alive=$((alive + 1))
        fi
    done
    if (( alive == 0 )); then
        break
    fi
    echo "  $(date +%H:%M:%S) $alive still running..."
    sleep 15
done

echo
echo "All sessions finished."
for i in "${!SESSIONS[@]}"; do
    echo "  ${REPOS[$i]}"
    echo "    log: ${LOGS[$i]}"
done
