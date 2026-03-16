#!/usr/bin/env bash
# test-config.sh — Tests for the Stripe API digital twin (config-file approach)
# This tests the full response transform layer: prefix IDs, unix timestamps,
# Stripe list envelope, form-encoded input, cursor pagination, error transforms.
#
# Requires: mockd installed, jq installed, python3 installed
# Usage: ./test-config.sh
# Env: MOCKD_BIN, BASE_URL, ADMIN_URL
set -euo pipefail

PASS=0
FAIL=0
MOCKD_BIN="${MOCKD_BIN:-mockd}"
BASE_URL="${BASE_URL:-http://localhost:4280}"
ADMIN_URL="${ADMIN_URL:-http://localhost:4290}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

assert_not_contains() {
  local desc="$1" unexpected="$2" body="$3"
  if echo "$body" | grep -q "$unexpected" 2>/dev/null; then fail "$desc (body contains '$unexpected')"
  else pass "$desc"; fi
}

json_field() {
  echo "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$2)" 2>/dev/null
}

# ── Setup ────────────────────────────────────────────────────────────

echo "=== Stripe API Digital Twin Tests (Config File) ==="
echo ""

# Start fresh with config file
$MOCKD_BIN stop 2>/dev/null || true
sleep 1
$MOCKD_BIN start --no-auth -c "$SCRIPT_DIR/mockd.yaml" --data-dir /tmp/mockd-stripe-config-test -d 2>/dev/null
sleep 2

# Verify server is healthy
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/health")
assert_status "Server healthy" "200" "$STATUS"

# ── Test 1: Prefix IDs ──────────────────────────────────────────────

echo ""
echo "--- Prefix IDs ---"

BODY=$(curl -s -X POST "$BASE_URL/v1/customers" \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Johnson","email":"alice@example.com"}')
CUSTOMER_ID=$(json_field "$BODY" "['id']")

if [[ "$CUSTOMER_ID" == cus_* ]]; then pass "Customer ID has cus_ prefix ($CUSTOMER_ID)"
else fail "Customer ID should have cus_ prefix (got $CUSTOMER_ID)"; fi

BODY=$(curl -s -X POST "$BASE_URL/v1/payment_intents" \
  -H "Content-Type: application/json" \
  -d '{"amount":2000,"currency":"usd"}')
PI_ID=$(json_field "$BODY" "['id']")

if [[ "$PI_ID" == pi_* ]]; then pass "Payment intent ID has pi_ prefix ($PI_ID)"
else fail "Payment intent ID should have pi_ prefix (got $PI_ID)"; fi

# ── Test 2: Create returns 200 (not 201) ─────────────────────────────

echo ""
echo "--- Create Status Override ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/v1/products" \
  -H "Content-Type: application/json" \
  -d '{"name":"Widget"}')
assert_status "Create product returns 200 (Stripe convention)" "200" "$STATUS"

# ── Test 3: Injected Fields ──────────────────────────────────────────

echo ""
echo "--- Injected Fields ---"

BODY=$(curl -s "$BASE_URL/v1/customers/$CUSTOMER_ID")
OBJECT=$(json_field "$BODY" "['object']")
assert_status "Customer has object=customer" "customer" "$OBJECT"

LIVEMODE=$(json_field "$BODY" "['livemode']")
assert_status "Customer has livemode=False" "False" "$LIVEMODE"

# ── Test 4: Unix Timestamps ──────────────────────────────────────────

echo ""
echo "--- Unix Timestamps ---"

CREATED=$(json_field "$BODY" "['created']")
# Unix timestamp should be a number (epoch seconds), not a string
IS_INT=$(python3 -c "print(isinstance($CREATED, int))" 2>/dev/null || echo "False")
assert_status "Timestamp 'created' is unix integer" "True" "$IS_INT"

# updatedAt should be hidden
assert_not_contains "updatedAt is hidden" "updatedAt" "$BODY"
# createdAt should be renamed to created
assert_not_contains "createdAt is renamed (not present as createdAt)" "createdAt" "$BODY"

# ── Test 5: Stripe List Envelope ─────────────────────────────────────

echo ""
echo "--- Stripe List Envelope ---"

BODY=$(curl -s "$BASE_URL/v1/customers")
OBJECT=$(json_field "$BODY" "['object']")
assert_status "List has object=list" "list" "$OBJECT"

URL=$(json_field "$BODY" "['url']")
assert_status "List has url=/v1/customers" "/v1/customers" "$URL"

# Should have 'data' array, not 'meta'
assert_contains "List has 'data' array" '"data"' "$BODY"
assert_not_contains "List has no 'meta' (hideMeta: true)" '"meta"' "$BODY"
assert_not_contains "List has no 'total' (hideMeta: true)" '"total"' "$BODY"

# ── Test 6: Computed has_more ────────────────────────────────────────

echo ""
echo "--- Computed has_more ---"

# Create more customers for pagination test
for i in $(seq 2 5); do
  curl -s -X POST "$BASE_URL/v1/customers" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"Customer $i\"}" >/dev/null
done

# List with limit=2 — should have has_more=true
BODY=$(curl -s "$BASE_URL/v1/customers?limit=2")
HAS_MORE=$(json_field "$BODY" "['has_more']")
assert_status "has_more=True with limit=2 and 5 items" "True" "$HAS_MORE"

DATA_LEN=$(json_field "$BODY" "['data'].__len__()")
assert_status "Returned 2 items with limit=2" "2" "$DATA_LEN"

# List all — should have has_more=false
BODY=$(curl -s "$BASE_URL/v1/customers?limit=100")
HAS_MORE=$(json_field "$BODY" "['has_more']")
assert_status "has_more=False with all items" "False" "$HAS_MORE"

