#!/usr/bin/env bash
#
# Messages.app workflow: register a work item, notify your phone, and reply
# over iMessage to route a message into a tmux pane.
#
# Prerequisites:
#   - macOS with Messages.app configured
#   - `send-message --init` run once, with your phone number
#   - Full Disk Access granted to your terminal app, so the coordinator can read
#     ~/Library/Messages/chat.db. Grant it in System Settings > Privacy &
#     Security > Full Disk Access, then QUIT and relaunch the terminal. If a
#     tmux server was already running, `tmux kill-server` too — permissions are
#     inherited at launch.
#
# Run from the repository root:
#   ./examples/messages-mode-workflow.sh

set -e

cd "$(dirname "$0")/.."

WC="bundle exec ruby bin/work-coordinator"

# NOTE: replace with your own phone number in E.164 form (or an email address
# tied to your iMessage account). Messages mode will not start without it.
export WC_RECIPIENT="+1XXXXXXXXXX"

# NOTE: customize these.
REF="DEMO-123"
TMUX_SESSION="wc-example"
TMUX_TARGET="${TMUX_SESSION}:claude.0"

echo "==> Creating tmux session ${TMUX_SESSION}"
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" -n claude

# 1. Register the work item — identical to local mode. Only the transport
#    differs; routing is always by REF.
echo "==> Registering work item ${REF}"
REGISTER_OUTPUT=$($WC register \
  --title "Fix flaky checkout test" \
  --kind  jira \
  --ref   "$REF" \
  --repo  demo-service \
  --tmux  "$TMUX_TARGET")

echo "$REGISTER_OUTPUT"

WORK_ITEM_ID=$(echo "$REGISTER_OUTPUT" | awk '/^id:/{print $2}')
echo "==> Work item id: ${WORK_ITEM_ID}"

# 2. Mark it active.
echo "==> Starting work item"
$WC start "$WORK_ITEM_ID"

# 3. Show current state before handing off to the foreground daemon.
echo "==> Status"
$WC status

# 4. Send a notification to your phone. In real use the agent does this when it
#    reaches a question it cannot answer alone.
echo "==> Notifying ${WC_RECIPIENT}"
$WC notify "$WORK_ITEM_ID" "Should I update the checkout fixture?"

# 5. Tell the user what to send back. Every reply must begin with "ai: "
#    (lowercase, one space after the colon) — that filters out unrelated
#    messages in the same thread. The prefix and the REF are both stripped
#    before the body reaches the pane.
cat <<EOF

==> Reply from your iPhone with:

      ai: ${REF} yes, update the fixture and rerun the suite

    Within about 5 seconds the coordinator prints:

      Routed to ${WORK_ITEM_ID}: yes, update the fixture and rerun the suite

    and the body arrives in ${TMUX_TARGET}.

    Check status from another terminal while this runs:

      bundle exec ruby bin/work-coordinator status

EOF

# 6. Start the coordinator in messages mode, in the foreground. It polls
#    chat.db every few seconds. Ctrl-C to stop.
echo "==> Starting coordinator in messages mode (Ctrl-C to stop)"
$WC run --mode messages
