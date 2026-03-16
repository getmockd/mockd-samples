#!/usr/bin/env bash
set -euo pipefail

# Mock the Twilio API — one script
# Requires: mockd installed (curl -fsSL https://get.mockd.io | sh)

MOCKD_BIN="${MOCKD_BIN:-mockd}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Twilio API Mock Setup ==="
echo ""

# Check if mockd is installed
if ! command -v "$MOCKD_BIN" &>/dev/null; then
  echo "Error: mockd not found. Install it with:"
  echo "  curl -fsSL https://get.mockd.io | sh"
  exit 1
fi

# Download spec if not present
if [ -f "$SCRIPT_DIR/twilio.json" ]; then
  echo "1. Twilio OpenAPI spec already present (twilio.json)"
else
  echo "1. Downloading Twilio's OpenAPI spec..."
  curl -sL https://raw.githubusercontent.com/twilio/twilio-oai/main/spec/json/twilio_api_v2010.json -o "$SCRIPT_DIR/twilio.json"
  echo "   Done ($(wc -c < "$SCRIPT_DIR/twilio.json") bytes)"
fi

echo ""
echo "2. Starting mockd with Twilio config..."
$MOCKD_BIN start --no-auth -c "$SCRIPT_DIR/mockd.yaml" -d 2>/dev/null
sleep 2

echo ""
echo "=== Twilio API is running at http://localhost:4280 ==="
echo ""
echo "Schema-generated endpoints: 197 (from Twilio's OpenAPI spec)"
echo "Stateful tables:            messages, calls, accounts,"
echo "                            incoming_phone_numbers, recordings,"
echo "                            conferences, participants"
echo ""
echo "Try it:"
echo ""
echo "  # List messages (includes 2 seeded messages)"
echo "  curl -s http://localhost:4280/2010-04-01/Accounts/AC_test/Messages.json | jq"
echo '  # → {"messages":[...],"page":0,"page_size":50,...}'
echo ""
echo "  # Send a message (it persists!)"
echo "  curl -s -X POST http://localhost:4280/2010-04-01/Accounts/AC_test/Messages.json \\"
echo "    -d 'From=+15558675310&To=+15551234567&Body=Hello from mockd!' | jq"
echo '  # → {"sid":"SM...","body":"Hello from mockd!","status":"queued",...}'
echo ""
echo "  # List calls"
echo "  curl -s http://localhost:4280/2010-04-01/Accounts/AC_test/Calls.json | jq"
echo ""
echo "  # List accounts"
echo "  curl -s http://localhost:4280/2010-04-01/Accounts.json | jq"
echo ""
echo "Chaos testing:"
echo "  mockd chaos apply flaky     # 30% error rate"
echo "  mockd chaos apply slow-api  # 200-800ms latency"
echo "  mockd chaos apply offline   # 100% 503 errors"
echo "  mockd chaos disable         # back to normal"
echo ""
echo "Reset state:"
echo "  mockd stateful reset messages"
echo "  mockd stateful reset calls"