# ── Test 7: Cursor Pagination ────────────────────────────────────────

echo ""
echo "--- Cursor Pagination ---"

# Get first page
BODY=$(curl -s "$BASE_URL/v1/customers?limit=2")
FIRST_PAGE_LAST_ID=$(json_field "$BODY" "['data'][-1]['id']")

# Get next page using starting_after
BODY=$(curl -s "$BASE_URL/v1/customers?limit=2&starting_after=$FIRST_PAGE_LAST_ID")
SECOND_PAGE_FIRST_ID=$(json_field "$BODY" "['data'][0]['id']")

if [ "$SECOND_PAGE_FIRST_ID" != "$FIRST_PAGE_LAST_ID" ]; then
  pass "Cursor pagination returns different items (page2[0]=$SECOND_PAGE_FIRST_ID != page1[-1]=$FIRST_PAGE_LAST_ID)"
else
  fail "Cursor pagination should return items after cursor"
fi

# ── Test 8: Form-Encoded Input ───────────────────────────────────────

echo ""
echo "--- Form-Encoded Input ---"

BODY=$(curl -s -X POST "$BASE_URL/v1/customers" \
  -d "name=Form+User" \
  -d "email=form@example.com" \
  -d "metadata[tier]=premium" \
  -d "metadata[source]=api")
assert_contains "Form-encoded creates customer" "Form User" "$BODY"
assert_contains "Form-encoded parses email" "form@example.com" "$BODY"

FORM_CUS_ID=$(json_field "$BODY" "['id']")
if [[ "$FORM_CUS_ID" == cus_* ]]; then pass "Form-created customer has cus_ prefix"
else fail "Form-created customer should have cus_ prefix (got $FORM_CUS_ID)"; fi

# Check nested metadata
META_TIER=$(json_field "$BODY" "['metadata']['tier']")
assert_status "Form bracket notation: metadata.tier=premium" "premium" "$META_TIER"

# ── Test 9: Delete Returns Body ──────────────────────────────────────

echo ""
echo "--- Delete with Response Body ---"

STATUS=$(curl -s -o /tmp/stripe-delete-body.json -w "%{http_code}" \
  -X DELETE "$BASE_URL/v1/customers/$CUSTOMER_ID")
assert_status "Delete returns 200 (not 204)" "200" "$STATUS"

DEL_BODY=$(cat /tmp/stripe-delete-body.json)
DEL_ID=$(json_field "$DEL_BODY" "['id']")
assert_status "Delete body has id" "$CUSTOMER_ID" "$DEL_ID"

DEL_OBJECT=$(json_field "$DEL_BODY" "['object']")
assert_status "Delete body has object=customer" "customer" "$DEL_OBJECT"

DEL_DELETED=$(json_field "$DEL_BODY" "['deleted']")
assert_status "Delete body has deleted=True" "True" "$DEL_DELETED"

# ── Test 10: Error Transform (Stripe format) ─────────────────────────

echo ""
echo "--- Error Transform ---"

BODY=$(curl -s "$BASE_URL/v1/customers/nonexistent-id")
ERR_TYPE=$(json_field "$BODY" "['error']['type']")
assert_status "404 error type = invalid_request_error" "invalid_request_error" "$ERR_TYPE"

ERR_CODE=$(json_field "$BODY" "['error']['code']")
assert_status "404 error code = resource_missing" "resource_missing" "$ERR_CODE"

assert_contains "Error has message" "message" "$BODY"

# ── Test 11: Items have all transform fields ─────────────────────────

echo ""
echo "--- Item Transform Consistency ---"

# List items and check each has transforms applied
BODY=$(curl -s "$BASE_URL/v1/customers?limit=3")
ITEMS_HAVE_OBJECT=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(all('object' in item for item in d['data']))")
assert_status "All list items have 'object' field" "True" "$ITEMS_HAVE_OBJECT"

ITEMS_HAVE_CREATED=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin); print(all('created' in item for item in d['data']))")
assert_status "All list items have 'created' timestamp" "True" "$ITEMS_HAVE_CREATED"

# ── Test 12: Partial Update (Stripe SDK Patch Semantics) ─────────────

echo ""
echo "--- Partial Update (Patch Semantics) ---"

# Create a customer with multiple fields
BODY=$(curl -s -X POST "$BASE_URL/v1/customers" \
  -d "name=PatchTest&email=patch@example.com&metadata[tier]=gold" \
  -H "Content-Type: application/x-www-form-urlencoded")
PATCH_ID=$(json_field "$BODY" "['id']")

# Update only the name (Stripe SDK sends only changed fields)
BODY=$(curl -s -X POST "$BASE_URL/v1/customers/$PATCH_ID" \
  -d "name=PatchTest+Updated" \
  -H "Content-Type: application/x-www-form-urlencoded")

# Verify: name changed, email survived, metadata survived
PATCHED_NAME=$(json_field "$BODY" "['name']")
assert_status "Patch: name updated" "PatchTest Updated" "$PATCHED_NAME"

PATCHED_EMAIL=$(json_field "$BODY" "['email']")
assert_status "Patch: email survived partial update" "patch@example.com" "$PATCHED_EMAIL"

PATCHED_TIER=$(json_field "$BODY" "['metadata']['tier']")
assert_status "Patch: metadata.tier survived partial update" "gold" "$PATCHED_TIER"

# ── Cleanup ──────────────────────────────────────────────────────────

$MOCKD_BIN stop 2>/dev/null || true
rm -f /tmp/stripe-delete-body.json

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
