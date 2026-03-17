#!/usr/bin/env bash
# test.sh — Validate all mock endpoints for the microservices sample.
#
# Usage:
#   ./test.sh                    # test against localhost:4280
#   ./test.sh http://mockd:4280  # test against a custom base URL
#
# Prerequisites: curl, jq

set -euo pipefail

BASE_URL="${1:-http://localhost:4280}"
PASS=0
FAIL=0

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

assert_status() {
  local description="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    green "  PASS  $description (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL  $description (expected $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local description="$1" body="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$body" | jq -r "$field" 2>/dev/null || echo "PARSE_ERROR")
  if [ "$actual" = "$expected" ]; then
    green "  PASS  $description ($field = $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL  $description ($field: expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

# --------------------------------------------------------------------------
# Wait for mockd to be healthy
# --------------------------------------------------------------------------
bold "Waiting for mockd at $BASE_URL ..."
ADMIN_URL="${BASE_URL%:4280}:4290"
for i in $(seq 1 30); do
  if curl -sf "$ADMIN_URL/health" > /dev/null 2>&1; then
    green "  mockd is healthy"
    break
  fi
  if [ "$i" -eq 30 ]; then
    red "  mockd did not become healthy after 30 attempts"
    exit 1
  fi
  sleep 1
done
echo ""

# ==========================================================================
bold "User Service"
# ==========================================================================

# List users — should return seed data
bold "  GET /users (list)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/users")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "list users" "200" "$STATUS"
assert_json_field "seed data present" "$BODY" '.data | length' "2"
# Verify seed data contains expected names (order not guaranteed)
echo "$BODY" | jq -e '.data | map(.name) | contains(["Alice Johnson"])' > /dev/null && \
  green "  PASS  seed data contains Alice Johnson" && PASS=$((PASS + 1)) || \
  (red "  FAIL  seed data missing Alice Johnson" && FAIL=$((FAIL + 1)))

# Get user by ID
bold "  GET /users/usr_1 (get)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/users/usr_1")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "get user" "200" "$STATUS"
assert_json_field "user id" "$BODY" '.id' "usr_1"
assert_json_field "user email" "$BODY" '.email' "alice@example.com"

# Create user
bold "  POST /users (create)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Dave Wilson","email":"dave@example.com","plan":"free","role":"member"}')
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "create user" "201" "$STATUS"
assert_json_field "user name" "$BODY" '.name' "Dave Wilson"
NEW_USER_ID=$(echo "$BODY" | jq -r '.id')

# Verify created user shows up in list
bold "  GET /users (list after create)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/users")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "list after create" "200" "$STATUS"
assert_json_field "count increased" "$BODY" '.data | length' "3"

# Get the newly created user
bold "  GET /users/$NEW_USER_ID (get created)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/users/$NEW_USER_ID")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "get created user" "200" "$STATUS"
assert_json_field "created user name" "$BODY" '.name' "Dave Wilson"

echo ""

# ==========================================================================
bold "Payment Service"
# ==========================================================================

# List payments — should return seed data
bold "  GET /payments (list)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/payments")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "list payments" "200" "$STATUS"
assert_json_field "seed data present" "$BODY" '.data | length' "2"
# Verify seed data contains expected statuses (order not guaranteed)
echo "$BODY" | jq -e '.data | map(.status) | contains(["completed"])' > /dev/null && \
  green "  PASS  seed data contains completed payment" && PASS=$((PASS + 1)) || \
  (red "  FAIL  seed data missing completed payment" && FAIL=$((FAIL + 1)))

# Get payment by ID
bold "  GET /payments/pay_1 (get)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/payments/pay_1")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "get payment" "200" "$STATUS"
assert_json_field "payment id" "$BODY" '.id' "pay_1"
assert_json_field "payment amount" "$BODY" '.amount' "2999"
assert_json_field "payment userId" "$BODY" '.userId' "usr_1"

# Create payment
bold "  POST /payments (create)"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/payments" \
  -H "Content-Type: application/json" \
  -d '{"userId":"usr_2","amount":4999,"currency":"usd","status":"pending","description":"Upgrade to pro"}')
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "create payment" "201" "$STATUS"
assert_json_field "payment amount" "$BODY" '.amount' "4999"
assert_json_field "payment userId" "$BODY" '.userId' "usr_2"
NEW_PAY_ID=$(echo "$BODY" | jq -r '.id')

# Verify created payment shows up in list
bold "  GET /payments (list after create)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/payments")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "list after create" "200" "$STATUS"
assert_json_field "count increased" "$BODY" '.data | length' "3"

# Get the newly created payment
bold "  GET /payments/$NEW_PAY_ID (get created)"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/payments/$NEW_PAY_ID")
STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')
assert_status "get created payment" "200" "$STATUS"
assert_json_field "created payment amount" "$BODY" '.amount' "4999"

echo ""

# ==========================================================================
bold "Results"
# ==========================================================================
TOTAL=$((PASS + FAIL))
echo ""
if [ "$FAIL" -eq 0 ]; then
  green "All $TOTAL assertions passed."
else
  red "$FAIL of $TOTAL assertions failed."
  exit 1
fi
