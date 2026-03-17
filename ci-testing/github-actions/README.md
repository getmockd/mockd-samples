# GitHub Actions CI — Contract Testing with mockd

Run your API contract tests in CI with zero network dependencies. This sample shows how to use the [`getmockd/setup-mockd`](https://github.com/getmockd/setup-mockd) GitHub Action to spin up a stateful mock server and verify your tests actually exercise every endpoint.

```yaml
- uses: getmockd/setup-mockd@v1
  with:
    start: true
    config: mockd.yaml
```

No external API keys. No flaky network calls. Deterministic on every run.

## Quick Start

```bash
# Run locally (same as CI)
mockd start -c mockd.yaml --no-auth -d
bash test.sh
```

## How It Works

### 1. The `setup-mockd` Action

The [`getmockd/setup-mockd@v1`](https://github.com/getmockd/setup-mockd) action installs the mockd CLI and optionally starts the server in one step:

```yaml
- uses: getmockd/setup-mockd@v1
  with:
    start: true          # Start the server in daemon mode
    config: mockd.yaml   # Path to your config file
    args: "--no-auth"    # Additional CLI flags
```

| Input | Default | Description |
|-------|---------|-------------|
| `version` | `latest` | mockd version to install |
| `start` | `false` | Start the server after install |
| `config` | — | Config file path (required if `start: true`) |
| `args` | — | Extra flags passed to `mockd start` |

If you set `start: false` (the default), you get just the CLI — useful when you need to start multiple instances on different ports.

### 2. Complete Workflow

```yaml
name: API Tests
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  contract-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Install mockd and start with our config
      - uses: getmockd/setup-mockd@v1
        with:
          start: true
          config: mockd.yaml
          args: "--no-auth"

      # Wait for the mock to be ready
      - name: Wait for mockd
        run: |
          for i in $(seq 1 30); do
            if curl -sf http://localhost:4290/health > /dev/null 2>&1; then
              echo "mockd is ready"
              break
            fi
            echo "Waiting for mockd... ($i/30)"
            sleep 1
          done

      # Run your tests against the mock
      - name: Run contract tests
        run: bash test.sh

      # Verify your tests actually called the right endpoints
      - name: Verify mock invocations
        run: |
          mockd verify check orders-create --at-least 1
          mockd verify check orders-list --at-least 1
          mockd verify check payments-create --at-least 1
```

### 3. Contract Verification

The `mockd verify check` command asserts that endpoints were called a minimum number of times. This is what makes it a **contract test** — you're not just testing that the mock works, you're testing that your code exercises every endpoint it's supposed to.

```bash
# Passes if orders-create was called at least once
mockd verify check orders-create --at-least 1

# Passes if orders-list was called at least 2 times
mockd verify check orders-list --at-least 2

# Fails the CI step if the endpoint was never called
mockd verify check payments-create --at-least 1
```

If a developer removes an API call from the codebase, the verification step catches it before merge.

## The Sample Config

The `mockd.yaml` defines a fictional **Payment Service** with two stateful tables:

| Table | ID Prefix | Endpoints | Seed Data |
|-------|-----------|-----------|-----------|
| `orders` | `ord_` | POST, GET, GET/:id, PUT/:id, DELETE/:id | 2 orders |
| `payments` | `pay_` | POST, GET, GET/:id | 2 payments |

Response transforms:
- **Prefixed IDs** — `ord_a1b2c3`, `pay_d4e5f6`
- **ISO 8601 timestamps** — `created_at`, `updated_at`
- **Type field** — `"type": "order"` / `"type": "payment"`
- **List envelope** — `{"orders": [...], "total_count": 3}`

## Multi-Service Integration Testing

When your application talks to multiple APIs, start a separate mockd instance for each:

```yaml
jobs:
  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: getmockd/setup-mockd@v1

      # Payment service on port 4280
      - name: Start payment service mock
        run: mockd start --no-auth -c payment-mockd.yaml --port 4280 --admin-port 4290 -d

      # Inventory service on port 4281
      - name: Start inventory service mock
        run: mockd start --no-auth -c inventory-mockd.yaml --port 4281 --admin-port 4291 -d

      # Wait for both
      - name: Wait for services
        run: |
          for port in 4290 4291; do
            for i in $(seq 1 30); do
              if curl -sf "http://localhost:$port/health" > /dev/null 2>&1; then
                echo "Service on admin port $port ready"
                break
              fi
              sleep 1
            done
          done

      - name: Run integration tests
        run: npm test
        env:
          PAYMENT_API_URL: http://localhost:4280
          INVENTORY_API_URL: http://localhost:4281
```

Each mock gets its own port, its own admin port, and its own state. Tests are fully isolated.

## The Test Script

`test.sh` runs through a contract test workflow:

1. **Health check** — waits for mockd to be ready (retry loop)
2. **Create an order** — POST, verify response shape (id prefix, type field, timestamp)
3. **Get order** — verify it persists
4. **Create a payment** — POST, verify it links to the order
5. **List orders** — verify count and envelope format
6. **List payments** — verify count
7. **Error handling** — 404 for nonexistent resource
8. **Verify invocations** — `mockd verify check` for contract coverage

Any failure exits with code 1, which fails the GitHub Actions step.

## Files

```
github-actions/
├── README.md                         <- You're here
├── mockd.yaml                        <- Payment Service config (2 tables, seed data)
├── test.sh                           <- Contract test script
└── .github/
    └── workflows/
        └── test.yml                  <- GitHub Actions workflow
```

## Links

- [mockd](https://github.com/getmockd/mockd) — The mock server
- [getmockd/setup-mockd](https://github.com/getmockd/setup-mockd) — GitHub Action
- [docs.mockd.io](https://docs.mockd.io) — Documentation
- [Install mockd](https://get.mockd.io)
