#!/usr/bin/env bash
# test.sh — Regression tests for the OpenAI API sample
# Requires: mockd installed, jq installed, ports 4280/4290 free
# Usage: ./test.sh
set -euo pipefail

PASS=0
FAIL=0
MOCKD_BIN="${MOCKD_BIN:-mockd}"
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

assert_json_type() {
  local desc="$1" body="$2"
  if echo "$body" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then pass "$desc"
  else fail "$desc (response is not valid JSON)"; fi
}

# ── Setup ────────────────────────────────────────────────────────────

echo "=== OpenAI API Sample Tests ==="
echo ""

# Download spec if not present
if [ ! -f openai.yaml ]; then
  echo "  Downloading OpenAI spec..."
  curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml
fi

# Start fresh
$MOCKD_BIN stop 2>/dev/null || true
sleep 1
$MOCKD_BIN start -c mockd.yaml --no-auth -d 2>/dev/null
sleep 2

# Verify server is healthy
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/health")
assert_status "Server healthy" "200" "$STATUS"

# ── Test 1: Models (seeded table) ────────────────────────────────────

echo ""
echo "--- Models (stateful, seeded) ---"

BODY=$(curl -s "$BASE_URL/models")
assert_json_type "GET /models returns valid JSON" "$BODY"
assert_contains "Response has 'data' field" "data" "$BODY"
assert_contains "Seed data includes gpt-4o" "gpt-4o" "$BODY"
assert_contains "Seed data includes gpt-4o-mini" "gpt-4o-mini" "$BODY"
assert_contains "Seed data includes gpt-3.5-turbo" "gpt-3.5-turbo" "$BODY"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/models/gpt-4o")
assert_status "GET /models/gpt-4o returns 200" "200" "$STATUS"

# ── Test 2: Assistants (stateful CRUD) ───────────────────────────────

echo ""
echo "--- Assistants (stateful CRUD) ---"

# Create
BODY=$(curl -s -X POST "$BASE_URL/assistants" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","name":"Test Assistant","instructions":"You are helpful."}')
assert_json_type "POST /assistants returns valid JSON" "$BODY"
assert_contains "Created assistant has 'id'" "id" "$BODY"
ASST_ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

# List
BODY=$(curl -s "$BASE_URL/assistants")
assert_json_type "GET /assistants returns valid JSON" "$BODY"
assert_contains "List has 'data' field" "data" "$BODY"
if [ -n "$ASST_ID" ]; then
  assert_contains "List contains created assistant" "$ASST_ID" "$BODY"
fi

# Get by ID
if [ -n "$ASST_ID" ]; then
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/assistants/$ASST_ID")
  assert_status "GET /assistants/{id} returns 200" "200" "$STATUS"
fi

# ── Test 3: Chat Completions (spec-generated) ────────────────────────

echo ""
echo "--- Chat Completions (spec-generated) ---"

BODY=$(curl -s -X POST "$BASE_URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello"}]}')
assert_json_type "POST /chat/completions returns valid JSON" "$BODY"
assert_contains "Response has 'choices' field" "choices" "$BODY"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello"}]}')
assert_status "POST /chat/completions returns 200" "200" "$STATUS"

# ── Test 4: Threads (stateful CRUD) ──────────────────────────────────

echo ""
echo "--- Threads (stateful CRUD) ---"

# Create
BODY=$(curl -s -X POST "$BASE_URL/threads" \
  -H "Content-Type: application/json" \
  -d '{}')
assert_json_type "POST /threads returns valid JSON" "$BODY"
assert_contains "Created thread has 'id'" "id" "$BODY"
THREAD_ID=$(echo "$BODY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

# Get by ID
if [ -n "$THREAD_ID" ]; then
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/threads/$THREAD_ID")
  assert_status "GET /threads/{id} returns 200" "200" "$STATUS"
fi

# Delete
if [ -n "$THREAD_ID" ]; then
  BODY=$(curl -s -X DELETE "$BASE_URL/threads/$THREAD_ID")
  assert_contains "Delete returns deleted:true" "deleted" "$BODY"
fi

# ── Test 5: Embeddings (spec-generated) ──────────────────────────────

echo ""
echo "--- Embeddings (spec-generated) ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Hello world"}')
assert_status "POST /embeddings returns 200" "200" "$STATUS"

# ── Cleanup ──────────────────────────────────────────────────────────

$MOCKD_BIN stop 2>/dev/null || true

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
