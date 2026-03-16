# Twilio API — Digital Twin

Import Twilio's official OpenAPI specification. Get 197 endpoints across 121 paths with realistic data. Define stateful tables so messages, calls, and phone numbers actually persist — all from a single config file.

```bash
curl -sL https://raw.githubusercontent.com/twilio/twilio-oai/main/spec/json/twilio_api_v2010.json -o twilio.json
mockd start -c mockd.yaml --no-auth
```

197 endpoints. 7 stateful tables. 32 extend bindings. Twilio-formatted responses. No Twilio account. No auth tokens. No internet.

## Stateful Tables: A Real Twilio That Remembers

The config file imports Twilio's spec for 197 schema-generated endpoints, then defines stateful tables with response transforms that match Twilio's actual API format — SID-style IDs, ISO 8601 timestamps, list envelopes with page-based pagination, and Twilio error format.

```bash
# Start mockd with the Twilio config (imports spec + defines tables + binds endpoints)
mockd start -c mockd.yaml --no-auth

# Send a message — it actually exists now
curl -s -X POST http://localhost:4280/2010-04-01/Accounts/AC_test/Messages.json \
  -d 'From=+15558675310&To=+15551234567&Body=Hello from mockd!'
# → {"sid":"SMa1b2c3d4...","body":"Hello from mockd!","status":"queued","date_created":"2026-03-09T14:30:00Z",...}

# List messages — Twilio list envelope format
curl -s http://localhost:4280/2010-04-01/Accounts/AC_test/Messages.json
# → {"messages":[{"sid":"SMa1b2c3d4...","body":"Hello from mockd!",...}],"page":0,"page_size":50,...}

# Make a call
curl -s -X POST http://localhost:4280/2010-04-01/Accounts/AC_test/Calls.json \
  -d 'From=+15558675310&To=+15551234567&Url=https://handler.twilio.com/twiml/mockd'
# → {"sid":"CAe5f6g7h8...","from":"+15558675310","to":"+15551234567","status":"queued",...}

# Get it by SID
curl -s http://localhost:4280/2010-04-01/Accounts/AC_test/Calls/CAe5f6g7h8.json

# Delete a message
curl -s -X DELETE http://localhost:4280/2010-04-01/Accounts/AC_test/Messages/SMa1b2c3d4.json

# Reset a table for the next test run
mockd stateful reset messages
mockd stateful reset calls
```

Twilio's test credentials are limited. Here's why mockd is better:

## Why mockd Beats Twilio's Test Credentials

