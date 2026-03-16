# mockd Samples

Real-world examples of [mockd](https://github.com/getmockd/mockd) solving real problems. Each sample is self-contained — clone, run, done.

## Third-Party APIs

Mock real APIs from their actual OpenAPI specs. No accounts, no API keys, no internet.

| Sample | What You Get | Setup |
|--------|-------------|-------|
| [**Stripe API**](third-party-apis/stripe-api/) | 587 endpoints from Stripe's spec. Better than their sandbox. | `./setup.sh` |
| [**OpenAI API**](third-party-apis/openai-api/) | Chat completions with SSE streaming. Stop burning credits. | `./setup.sh` |

## CI Testing

Run integration tests without hitting real APIs.

| Sample | What You Get | Setup |
|--------|-------------|-------|
| [**GitHub Actions**](ci-testing/github-actions/) | mockd as a CI service. Contract testing with OpenAPI. | Copy workflow |

## Microservices

Mock the services you don't own. Work on the one you do.

| Sample | What You Get | Setup |
|--------|-------------|-------|
| [**Docker Compose**](microservices/docker-compose/) | 3 services, mock the ones that aren't yours. | `docker compose up` |

## AI Agents

AI agents that create their own test environments.

| Sample | What You Get | Setup |
|--------|-------------|-------|
| [**MCP Workflow**](ai-agents/mcp-workflow/) | Claude/Cursor creates mocks via MCP. Zero CLI commands. | Add to MCP config |

---

## Quick Start

Every sample has the same pattern:

```bash
# 1. Install mockd
curl -fsSL https://get.mockd.io | sh

# 2. Pick a sample
cd third-party-apis/stripe-api

# 3. Run it
./setup.sh
# or
docker compose up
```

## Links

- [mockd](https://github.com/getmockd/mockd) — The mock server
- [docs.mockd.io](https://docs.mockd.io) — Documentation
- [mockd-templates](https://github.com/getmockd/mockd-templates) — Reusable mock configs
