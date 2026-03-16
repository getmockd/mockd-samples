#!/usr/bin/env bash
# test.sh — Regression tests for the Twilio API sample
# Requires: mockd installed, jq installed, ports 4280/4290 free
# Usage: ./test.sh
set -euo pipefail

PASS=0
FAIL=0
MOCKD_BIN="${MOCKD_BIN:-mockd}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${BASE_URL:-http://localhost:4280}"
ADMIN_URL="${ADMIN_URL:-http://localhost:4290}"
ACCT="AC_test"

# ── Helpers ──────────────────────────────────────────────────────────

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

assert_status() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then pass "$desc"
  else fail "$desc (expected $expected, got $actual)"; fi
}

assert_contains() {
  local desc="$1" expected="$2" body="$3"
  if echo "$body" | grep -q "$expected" 2>/dev/null; then pass "$desc"
  else fail "$desc (expected body to contain '$expected')"; fi
}

assert_json_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then pass "$desc"
  else fail "$desc (expected '$expected', got '$actual')"; fi
}

# ── Setup ────────────────────────────────────────────────────────────

echo "=== Twilio API Sample Tests ==="
echo ""

# Download spec if not present
if [ ! -f "$SCRIPT_DIR/twilio.json" ]; then
  echo "  Downloading Twilio spec..."
  curl -sL https://raw.githubusercontent.com/twilio/twilio-oai/main/spec/json/twilio_api_v2010.json -o "$SCRIPT_DIR/twilio.json"
fi

# Start fresh with the config file
$MOCKD_BIN stop 2>/dev/null || true
sleep 1
$MOCKD_BIN start --no-auth -c "$SCRIPT_DIR/mockd.yaml" --data-dir /tmp/mockd-twilio-test -d 2>/dev/null
sleep 2

# Verify server is healthy
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/health")
assert_status "Server healthy" "200" "$STATUS"

# ── Test 1: Config-based Import ──────────────────────────────────────

echo ""
echo "--- Config-based Import ---"

# Verify a schema-generated endpoint works (list messages from seed data)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json")
assert_status "GET /Messages.json returns 200" "200" "$STATUS"

# ── Test 2: Messages — Stateful CRUD ─────────────────────────────────

echo ""
echo "--- Messages CRUD ---"

# Reset messages table to start clean
$MOCKD_BIN stateful reset messages >/dev/null 2>&1

# List messages (should have 2 seed messages after reset)
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json")
assert_contains "List messages has 'messages' envelope" '"messages"' "$BODY"
assert_contains "List messages has page field" '"page"' "$BODY"
assert_contains "List messages has page_size field" '"page_size"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['messages']))")
assert_json_eq "Seed data: 2 messages" "2" "$COUNT"

# Create a message
BODY=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json" \
  -H "Content-Type: application/json" \
  -d '{"From":"+15558675310","To":"+15559999999","Body":"Test message from mockd"}')
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')
assert_status "Create message returns 201" "201" "$STATUS"
assert_contains "Create message returns body text" "Test message from mockd" "$BODY"

# Extract the SID
MSG_SID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['sid'])")

# Verify SID format (SM + 32 hex chars = 34 total)
SID_PREFIX=$(echo "$MSG_SID" | cut -c1-2)
SID_LEN=${#MSG_SID}
assert_json_eq "Message SID has SM prefix" "SM" "$SID_PREFIX"
if [ "$SID_LEN" -eq 34 ]; then pass "Message SID is 34 chars"
else fail "Message SID is 34 chars (got $SID_LEN)"; fi

# Get message by SID
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages/$MSG_SID.json")
assert_contains "Get message returns body text" "Test message from mockd" "$BODY"
assert_contains "Get message has date_created" "date_created" "$BODY"

# List messages — now 3 (2 seed + 1 created)
COUNT=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json" | \
  python3 -c "import json,sys; print(len(json.load(sys.stdin)['messages']))")
assert_json_eq "List messages count = 3" "3" "$COUNT"

# Delete message
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages/$MSG_SID.json")
assert_status "Delete message returns 204" "204" "$STATUS"

# Verify deleted (404)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages/$MSG_SID.json")
assert_status "Deleted message returns 404" "404" "$STATUS"

# Verify Twilio error format on 404
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages/$MSG_SID.json")
assert_contains "404 error has code field" '"code"' "$BODY"
assert_contains "404 error has message field" '"message"' "$BODY"
assert_contains "404 error has status field" '"status"' "$BODY"

# ── Test 3: Calls — Stateful CRUD ────────────────────────────────────

echo ""
echo "--- Calls CRUD ---"

# Create a call
BODY=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/2010-04-01/Accounts/$ACCT/Calls.json" \
  -H "Content-Type: application/json" \
  -d '{"From":"+15558675310","To":"+15551112222","Url":"https://handler.twilio.com/twiml/test"}')
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')
assert_status "Create call returns 201" "201" "$STATUS"

CALL_SID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['sid'])")
CALL_PREFIX=$(echo "$CALL_SID" | cut -c1-2)
assert_json_eq "Call SID has CA prefix" "CA" "$CALL_PREFIX"

