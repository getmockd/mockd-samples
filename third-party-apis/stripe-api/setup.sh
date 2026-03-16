#!/usr/bin/env bash
set -euo pipefail

# Mock the Stripe API — one script
# Requires: mockd installed (curl -fsSL https://get.mockd.io | sh)

MOCKD_BIN="${MOCKD_BIN:-mockd}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Stripe API Mock Setup ==="
echo ""

# The spec is committed in the repo. If missing, download it.
if [ ! -f "$SCRIPT_DIR/stripe.yaml" ]; then
  echo "1. Downloading Stripe's OpenAPI spec..."
  curl -sL https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml -o "$SCRIPT_DIR/stripe.yaml"
  echo "   Done ($(wc -l < "$SCRIPT_DIR/stripe.yaml") lines)"
else
  echo "1. Stripe OpenAPI spec found (stripe.yaml)"
fi

echo ""
echo "2. Starting mockd with Stripe config..."
$MOCKD_BIN start --no-auth -c "$SCRIPT_DIR/mockd.yaml" -d 2>/dev/null
sleep 2

echo ""
echo "=== Stripe API is running at http://localhost:4280 ==="
echo ""
echo "Schema-generated endpoints: 587 (from Stripe's OpenAPI spec)"
echo "Stateful tables:            customers, payment_intents, subscriptions,"
echo "                            products, prices, invoices, refunds, disputes"
echo ""
echo "Try it:"
echo ""
echo "  # List customers (empty initially)"
echo "  curl -s http://localhost:4280/v1/customers | jq"
echo '  # → {"object":"list","data":[],"has_more":false,"url":"/v1/customers"}'
echo ""
echo "  # Create a customer (it persists!)"
echo '  curl -s -X POST http://localhost:4280/v1/customers \'
echo '    -H "Content-Type: application/json" \'
echo "    -d '{\"name\":\"Alice\",\"email\":\"alice@example.com\"}' | jq"
echo '  # → {"id":"cus_...","object":"customer","name":"Alice",...}'
echo ""
echo "  # List again (Alice is there)"
echo "  curl -s http://localhost:4280/v1/customers | jq"
echo '  # → {"object":"list","data":[{"id":"cus_...","object":"customer",...}],...}'
echo ""
echo "  # Get balance (schema-generated response)"
echo "  curl -s http://localhost:4280/v1/balance | jq"
echo ""
echo "Chaos testing:"
echo "  mockd chaos apply flaky     # 30% error rate"
echo "  mockd chaos apply slow-api  # 200-800ms latency"
echo "  mockd chaos apply offline   # 100% 503 errors"
echo "  mockd chaos disable         # back to normal"
echo ""
echo "Reset state:"
echo "  mockd stateful reset customers"
echo "  mockd stateful reset payment_intents"
