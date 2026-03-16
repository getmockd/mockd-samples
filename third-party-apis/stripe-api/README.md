# Mock the Entire Stripe API — From Their Own Spec

Import Stripe's official OpenAPI specification. Get 587 endpoints with realistic data. Define stateful tables so customers, payment intents, and subscriptions actually persist — all from a single config file.

```bash
curl -sL https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml -o stripe.yaml
mockd start -c mockd.yaml
```

587 endpoints. 8 stateful tables. Stripe-formatted responses. No Stripe account. No API keys. No internet.

## Stateful Tables: A Real Stripe That Remembers

The config file imports Stripe's spec for 587 schema-generated endpoints, then defines stateful tables with response transforms that match Stripe's actual API format — prefixed IDs, `object` type fields, list envelopes, unix timestamps, and Stripe error format.

```bash
# Start mockd with the Stripe config (imports spec + defines tables + binds endpoints)
mockd start -c mockd.yaml

# Create a customer — it actually exists now
curl -s -X POST http://localhost:4280/v1/customers \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice Johnson","email":"alice@example.com","metadata":{"plan":"pro"}}'
# → {"id":"cus_a1b2c3d4","object":"customer","name":"Alice Johnson","email":"alice@example.com","created":1709856000,...}

# List customers — Stripe list envelope format
curl -s http://localhost:4280/v1/customers
# → {"object":"list","data":[{"id":"cus_a1b2c3d4","object":"customer","name":"Alice Johnson",...}],"has_more":false,"url":"/v1/customers"}

# Create a payment intent for Alice
curl -s -X POST http://localhost:4280/v1/payment_intents \
  -H "Content-Type: application/json" \
  -d '{"amount":2000,"currency":"usd","customer":"cus_a1b2c3d4"}'
# → {"id":"pi_e5f6g7h8","object":"payment_intent","amount":2000,"currency":"usd",...}

# Get it by ID
curl -s http://localhost:4280/v1/payment_intents/pi_e5f6g7h8

# Update it (POST, not PUT — matches Stripe convention)
curl -s -X POST http://localhost:4280/v1/payment_intents/pi_e5f6g7h8 \
  -H "Content-Type: application/json" \
  -d '{"status":"succeeded"}'

# Delete the customer — returns Stripe deletion object
curl -s -X DELETE http://localhost:4280/v1/customers/cus_a1b2c3d4
# → {"id":"cus_a1b2c3d4","object":"customer","deleted":true}

# List again — empty
curl -s http://localhost:4280/v1/customers
# → {"object":"list","data":[],"has_more":false,"url":"/v1/customers"}

# Reset a table for the next test run
mockd stateful reset customers
mockd stateful reset payment_intents
```

Stripe's test mode is stateful too. Here's why mockd is still better:

## Why mockd Beats Stripe's Test Mode

| | Stripe Test Mode | mockd |
|---|---|---|
| **Setup time** | Create account, verify email, get API keys | `mockd start -c mockd.yaml` |
| **Internet** | Required for every request | Works offline |
| **Rate limits** | 25 requests/sec in test mode | Unlimited |
| **Response latency** | 200-500ms (network round-trip) | <2ms (local) |
| **State reset** | Delete objects one by one, or create new test account | `mockd stateful reset customers` — instant |
| **Simulate outage** | Impossible | `mockd chaos apply offline` |
| **Simulate degradation** | Impossible | `mockd chaos apply slow-api` |
| **Simulate flaky network** | Impossible | `mockd chaos enable --error-rate 0.3` |
| **Webhook testing** | Stripe CLI + forwarding, seconds of latency | Local, instant delivery |
| **CI/CD** | Network dependency, API key secrets | Zero network, no secrets |
| **Reproducibility** | Shared test state across team | Fresh state per run, seeded responses |
| **Edge cases** | Limited to Stripe's test card numbers | Mock any response you want |
| **Cost** | Free (rate-limited) | Free (unlimited) |
| **Coverage** | Only endpoints that support test mode | All 587 endpoints from the spec |

## Quick Start

### Option A: One script

```bash
curl -fsSL https://get.mockd.io | sh   # Install mockd (if you haven't)
./setup.sh                               # Downloads spec, starts server
```

### Option B: Docker

```bash
docker compose up
```

### Option C: Step by step

```bash
# 1. Install
curl -fsSL https://get.mockd.io | sh

# 2. Download the Stripe OpenAPI spec
curl -sL https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml -o stripe.yaml

# 3. Start mockd with the config file (imports spec + defines tables + binds endpoints)
mockd start -c mockd.yaml
```

## Config File Architecture

The `mockd.yaml` config file does everything in one place — no runtime commands needed:

```yaml
# mockd.yaml (simplified)
imports:
  - path: stripe.yaml    # Import the OpenAPI spec (587 endpoints)
    as: stripe

tables:
  - name: customers
    idPrefix: "cus_"
    response:
      fields:
        inject: { object: customer }
      list:
        dataField: data
        extraFields: { object: list, has_more: false }
      delete:
        body: { id: "{{item.id}}", object: customer, deleted: true }

extend:
  - { mock: stripe.PostCustomers,          table: customers, action: create }
  - { mock: stripe.GetCustomers,           table: customers, action: list }
  - { mock: stripe.GetCustomersCustomer,   table: customers, action: get }
  - { mock: stripe.PostCustomersCustomer,  table: customers, action: patch }
  - { mock: stripe.DeleteCustomersCustomer, table: customers, action: delete }
```

