# mockd Samples

Real-world examples of [mockd](https://github.com/getmockd/mockd)'s digital twin and API mocking capabilities.

## Available Samples

| Sample | Description | Stateful | Endpoints | SDK Tested |
|--------|-------------|----------|-----------|------------|
| [Stripe API](third-party-apis/stripe-api/) | Full Stripe payment API digital twin | 9 tables, 46 bindings, 8 custom ops | 587 | stripe-go 49/49 |
| [Twilio API](third-party-apis/twilio-api/) | Twilio REST API v2010 digital twin | 7 tables, 32 bindings | 197 | twilio-go 13/13 |
| [OpenAI API](third-party-apis/openai-api/) | OpenAI API mock from official spec | — | 237 | — |

## Quick Start

Every sample follows the same pattern:

```bash
cd third-party-apis/stripe-api
mockd start -c mockd.yaml --no-auth
```

Or with Docker:

```bash
docker compose up
```

The mock server runs on `localhost:4280` by default.

## Digital Twin Architecture

The Stripe and Twilio samples are **digital twins** — stateful mocks that behave like the real API:

- **Tables** define in-memory resource collections (customers, invoices, messages, etc.)
- **Extend bindings** wire HTTP endpoints to CRUD operations on those tables
- **Custom operations** handle domain logic (e.g., paying an invoice, sending a message)
- **Imports** split large configs into composable files

This means `POST /v1/customers` actually creates a customer that `GET /v1/customers/:id` can retrieve — no scripting required.

## Requirements

- mockd v0.6.0+

## Links

- [mockd](https://github.com/getmockd/mockd) — Core engine
- [docs.mockd.io](https://docs.mockd.io) — Documentation
- [mockd-templates](https://github.com/getmockd/mockd-templates) — Reusable mock configs
