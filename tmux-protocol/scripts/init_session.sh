#!/bin/bash
# init_session.sh — Create a tmux session for AG conversation
#
# Usage: init_session.sh <session_id>
#
# Why this exists:
#   Bare `tmux new-session -d` produces no stdout → AG's run_command
#   backgrounds the command → AG loses track → conversation hangs.
#   This wrapper provides explicit stdout so run_command completes normally.

set -euo pipefail

SESSION_ID="${1:?Usage: init_session.sh <session_id>}"

# Kill existing session if any (idempotent)
tmux kill-session -t "$SESSION_ID" 2>/dev/null || true

# Create detached session
tmux new-session -d -s "$SESSION_ID" -x 200 -y 50

echo "TMUX_SESSION_READY: $SESSION_ID"