# List calls
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Calls.json")
assert_contains "List calls has 'calls' envelope" '"calls"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['calls']))")
if [ "$COUNT" -ge 2 ]; then pass "List calls has at least 2 (1 seed + 1 created)"
else fail "List calls has at least 2 (got $COUNT)"; fi

# Get call by SID
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Calls/$CALL_SID.json")
assert_contains "Get call returns from number" "+15558675310" "$BODY"

# ── Test 4: Accounts ─────────────────────────────────────────────────

echo ""
echo "--- Accounts ---"

# List accounts
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts.json")
assert_contains "List accounts has 'accounts' envelope" '"accounts"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['accounts']))")
if [ "$COUNT" -ge 1 ]; then pass "List accounts has at least 1 (seed account)"
else fail "List accounts has at least 1 (got $COUNT)"; fi

# Get the test account
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT.json")
assert_contains "Get account returns friendly_name" "My Twilio Test Account" "$BODY"
assert_contains "Get account has sid field" '"sid"' "$BODY"

# ── Test 5: Incoming Phone Numbers ───────────────────────────────────

echo ""
echo "--- Incoming Phone Numbers ---"

# List phone numbers
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/IncomingPhoneNumbers.json")
assert_contains "List phone numbers has envelope" '"incoming_phone_numbers"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['incoming_phone_numbers']))")
assert_json_eq "Seed data: 2 phone numbers" "2" "$COUNT"

# Verify phone number SID prefix
FIRST_SID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['incoming_phone_numbers'][0]['sid'])")
PN_PREFIX=$(echo "$FIRST_SID" | cut -c1-2)
assert_json_eq "Phone number SID has PN prefix" "PN" "$PN_PREFIX"

# ── Test 6: Recordings ───────────────────────────────────────────────

echo ""
echo "--- Recordings ---"

# List recordings
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Recordings.json")
assert_contains "List recordings has envelope" '"recordings"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['recordings']))")
assert_json_eq "Seed data: 1 recording" "1" "$COUNT"

# ── Test 7: Conferences ──────────────────────────────────────────────

echo ""
echo "--- Conferences ---"

# List conferences
BODY=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Conferences.json")
assert_contains "List conferences has envelope" '"conferences"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['conferences']))")
assert_json_eq "Seed data: 1 conference" "1" "$COUNT"

# ── Test 8: State Reset ──────────────────────────────────────────────

echo ""
echo "--- State Reset ---"

# Create some messages
curl -s -X POST "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json" \
  -H "Content-Type: application/json" \
  -d '{"From":"+15558675310","To":"+15559999999","Body":"Temp 1"}' >/dev/null
curl -s -X POST "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json" \
  -H "Content-Type: application/json" \
  -d '{"From":"+15558675310","To":"+15559999999","Body":"Temp 2"}' >/dev/null

COUNT=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json" | \
  python3 -c "import json,sys; print(len(json.load(sys.stdin)['messages']))")
if [ "$COUNT" -ge 4 ]; then pass "Created additional messages (count >= 4)"
else fail "Created additional messages (expected >= 4, got $COUNT)"; fi

# Reset messages table
$MOCKD_BIN stateful reset messages >/dev/null 2>&1

COUNT=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json" | \
  python3 -c "import json,sys; print(len(json.load(sys.stdin)['messages']))")
assert_json_eq "After reset, messages = 2 (seed data restored)" "2" "$COUNT"

# Calls unaffected by messages reset
CALL_COUNT=$(curl -s "$BASE_URL/2010-04-01/Accounts/$ACCT/Calls.json" | \
  python3 -c "import json,sys; print(len(json.load(sys.stdin)['calls']))")
if [ "$CALL_COUNT" -ge 1 ]; then pass "Calls unaffected by messages reset"
else fail "Calls unaffected by messages reset (got $CALL_COUNT)"; fi

# ── Test 9: Chaos Engineering ────────────────────────────────────────

echo ""
echo "--- Chaos Engineering ---"

# Enable chaos
$MOCKD_BIN chaos apply flaky >/dev/null 2>&1

# Send 20 requests, count errors
ERRORS=0
for i in $(seq 1 20); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json")
  if [ "$STATUS" != "200" ]; then ((ERRORS++)) || true; fi
done

if [ "$ERRORS" -gt 0 ]; then
  pass "Chaos flaky profile injected $ERRORS errors in 20 requests"
else
  fail "Chaos flaky profile should have injected at least 1 error (got 0 in 20 requests)"
fi

# Disable chaos
$MOCKD_BIN chaos disable >/dev/null 2>&1

# Verify back to normal
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/2010-04-01/Accounts/$ACCT/Messages.json")
assert_status "After chaos disable, Messages.json returns 200" "200" "$STATUS"

# ── Cleanup ──────────────────────────────────────────────────────────

$MOCKD_BIN stop 2>/dev/null || true

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
