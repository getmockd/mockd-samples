# Mock the Entire OpenAI API — From Their Own Spec

Import OpenAI's official OpenAPI specification. Get 237 mock endpoints with stateful models, assistants, and threads. Stop burning credits during development.

```bash
# Download OpenAI's spec
curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml

# Start mockd with the config
mockd start -c mockd.yaml --no-auth

# Use it
curl http://localhost:4280/models | jq
```

No OpenAI account. No API key. No credit card. No internet.

## What You Get

- **237 endpoints** auto-generated from OpenAI's OpenAPI spec (chat completions, embeddings, images, audio, fine-tuning, etc.)
- **Stateful models table** seeded with gpt-4o, gpt-4o-mini, gpt-3.5-turbo
- **Stateful assistants** with full CRUD (create, list, get, update, delete)
- **Stateful threads** with full CRUD

## Why This Is Better Than OpenAI's API

| | OpenAI API | mockd |
|---|---|---|
| **Cost** | $0.01-0.06 per 1K tokens | Free |
| **Rate limits** | Tier-based, can be restrictive | None |
| **Internet required** | Yes | No |
| **Latency** | 500ms-5s (model inference) | <2ms |
| **Deterministic** | No (temperature, sampling) | Seeded responses |
| **Test error handling** | Wait for real errors | `mockd chaos apply flaky` |
| **Test rate limiting** | Hit the limit | `mockd chaos apply rate-limited` |
| **Test timeouts** | Hope for slow response | `mockd chaos apply timeout` |
| **CI-friendly** | Network + billing dependency | Zero dependencies |
| **Runs offline** | No | Yes |

## Quick Start

### 1. Install mockd

```bash
curl -fsSL https://get.mockd.io | sh
```

### 2. Download the spec and start

```bash
curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml
mockd start -c mockd.yaml --no-auth
```

### 3. Use it like the real API

```bash
# List models (stateful — returns seeded gpt-4o, gpt-4o-mini, gpt-3.5-turbo)
curl -s http://localhost:4280/models | jq

# Get a specific model
curl -s http://localhost:4280/models/gpt-4o | jq

# Chat completions (spec-generated response)
curl -s -X POST http://localhost:4280/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"Hello"}]}' | jq

# Create an assistant (stateful — persisted in memory)
curl -s -X POST http://localhost:4280/assistants \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","name":"My Assistant","instructions":"You are helpful."}' | jq

# List assistants
curl -s http://localhost:4280/assistants | jq

# Create a thread
curl -s -X POST http://localhost:4280/threads \
  -H "Content-Type: application/json" \
  -d '{}' | jq

# Create embeddings (spec-generated response)
curl -s -X POST http://localhost:4280/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Hello world"}' | jq
```

> **Note:** OpenAI's spec defines paths relative to `https://api.openai.com/v1`, so imported paths don't include the `/v1/` prefix. Set `base_url="http://localhost:4280"` (no `/v1` suffix) — the SDK appends API paths automatically. Validated with the official `openai` Python SDK.

## Use With Your SDK

Point your OpenAI SDK at mockd:

### Python

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-fake",
    base_url="http://localhost:4280",
)

# Chat completions
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello"}],
)
print(response.choices[0].message.content)

# List models (returns seeded data)
models = client.models.list()
for model in models:
    print(model.id)
```

### Node.js

```javascript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: 'sk-fake',
  baseURL: 'http://localhost:4280',
});

// Chat completions
const response = await openai.chat.completions.create({
  model: 'gpt-4o',
  messages: [{ role: 'user', content: 'Hello' }],
});
console.log(response.choices[0].message.content);

// List models (returns seeded data)
const models = await openai.models.list();
for await (const model of models) {
  console.log(model.id);
}
```

## Docker

```bash
docker compose up
```

The config file is mounted into the container. The spec is downloaded at build time if not already present locally.

## Test AI App Resilience

What happens when OpenAI is slow? Returns errors? Rate limits you?

```bash
# Simulate slow model inference
mockd chaos apply slow-api

# Simulate intermittent failures
mockd chaos enable --error-rate 0.2

# Simulate rate limiting (429 responses)
mockd chaos apply rate-limited

# Simulate complete outage
mockd chaos apply offline

# Back to normal
mockd chaos disable
```

## Files in This Sample

```
openai-api/
├── README.md           ← You're here
├── mockd.yaml          ← Config: imports spec, defines tables + extend bindings
├── openai.yaml         ← OpenAI's OpenAPI spec (downloaded)
├── setup.sh            ← Downloads spec + starts mockd
├── test.sh             ← Regression tests
└── docker-compose.yml  ← Run the whole thing in Docker
```

## Links

- [mockd GitHub](https://github.com/getmockd/mockd)
- [mockd Documentation](https://docs.mockd.io)
- [Install mockd](https://get.mockd.io)
- [OpenAI OpenAPI spec](https://github.com/openai/openai-openapi)
