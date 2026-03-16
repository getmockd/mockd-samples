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

# Start fresh
$MOCKD_BIN stop 2>/dev/null || true
sleep 1
$MOCKD_BIN start --no-auth --data-dir /tmp/mockd-openai-test -d 2>/dev/null
sleep 2

# Verify server is healthy
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/health")
assert_status "Server healthy" "200" "$STATUS"

# ── Test 1: OpenAPI Import ───────────────────────────────────────────

echo ""
echo "--- OpenAPI Import ---"

if [ ! -f openai.yaml ]; then
  echo "  Downloading OpenAI spec..."
  curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml
fi

OUTPUT=$($MOCKD_BIN import openai.yaml 2>&1)
assert_contains "Spec imported" "mocks" "$OUTPUT"

# ── Test 2: Chat Completions ─────────────────────────────────────────

echo ""
echo "--- Chat Completions ---"

# Note: OpenAI paths don't include /v1/ prefix (spec is relative to server base URL)
BODY=$(curl -s -X POST "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer sk-fake" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}]}')
assert_json_type "POST /chat/completions returns valid JSON" "$BODY"
assert_contains "Response has 'choices' field" "choices" "$BODY"
assert_contains "Response has 'model' field" "model" "$BODY"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}]}')
assert_status "POST /chat/completions returns 200" "200" "$STATUS"

# ── Test 3: Models ───────────────────────────────────────────────────

echo ""
echo "--- Models ---"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/models")
assert_status "GET /models returns 200" "200" "$STATUS"

BODY=$(curl -s "$BASE_URL/models")
assert_json_type "GET /models returns valid JSON" "$BODY"

# ── Test 4: Embeddings ───────────────────────────────────────────────

echo ""
echo "--- Embeddings ---"

BODY=$(curl -s -X POST "$BASE_URL/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Hello world"}')
assert_json_type "POST /embeddings returns valid JSON" "$BODY"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Hello world"}')
assert_status "POST /embeddings returns 200" "200" "$STATUS"

# ── Test 5: Image Generation ─────────────────────────────────────────

echo ""
echo "--- Image Generation ---"

BODY=$(curl -s -X POST "$BASE_URL/images/generations" \
  -H "Content-Type: application/json" \
  -d '{"model":"dall-e-3","prompt":"a cat","n":1}')
assert_json_type "POST /images/generations returns valid JSON" "$BODY"

STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/images/generations" \
  -H "Content-Type: application/json" \
  -d '{"model":"dall-e-3","prompt":"a cat","n":1}')
assert_status "POST /images/generations returns 200" "200" "$STATUS"

# ── Test 6: Chaos Engineering ────────────────────────────────────────

echo ""
echo "--- Chaos Engineering ---"

# Enable chaos
$MOCKD_BIN chaos apply flaky >/dev/null 2>&1

# Send 20 requests, count errors
ERRORS=0
for i in $(seq 1 20); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/models")
  if [ "$STATUS" != "200" ]; then ERRORS=$((ERRORS + 1)); fi
done

if [ "$ERRORS" -gt 0 ]; then
  pass "Chaos flaky profile injected $ERRORS errors in 20 requests"
else
  fail "Chaos flaky profile should have injected at least 1 error (got 0 in 20 requests)"
fi

# Disable chaos
$MOCKD_BIN chaos disable >/dev/null 2>&1

# Verify back to normal
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/models")
assert_status "After chaos disable, /models returns 200" "200" "$STATUS"

# ── Cleanup ──────────────────────────────────────────────────────────

$MOCKD_BIN stop 2>/dev/null || true

# ── Results ──────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
