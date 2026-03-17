# Microservices with Docker Compose

Mock dependent services during local development with mockd.

## The Problem

You're developing an **Order Service** that calls two internal APIs you don't own:

```
                         ┌──────────────────┐
                    ┌───>│   User Service    │  (team Alpha owns this)
┌──────────────┐   │    │   GET /users/:id  │
│              │   │    └──────────────────┘
│ Order Service│───┤
│  (yours)     │   │    ┌──────────────────┐
│              │   └───>│ Payment Service   │  (team Bravo owns this)
└──────────────┘        │ POST /payments    │
                        └──────────────────┘
```

Running locally is painful:
- Those services are deployed to a shared staging env that's slow and flaky
- You can't create test data without side effects
- You can't test edge cases (what if Payment Service returns 500?)
- You block on other teams when their services are down

## The Solution

Replace both dependencies with **mockd** — a single container that serves stateful mocks for both services:

```
                         ┌──────────────────────────────────┐
                         │            mockd                  │
┌──────────────┐         │                                  │
│              │────────>│  /users      ← users table       │
│ Order Service│         │  /users/:id                      │
│  (yours)     │────────>│  /payments   ← payments table    │
│              │         │  /payments/:id                   │
└──────────────┘         │                                  │
                         │  Seed data loaded on startup     │
                         │  POST creates → GET retrieves    │
                         └──────────────────────────────────┘
```

Both services run on the same mockd instance (port 4280). Tables provide stateful behavior — `POST /users` creates a user that `GET /users/:id` can retrieve.

## Quick Start

```bash
# Start mockd
docker compose up -d

# Verify endpoints
./test.sh

# Or test manually
curl http://localhost:4280/users
curl http://localhost:4280/payments/pay_1
```

## Files

| File | Purpose |
|------|---------|
| `mockd.yaml` | Mock definitions — 2 tables, 10 endpoints, seed data |
| `docker-compose.yml` | Runs mockd + your service |
| `test.sh` | Validates all endpoints work |

## What's in the Mock

### User Service (5 endpoints)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/users` | List all users |
| `GET` | `/users/{id}` | Get user by ID |
| `POST` | `/users` | Create a user |
| `PATCH` | `/users/{id}` | Update a user |
| `DELETE` | `/users/{id}` | Delete a user |

### Payment Service (5 endpoints)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/payments` | List all payments |
| `GET` | `/payments/{id}` | Get payment by ID |
| `POST` | `/payments` | Create a payment |
| `PATCH` | `/payments/{id}` | Update a payment |
| `DELETE` | `/payments/{id}` | Delete a payment |

### Seed Data

The mock starts with realistic data pre-loaded:

**Users:**
| ID | Name | Plan |
|----|------|------|
| `usr_1` | Alice Johnson | pro |
| `usr_2` | Bob Smith | free |
| `usr_3` | Carol Lee | pro |

**Payments:**
| ID | User | Amount | Status |
|----|------|--------|--------|
| `pay_1` | usr_1 | $29.99 | completed |
| `pay_2` | usr_2 | $9.99 | pending |
| `pay_3` | usr_1 | $29.99 | completed |

## Connecting Your Service

Uncomment the `your-service` block in `docker-compose.yml` and point your service's env vars at mockd:

```yaml
services:
  your-service:
    build: .
    environment:
      USER_SERVICE_URL: http://mockd:4280
      PAYMENT_SERVICE_URL: http://mockd:4280
    depends_on:
      mockd:
        condition: service_healthy
```

Your service code doesn't change — it calls the same paths (`/users`, `/payments`), just against mockd instead of the real services.

## Adding More Endpoints

As you discover new API calls your service needs, add them to `mockd.yaml`:

1. **Add a mock** in the `mocks:` section with a matcher
2. **Add an extend binding** to wire it to a table

For example, to add `PUT /users/{id}`:

```yaml
mocks:
  # ... existing mocks ...
  - id: replace-user
    type: http
    http:
      matcher:
        method: PUT
        path: /users/{id}

extend:
  # ... existing bindings ...
  - { mock: "PUT /users/{id}", table: users, action: update }
```

Restart mockd and the new endpoint is live.

## Without Docker

You can run mockd directly if you have it installed:

```bash
mockd start -c mockd.yaml --no-auth
```

The mock server runs on `localhost:4280`, admin API on `localhost:4290`.

## Requirements

- Docker and Docker Compose (for containerized usage)
- mockd v0.6.0+ (for local usage)
- curl and jq (for `test.sh`)
