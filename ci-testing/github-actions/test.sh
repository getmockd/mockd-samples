#!/usr/bin/env bash
# test.sh — Contract tests for the Payment Service API
# Requires: mockd running with mockd.yaml, jq or python3 installed
# Usage: bash test.sh
set -euo pipefail

PASS=0
FAIL=0
BASE_URL="${BASE_URL:-http://localhost:4280}"
ADMIN_URL="${ADMIN_URL:-http://localhost:4290}"

# ── Helpers ──────────────────────────────────────────────────────────

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

json_field() {
  python3 -c "import json,sys; print(json.load(sys.stdin)$1)" 2>/dev/null
}

assert_status() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then pass "$desc"
  else fail "$desc (expected $expected, got $actual)"; fi
}

assert_json_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then pass "$desc"
  else fail "$desc (expected '$expected', got '$actual')"; fi
}

assert_contains() {
  local desc="$1" expected="$2" body="$3"
  if echo "$body" | grep -q "$expected" 2>/dev/null; then pass "$desc"
  else fail "$desc (expected body to contain '$expected')"; fi
}

# ── Wait for mockd ───────────────────────────────────────────────────

echo "=== Payment Service Contract Tests ==="
echo ""
echo "--- Health Check ---"

for i in $(seq 1 30); do
  if curl -sf "$ADMIN_URL/health" > /dev/null 2>&1; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "  FAIL: mockd did not become healthy within 30 seconds"
    exit 1
  fi
  sleep 1
done
pass "mockd is healthy"

# ── Test 1: Create an order ──────────────────────────────────────────

echo ""
echo "--- Create Order ---"

BODY=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "test@example.com",
    "items": [
      {"sku": "WIDGET-1", "name": "Blue Widget", "quantity": 3, "unit_price": 1500}
    ],
    "total": 4500,
    "currency": "usd",
    "status": "pending"
  }')
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')

assert_status "POST /api/orders returns 201" "201" "$STATUS"

# Verify response shape (contract)
ORDER_ID=$(echo "$BODY" | json_field "['id']")
ORDER_EMAIL=$(echo "$BODY" | json_field "['customer_email']")
ORDER_CREATED=$(echo "$BODY" | json_field "['createdAt']")

assert_json_eq "Response has correct email" "test@example.com" "$ORDER_EMAIL"

# ID has ord_ prefix
ID_PREFIX=$(echo "$ORDER_ID" | cut -c1-4)
assert_json_eq "Order ID has ord_ prefix" "ord_" "$ID_PREFIX"

# createdAt is present (ISO 8601 timestamp)
if [ -n "$ORDER_CREATED" ] && [ "$ORDER_CREATED" != "None" ]; then
  pass "Response has createdAt timestamp"
else
  fail "Response missing createdAt timestamp"
fi

# ── Test 2: Get order by ID ─────────────────────────────────────────

echo ""
echo "--- Get Order ---"

BODY=$(curl -s -w "\n%{http_code}" "$BASE_URL/api/orders/$ORDER_ID")
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')

assert_status "GET /api/orders/:id returns 200" "200" "$STATUS"
FETCHED_ID=$(echo "$BODY" | json_field "['id']")
assert_json_eq "Returned order matches created ID" "$ORDER_ID" "$FETCHED_ID"

# ── Test 3: Create a payment for the order ───────────────────────────

echo ""
echo "--- Create Payment ---"

BODY=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/payments" \
  -H "Content-Type: application/json" \
  -d "{
    \"order_id\": \"$ORDER_ID\",
    \"amount\": 4500,
    \"currency\": \"usd\",
    \"method\": \"card\",
    \"card_last4\": \"4242\",
    \"status\": \"succeeded\"
  }")
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')

assert_status "POST /api/payments returns 201" "201" "$STATUS"

PAYMENT_ID=$(echo "$BODY" | json_field "['id']")
PAYMENT_ORDER=$(echo "$BODY" | json_field "['order_id']")
PAYMENT_AMOUNT=$(echo "$BODY" | json_field "['amount']")

assert_json_eq "Payment linked to correct order" "$ORDER_ID" "$PAYMENT_ORDER"
assert_json_eq "Payment has correct amount" "4500" "$PAYMENT_AMOUNT"

# ID has pay_ prefix
PAY_PREFIX=$(echo "$PAYMENT_ID" | cut -c1-4)
assert_json_eq "Payment ID has pay_ prefix" "pay_" "$PAY_PREFIX"

# ── Test 4: List orders — verify pagination fields ───────────────────

echo ""
echo "--- List Orders ---"

BODY=$(curl -s "$BASE_URL/api/orders")

# Seed data has 2 orders + we created 1 = 3
ORDERS_LEN=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
ORDER_TOTAL=$(echo "$BODY" | json_field "['meta']['total']")

assert_json_eq "List orders returns 3 items" "3" "$ORDERS_LEN"
assert_json_eq "List meta.total is 3" "3" "$ORDER_TOTAL"
assert_contains "List response has 'data' array" '"data"' "$BODY"
assert_contains "List response has meta" '"meta"' "$BODY"

# ── Test 5: List payments ────────────────────────────────────────────

echo ""
echo "--- List Payments ---"

BODY=$(curl -s "$BASE_URL/api/payments")

# Seed data has 2 payments + we created 1 = 3
PAYMENTS_LEN=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "List payments returns 3 items" "3" "$PAYMENTS_LEN"

# ── Test 6: Get nonexistent resource returns 404 ─────────────────────

echo ""
echo "--- Error Handling ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/orders/ord_nonexistent")
assert_status "GET nonexistent order returns 404" "404" "$STATUS"

BODY=$(curl -s "$BASE_URL/api/orders/ord_nonexistent")
assert_contains "404 response has error message" '"message"' "$BODY"

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