| | Twilio Test Credentials | mockd |
|---|---|---|
| **Setup time** | Create account, verify phone, get SID + auth token | `mockd start -c mockd.yaml --no-auth` |
| **Internet** | Required for every request | Works offline |
| **Rate limits** | Concurrency limits apply | Unlimited |
| **Response latency** | 200-500ms (network round-trip) | <2ms (local) |
| **State reset** | Delete objects one by one | `mockd stateful reset messages` — instant |
| **Test phone numbers** | Only [magic numbers](https://www.twilio.com/docs/iam/test-credentials) work | Any phone number |
| **Supported resources** | Messages and calls only (test credentials) | All 197 endpoints from the spec |
| **Simulate outage** | Impossible | `mockd chaos apply offline` |
| **Simulate degradation** | Impossible | `mockd chaos apply slow-api` |
| **Simulate flaky network** | Impossible | `mockd chaos enable --error-rate 0.3` |
| **CI/CD** | Network dependency, credential secrets | Zero network, no secrets |
| **Reproducibility** | Shared test state | Fresh state per run, seeded data |
| **Cost** | Free (limited) | Free (unlimited) |

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

# 2. Download the Twilio OpenAPI spec
curl -sL https://raw.githubusercontent.com/twilio/twilio-oai/main/spec/json/twilio_api_v2010.json -o twilio.json

# 3. Start mockd with the config file (imports spec + defines tables + binds endpoints)
mockd start -c mockd.yaml --no-auth
```

## Config File Architecture

The `mockd.yaml` config file does everything in one place — no runtime commands needed:

```yaml
# mockd.yaml (simplified)
imports:
  - path: twilio.json    # Import the OpenAPI spec (197 endpoints)
    as: twilio

tables:
  - name: messages
    idField: sid
    idStrategy: prefix
    idPrefix: "SM"
    response:
      timestamps:
        format: iso8601
        fields: { createdAt: date_created, updatedAt: date_updated }
      fields:
        rename: { id: sid }
      list:
        dataField: messages
        extraFields: { page: 0, page_size: 50 }
        hideMeta: true

extend:
  - { mock: twilio.CreateMessage, table: messages, action: create }
  - { mock: twilio.ListMessage,   table: messages, action: list }
  - { mock: twilio.FetchMessage,  table: messages, action: get }
  - { mock: twilio.UpdateMessage, table: messages, action: patch }
  - { mock: twilio.DeleteMessage, table: messages, action: delete }
```

**imports** loads the OpenAPI spec. **tables** defines stateful data stores with Twilio-compatible response transforms. **extend** binds specific imported endpoints (by operationId) to table actions. The result is a Twilio-compatible API where CRUD operations persist and responses match the real Twilio format.

### Key differences from Stripe's format

| | Stripe | Twilio |
|---|---|---|
| **Base path** | `/v1/` | `/2010-04-01/Accounts/{AccountSid}/` |
| **IDs** | Short prefixed (`cus_a1b2c3`) | 34-char SIDs (`SM` + 32 hex chars) |
| **Timestamps** | Unix epoch integers | ISO 8601 strings (`date_created`) |
| **List envelope** | `{"object":"list","data":[...]}` | `{"messages":[...],"page":0,"page_size":50}` |
| **Pagination** | Cursor-based (`starting_after`) | Page-based (`page`, `page_size`) |
| **Auth** | Bearer token | HTTP Basic (SID + auth token) |
| **Error format** | `{"error":{"type":"...","message":"..."}}` | `{"code":20404,"message":"...","status":404}` |

## Chaos Testing: What Happens When Twilio Goes Down?

You can't test how your app handles a Twilio outage using Twilio's sandbox. You can with mockd.

```bash
# Twilio is slow today (200-800ms latency)
mockd chaos apply slow-api

# Twilio is flaky (30% of requests fail)
mockd chaos enable --error-rate 0.3

# Twilio is down (100% 503 errors)
mockd chaos apply offline

# Twilio rate-limits you (429 Too Many Requests)
mockd chaos apply rate-limited

# Back to normal
mockd chaos disable
```

Test your retry logic. Test your error handling. Test your fallback SMS providers. All without waiting for Twilio to actually have a bad day.

## SDK Integration

Point your Twilio SDK at `localhost:4280` instead of `api.twilio.com`:

### Go

```go
package main

import (
    "fmt"
    "github.com/twilio/twilio-go"
    twilioApi "github.com/twilio/twilio-go/rest/api/v2010"
)

func main() {
    client := twilio.NewRestClientWithParams(twilio.ClientParams{
        Username:   "AC_test",
        Password:   "mock_auth_token",
        AccountSid: "AC_test",
    })
    // Point at mockd instead of api.twilio.com
    client.SetEdge("localhost:4280")

    params := &twilioApi.CreateMessageParams{}
    params.SetFrom("+15558675310")
    params.SetTo("+15551234567")
    params.SetBody("Hello from mockd!")

    msg, _ := client.Api.CreateMessage(params)
    fmt.Println(*msg.Sid) // → "SM..."
}
```

### Node.js

```javascript
const twilio = require('twilio');

const client = twilio('AC_test', 'mock_auth_token', {
  edge: 'localhost',
  uri: 'http://localhost:4280',
});

const message = await client.messages.create({
  from: '+15558675310',
  to: '+15551234567',
  body: 'Hello from mockd!',
});
console.log(message.sid); // → "SM..."
```

### Python

```python
from twilio.rest import Client

client = Client('AC_test', 'mock_auth_token')
# Override the base URL
client._api.base_url = 'http://localhost:4280'

message = client.messages.create(
    from_='+15558675310',
    to='+15551234567',
    body='Hello from mockd!'
)
print(message.sid)  # → "SM..."
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

      - name: Download Twilio spec
        run: curl -sL https://raw.githubusercontent.com/twilio/twilio-oai/main/spec/json/twilio_api_v2010.json -o twilio.json

      - name: Start Twilio mock
        run: mockd start --no-auth -c mockd.yaml -d

      - name: Run tests
        run: npm test
        env:
          TWILIO_ACCOUNT_SID: AC_test
          TWILIO_AUTH_TOKEN: mock_auth_token
          TWILIO_API_BASE: http://localhost:4280

      - name: Verify API was called correctly
        run: |
          mockd verify check messages-create --at-least 1
          mockd verify check calls-create --at-least 1
```

Zero network dependencies. Deterministic. Fresh state per run.

## Stateful Resources

All 7 resources support full CRUD with Twilio-formatted responses:

| Resource | Table | SID Prefix | Actions | Seed Data |
|----------|-------|------------|---------|-----------|
| Messages | `messages` | `SM` | create, list, get, update, delete | 2 SMS messages |
| Calls | `calls` | `CA` | create, list, get, update, delete | 1 completed call |
| Accounts | `accounts` | `AC` | create, list, get, update | 1 test account |
| Incoming Phone Numbers | `incoming_phone_numbers` | `PN` | create, list, get, update, delete | 2 phone numbers |
| Recordings | `recordings` | `RE` | list, get, delete | 1 recording |
| Conferences | `conferences` | `CF` | list, get, update | 1 conference |
| Participants | `participants` | `CA` | create, list, get, update, delete | 1 participant |

All responses include:
- **SID-style IDs** — 2-letter prefix + 32 hex characters (e.g., `SM2a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d`)
- **ISO 8601 timestamps** — `date_created` and `date_updated` fields
- **Twilio list envelope** — `{"messages":[...],"page":0,"page_size":50,"uri":"..."}`
- **Twilio error format** — `{"code":20404,"message":"...","status":404,"more_info":"..."}`

13/13 twilio-go SDK tests pass against this mock.

## Running Tests

```bash
./test.sh
```

The test script verifies: config-based import, stateful CRUD with Twilio-formatted responses (create with SID-prefix IDs, list with Twilio page envelope, get by SID, Twilio error format on 404), chaos injection, and table reset. Run it after changes to catch regressions.

## Files

```
twilio-api/
├── README.md            ← You're here
├── setup.sh             ← Downloads spec + starts mockd with config
├── test.sh              ← Regression tests (run to verify everything works)
├── mockd.yaml           ← Curated config: 7 stateful tables with Twilio response transforms
├── twilio.json          ← Twilio's official OpenAPI spec (downloaded by setup.sh)
└── docker-compose.yml   ← Run everything in Docker
```

## Links

- [mockd](https://github.com/getmockd/mockd) — The mock server
- [docs.mockd.io](https://docs.mockd.io) — Documentation
- [Install mockd](https://get.mockd.io)
- [Twilio OpenAPI spec](https://github.com/twilio/twilio-oai)
