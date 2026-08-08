#!/usr/bin/env bash
#
# Local socket workflow: register a work item, start the coordinator, and route
# a message to the tmux pane where an agent is waiting.
#
# Run from the repository root:
#   ./examples/local-socket-workflow.sh

set -e

cd "$(dirname "$0")/.."

WC="bundle exec ruby bin/work-coordinator"

# NOTE: customize these. REF is the routing key — any message beginning with it
# is delivered to TMUX_TARGET.
REF="DEMO-123"
TMUX_SESSION="wc-example"
TMUX_TARGET="${TMUX_SESSION}:claude.0"

# The pane that receives routed messages. In real use this is a Claude Code
# session; here it is a plain shell so you can watch the text arrive.
echo "==> Creating tmux session ${TMUX_SESSION}"
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" -n claude

# 1. Register the work item. Migrations run automatically on first invocation.
echo "==> Registering work item ${REF}"
REGISTER_OUTPUT=$($WC register \
  --title "Fix flaky checkout test" \
  --kind  jira \
  --ref   "$REF" \
  --repo  demo-service \
  --tmux  "$TMUX_TARGET")

echo "$REGISTER_OUTPUT"

# 2. Capture the UUID. `register` prints "id:    <uuid>" on its first line.
WORK_ITEM_ID=$(echo "$REGISTER_OUTPUT" | awk '/^id:/{print $2}')
echo "==> Work item id: ${WORK_ITEM_ID}"

# 3. Mark it active.
echo "==> Starting work item"
$WC start "$WORK_ITEM_ID"

# 4. Start the coordinator in the background. It opens the Unix socket at
#    WC_SOCKET (default /tmp/work-coordinator.sock) and listens.
#    NOTE: in normal use you run this in its own terminal, in the foreground.
echo "==> Starting coordinator in local mode"
$WC run --mode local &
COORDINATOR_PID=$!

# Stop the coordinator on exit, however this script ends. The daemon traps TERM
# and removes its socket file cleanly.
cleanup() {
  echo "==> Stopping coordinator (pid ${COORDINATOR_PID})"
  kill "$COORDINATOR_PID" 2>/dev/null || true
  wait "$COORDINATOR_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Give the socket a moment to appear before sending to it.
sleep 2

# 5. Send a message. Format is "<REF> <body>": the REF must match exactly
#    (case-sensitive), separated from the body by a single space. The
#    coordinator strips the REF and delivers only the body to the pane.
echo "==> Sending a message"
$WC send "${REF} yes, update the fixture and rerun the suite"

sleep 1

# 6. Check status. The item shows as active, and the pane holds the body.
echo "==> Status"
$WC status

echo "==> Contents of ${TMUX_TARGET}"
tmux capture-pane -p -t "$TMUX_TARGET"

# 7. The trap above stops the coordinator. Clean up the demo tmux session too.
echo "==> Removing tmux session ${TMUX_SESSION}"
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
