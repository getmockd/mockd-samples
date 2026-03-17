#!/usr/bin/env bash
# test.sh — Regression tests for the MCP workflow todo API sample
# Requires: mockd installed, jq or python3 installed, ports 4280/4290 free
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

echo "=== MCP Workflow Todo API Tests ==="
echo ""

# Start fresh with the config file
$MOCKD_BIN stop 2>/dev/null || true
sleep 1
$MOCKD_BIN start --no-auth -c "$SCRIPT_DIR/mockd.yaml" --data-dir /tmp/mockd-mcp-workflow-test -d 2>/dev/null

# Wait for server to be ready
for i in $(seq 1 30); do
  if curl -sf "$ADMIN_URL/health" > /dev/null 2>&1; then
    break
  fi
  sleep 1
done
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/health")
assert_status "Server healthy" "200" "$STATUS"

# ── Test 1: List Todos (Seed Data) ───────────────────────────────────

echo ""
echo "--- List Todos (Seed Data) ---"

BODY=$(curl -s "$BASE_URL/api/todos")
assert_contains "List response has data array" '"data"' "$BODY"
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "Seed data: 2 todos" "2" "$COUNT"

# Verify seed data content
FIRST_TITLE=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print([x['title'] for x in d if x.get('id')=='1'][0])")
assert_json_eq "First todo is 'Buy groceries'" "Buy groceries" "$FIRST_TITLE"

SECOND_COMPLETED=$(echo "$BODY" | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print([x['completed'] for x in d if x.get('id')=='2'][0])")
assert_json_eq "Second todo is completed" "True" "$SECOND_COMPLETED"

# ── Test 2: Create a Todo ────────────────────────────────────────────

echo ""
echo "--- Create Todo ---"

BODY=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/todos" \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to production","completed":false}')
STATUS=$(echo "$BODY" | tail -1)
BODY=$(echo "$BODY" | sed '$d')
assert_status "Create todo returns 201" "201" "$STATUS"
assert_contains "Create returns title" "Deploy to production" "$BODY"
assert_contains "Create returns completed=false" "false" "$BODY"

# Extract the new todo's ID
TODO_ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

if [ -n "$TODO_ID" ]; then pass "Created todo has ID: $TODO_ID"
else fail "Created todo has an ID"; fi

# ── Test 3: Get Todo by ID ───────────────────────────────────────────

echo ""
echo "--- Get Todo by ID ---"

BODY=$(curl -s "$BASE_URL/api/todos/$TODO_ID")
assert_contains "Get returns title" "Deploy to production" "$BODY"

GOT_ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
assert_json_eq "Get returns correct ID" "$TODO_ID" "$GOT_ID"

# Verify getting a seed todo also works
BODY=$(curl -s "$BASE_URL/api/todos/1")
assert_contains "Get seed todo returns title" "Buy groceries" "$BODY"

# ── Test 4: Update Todo ──────────────────────────────────────────────

echo ""
echo "--- Update Todo ---"

BODY=$(curl -s -X PUT "$BASE_URL/api/todos/$TODO_ID" \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to production","completed":true}')
assert_contains "Update returns completed=true" "true" "$BODY"
assert_contains "Update returns title" "Deploy to production" "$BODY"

# Verify update persisted
BODY=$(curl -s "$BASE_URL/api/todos/$TODO_ID")
COMPLETED=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin)['completed'])")
assert_json_eq "Updated completed field persisted" "True" "$COMPLETED"

# ── Test 5: List After Create + Update ───────────────────────────────

echo ""
echo "--- List After Mutations ---"

BODY=$(curl -s "$BASE_URL/api/todos")
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "List shows 3 todos (2 seed + 1 created)" "3" "$COUNT"

# ── Test 6: Delete Todo ──────────────────────────────────────────────

echo ""
echo "--- Delete Todo ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/api/todos/$TODO_ID")
assert_status "Delete returns 204" "204" "$STATUS"

# Verify deleted (404)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/todos/$TODO_ID")
assert_status "Deleted todo returns 404" "404" "$STATUS"

# ── Test 7: List After Delete ────────────────────────────────────────

echo ""
echo "--- List After Delete ---"

BODY=$(curl -s "$BASE_URL/api/todos")
COUNT=$(echo "$BODY" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "List shows 2 todos (back to seed count)" "2" "$COUNT"

# ── Test 8: Get Non-Existent Todo (404) ──────────────────────────────

echo ""
echo "--- Error Handling ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/todos/nonexistent")
assert_status "Get non-existent todo returns 404" "404" "$STATUS"

# ── Test 9: State Reset ──────────────────────────────────────────────

echo ""
echo "--- State Reset ---"

# Create some todos
curl -s -X POST "$BASE_URL/api/todos" \
  -H "Content-Type: application/json" \
  -d '{"title":"Temp 1","completed":false}' >/dev/null
curl -s -X POST "$BASE_URL/api/todos" \
  -H "Content-Type: application/json" \
  -d '{"title":"Temp 2","completed":false}' >/dev/null

COUNT=$(curl -s "$BASE_URL/api/todos" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "Created 2 more todos (total 4)" "4" "$COUNT"

# Reset the table
$MOCKD_BIN stateful reset todos >/dev/null 2>&1

COUNT=$(curl -s "$BASE_URL/api/todos" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['data']))")
assert_json_eq "After reset, todos = 2 (seed data restored)" "2" "$COUNT"

# ── Cleanup ──────────────────────────────────────────────────────────

$MOCKD_BIN stop 2>/dev/null || true

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
