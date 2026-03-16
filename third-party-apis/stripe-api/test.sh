#!/usr/bin/env bash
# test.sh — Regression tests for the Stripe API sample
# Requires: mockd installed, jq installed, ports 4280/4290 free
# Usage: ./test.sh
set -euo pipefail

PASS=0
FAIL=0
MOCKD_BIN="${MOCKD_BIN:-mockd}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${BASE_URL:-http://localhost:4280}"
ADMIN_URL="${ADMIN_URL:-http://localhost:4290}"

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

echo "=== Stripe API Sample Tests ==="
echo ""

# Download spec if not present
if [ ! -f "$SCRIPT_DIR/stripe.yaml" ]; then
  echo "  Downloading Stripe spec..."
  curl -sL https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml -o "$SCRIPT_DIR/stripe.yaml"
fi

# Start fresh with the config file
$MOCKD_BIN stop 2>/dev/null || true
sleep 1
$MOCKD_BIN start --no-auth -c "$SCRIPT_DIR/mockd.yaml" --data-dir /tmp/mockd-stripe-test -d 2>/dev/null

# Wait for server to be ready (large spec can take 10+ seconds to parse)
for i in $(seq 1 30); do
  if curl -sf "$ADMIN_URL/health" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/health")
assert_status "Server healthy" "200" "$STATUS"

# ── Test 1: Config-based Import ──────────────────────────────────────

echo ""
echo "--- Config-based Import ---"

# Verify a schema-generated endpoint works
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/balance")
assert_status "GET /v1/balance returns 200" "200" "$STATUS"

BODY=$(curl -s "$BASE_URL/v1/balance")
assert_contains "/v1/balance has 'available' field" "available" "$BODY"

# ── Test 2: Stateful CRUD (Stripe-formatted responses) ───────────────

echo ""
echo "--- Stateful CRUD ---"

# List customers (empty initially)
BODY=$(curl -s "$BASE_URL/v1/customers")
OBJ=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['object'])")
assert_json_eq "List customers returns object=list" "list" "$OBJ"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "List customers initially empty" "0" "$COUNT"

# Create a customer
BODY=$(curl -s -X POST "$BASE_URL/v1/customers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Johnson","email":"alice@example.com"}')
assert_contains "Create customer returns name" "Alice Johnson" "$BODY"
assert_contains "Create customer returns email" "alice@example.com" "$BODY"
assert_contains "Create customer has object=customer" "customer" "$BODY"
CUSTOMER_ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# Verify ID has cus_ prefix
ID_PREFIX=$(echo "$CUSTOMER_ID" | cut -c1-4)
assert_json_eq "Customer ID has cus_ prefix" "cus_" "$ID_PREFIX"

# Create returns 200 (Stripe convention, not 201)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/customers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Temp","email":"temp@example.com"}')
assert_status "Create customer returns 200 (Stripe convention)" "200" "$STATUS"
# Clean up the temp customer
TEMP_ID=$(curl -s "$BASE_URL/v1/customers" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print([x['id'] for x in d if x.get('name')=='Temp'][0])")
curl -s -X DELETE "$BASE_URL/v1/customers/$TEMP_ID" >/dev/null

# Read (list) — Stripe envelope format
BODY=$(curl -s "$BASE_URL/v1/customers")
assert_contains "List response has object=list" '"object":"list"' "$BODY"
assert_contains "List response has data array" '"data"' "$BODY"
assert_contains "List response has has_more" '"has_more"' "$BODY"
assert_contains "List response has url" '"/v1/customers"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "List customers count = 1" "1" "$COUNT"

# Read (by ID)
BODY=$(curl -s "$BASE_URL/v1/customers/$CUSTOMER_ID")
assert_contains "Get customer by ID returns Alice" "Alice Johnson" "$BODY"
assert_contains "Get customer has object=customer" '"object":"customer"' "$BODY"

# Update (POST, not PUT — Stripe convention via action: patch)
BODY=$(curl -s -X POST "$BASE_URL/v1/customers/$CUSTOMER_ID" \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Smith","email":"alice.smith@example.com"}')
assert_contains "Update customer returns new name" "Alice Smith" "$BODY"

# Verify update persisted
BODY=$(curl -s "$BASE_URL/v1/customers/$CUSTOMER_ID")
assert_contains "Updated name persisted" "Alice Smith" "$BODY"

# Create payment intent linked to customer
BODY=$(curl -s -X POST "$BASE_URL/v1/payment_intents" \
  -H "Content-Type: application/json" \
  -d "{\"amount\":2000,\"currency\":\"usd\",\"customer\":\"$CUSTOMER_ID\"}")
assert_contains "Payment intent has amount" "2000" "$BODY"
assert_contains "Payment intent has object=payment_intent" '"object":"payment_intent"' "$BODY"
PI_ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# Verify payment intent ID has pi_ prefix
PI_PREFIX=$(echo "$PI_ID" | cut -c1-3)
assert_json_eq "Payment intent ID has pi_ prefix" "pi_" "$PI_PREFIX"

# Get payment intent
BODY=$(curl -s "$BASE_URL/v1/payment_intents/$PI_ID")
assert_contains "Get payment intent returns amount" "2000" "$BODY"

# Delete customer — returns 200 with deletion confirmation
BODY=$(curl -s -w "\n%{http_code}" -X DELETE "$BASE_URL/v1/customers/$CUSTOMER_ID")
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')
assert_status "Delete customer returns 200" "200" "$STATUS"
assert_contains "Delete response has deleted=true" '"deleted":true' "$BODY"
assert_contains "Delete response has customer ID" "$CUSTOMER_ID" "$BODY"

# Verify deleted (404)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/customers/$CUSTOMER_ID")
assert_status "Deleted customer returns 404" "404" "$STATUS"

# Verify error format on 404
BODY=$(curl -s "$BASE_URL/v1/customers/$CUSTOMER_ID")
assert_contains "404 error has Stripe error envelope" '"error"' "$BODY"
assert_contains "404 error has type field" '"type"' "$BODY"
assert_contains "404 error has message field" '"message"' "$BODY"

# List should be empty
COUNT=$(curl -s "$BASE_URL/v1/customers" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "List customers after delete = 0" "0" "$COUNT"

# ── Test 3: State Reset ──────────────────────────────────────────────

echo ""
echo "--- State Reset ---"

# Create some data
curl -s -X POST "$BASE_URL/v1/customers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Bob","email":"bob@example.com"}' >/dev/null
curl -s -X POST "$BASE_URL/v1/customers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Carol","email":"carol@example.com"}' >/dev/null

COUNT=$(curl -s "$BASE_URL/v1/customers" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "Created 2 customers" "2" "$COUNT"

# Reset
$MOCKD_BIN stateful reset customers >/dev/null 2>&1

COUNT=$(curl -s "$BASE_URL/v1/customers" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "After reset, customers = 0" "0" "$COUNT"

# Payment intent still exists (different table)
PI_COUNT=$(curl -s "$BASE_URL/v1/payment_intents" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "Payment intents unaffected by customer reset" "1" "$PI_COUNT"

# ── Test 4: Chaos Engineering ────────────────────────────────────────

echo ""
echo "--- Chaos Engineering ---"

# Enable chaos
$MOCKD_BIN chaos apply flaky >/dev/null 2>&1

# Send 20 requests, count errors
ERRORS=0
for i in $(seq 1 20); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/balance")
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
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/balance")
assert_status "After chaos disable, /v1/balance returns 200" "200" "$STATUS"

# ── Cleanup ──────────────────────────────────────────────────────────

$MOCKD_BIN stop 2>/dev/null || true

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
