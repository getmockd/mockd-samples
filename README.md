# mockd Samples

Real-world examples of [mockd](https://github.com/getmockd/mockd)'s digital twin and API mocking capabilities.

## Available Samples

### Digital Twins (Third-Party APIs)

| Sample | Description | Stateful | Endpoints | SDK Tested |
|--------|-------------|----------|-----------|------------|
| [Stripe API](third-party-apis/stripe-api/) | Full Stripe payment API digital twin | 9 tables, 46 bindings, 8 custom ops | 587 | stripe-go 49/49 |
| [Twilio API](third-party-apis/twilio-api/) | Twilio REST API v2010 digital twin | 7 tables, 32 bindings | 197 | twilio-go 13/13 |
| [OpenAI API](third-party-apis/openai-api/) | OpenAI API with stateful models + assistants | 3 tables, 11 bindings | 237 | openai Python SDK |

### Use Case Samples

| Sample | Description | What it shows |
|--------|-------------|---------------|
| [MCP Workflow](ai-agents/mcp-workflow/) | Build a Todo API with AI tool calls | Create mocks via MCP — zero CLI commands |
| [GitHub Actions](ci-testing/github-actions/) | Contract testing in CI | `setup-mockd` action + `mockd verify` |
| [Docker Compose](microservices/docker-compose/) | Mock dependent microservices | User + Payment service mocks for local dev |

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