**imports** loads the OpenAPI spec. **tables** defines stateful data stores with response transforms. **extend** binds specific imported endpoints (by operationId) to table actions. The result is a Stripe-compatible API where CRUD operations persist and responses match the real Stripe format.

## Chaos Testing: What Happens When Stripe Goes Down?

This is where the real value shows up. You can't test how your app handles a Stripe outage using Stripe's sandbox. You can with mockd.

```bash
# Stripe is slow today (200-800ms latency)
mockd chaos apply slow-api

# Stripe is flaky (30% of requests fail)
mockd chaos enable --error-rate 0.3

# Stripe is down (100% 503 errors)
mockd chaos apply offline

# Stripe rate-limits you (429 Too Many Requests)
mockd chaos apply rate-limited

# Back to normal
mockd chaos disable
```

Test your retry logic. Test your error handling. Test your circuit breakers. Test your graceful degradation. All without waiting for Stripe to actually have a bad day.

## SDK Integration

Point your Stripe SDK at `localhost:4280` instead of `api.stripe.com`:

### Python

```python
import stripe

stripe.api_key = "sk_test_fake"
stripe.api_base = "http://localhost:4280"

# Create a customer — it persists (tables are configured in mockd.yaml)
customer = stripe.Customer.create(name="Alice", email="alice@example.com")
print(customer.id)  # → "cus_..."

# List customers — Alice is there
customers = stripe.Customer.list()
assert len(customers.data) > 0

# Create a payment intent
intent = stripe.PaymentIntent.create(amount=2000, currency="usd")
print(intent.id)  # → "pi_..."
```

### Node.js

```javascript
const Stripe = require('stripe');
const stripe = Stripe('sk_test_fake', {
  host: 'localhost',
  port: 4280,
  protocol: 'http',
});

const customer = await stripe.customers.create({
  name: 'Alice',
  email: 'alice@example.com',
});
console.log(customer.id); // → "cus_..."

const intent = await stripe.paymentIntents.create({
  amount: 2000,
  currency: 'usd',
});
console.log(intent.id); // → "pi_..."
```

### Go

```go
stripe.Key = "sk_test_fake"

config := &stripe.BackendConfig{
    URL: stripe.String("http://localhost:4280"),
}
stripe.SetBackend(stripe.APIBackend, config)
```

## CI Integration

```yaml
# .github/workflows/test.yml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: getmockd/setup-mockd@v1

      - name: Download Stripe spec
        run: curl -sL https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.yaml -o stripe.yaml

      - name: Start Stripe mock
        run: mockd start --no-auth -c mockd.yaml -d

      - name: Run tests
        run: npm test
        env:
          STRIPE_API_KEY: sk_test_fake
          STRIPE_API_BASE: http://localhost:4280

      - name: Verify API was called correctly
        run: |
          mockd verify check customers-list --at-least 1
          mockd verify check customers-create --at-least 1
```

Zero network dependencies. Deterministic. Fresh state per run.

## What's in the Box

After starting with the config, you get mock endpoints for:

| Category | Endpoints | Examples |
|----------|-----------|---------|
| **Customers** | CRUD + search | `/v1/customers`, `/v1/customers/{id}` |
| **Payments** | Intents, methods, confirmations | `/v1/payment_intents`, `/v1/payment_methods` |
| **Subscriptions** | Create, update, cancel | `/v1/subscriptions`, `/v1/subscription_items` |
| **Invoices** | Create, finalize, pay, void | `/v1/invoices`, `/v1/invoiceitems` |
| **Products** | Catalog management | `/v1/products`, `/v1/prices` |
| **Checkout** | Session management | `/v1/checkout/sessions` |
| **Billing** | Meters, credits, alerts | `/v1/billing/meters`, `/v1/billing/credit_grants` |
| **Connect** | Account management | `/v1/accounts`, `/v1/account_links` |
| **Disputes** | Dispute handling | `/v1/disputes` |
| **Refunds** | Refund processing | `/v1/refunds` |
| **Balance** | Account balance | `/v1/balance`, `/v1/balance_transactions` |
| **+500 more** | Full Stripe API surface | Every path in their OpenAPI spec |

## Running Tests

```bash
./test.sh
```

The test script verifies: config-based import, stateful CRUD with Stripe-formatted responses (create with `cus_` prefix IDs, list with `object:list` envelope, update via POST, delete with `deleted:true` body, 404 with Stripe error format), chaos injection, and table reset. Run it after changes to catch regressions.

## Files

```
stripe-api/
├── README.md            ← You're here
├── setup.sh             ← Downloads spec + starts mockd with config
├── test.sh              ← Regression tests (run to verify everything works)
├── mockd.yaml           ← Curated config: 8 stateful tables with Stripe response transforms
├── mockd-full.yaml      ← Full digital twin: 178 tables, 543 extend bindings (all Stripe resources)
└── docker-compose.yml   ← Run everything in Docker
```

## Links

- [mockd](https://github.com/getmockd/mockd) — The mock server
- [docs.mockd.io](https://docs.mockd.io) — Documentation
- [Install mockd](https://get.mockd.io)
- [Stripe OpenAPI spec](https://github.com/stripe/openapi)
