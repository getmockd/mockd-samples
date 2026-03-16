# Mock the Entire OpenAI API — From Their Own Spec

Import OpenAI's official OpenAPI specification. Get 237 mock endpoints. Stop burning credits during development.

```bash
# Download OpenAI's spec
curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml

# Import it into mockd
mockd import openai.yaml
# → Parsed 237 mocks (format: openapi)
# → Imported 237 mocks to server

# Use it
curl -X POST http://localhost:4280/chat/completions \
  -H "Authorization: Bearer sk-fake" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}]}'
```

No OpenAI account. No API key. No credit card. No internet.

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

### 2. Start and import

```bash
mockd start
curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml
mockd import openai.yaml
```

### 3. Use it like the real API

```bash
# Chat completions
curl -s -X POST http://localhost:4280/chat/completions \
  -H "Authorization: Bearer sk-fake" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}]}' | jq

# List models
curl -s http://localhost:4280/models \
  -H "Authorization: Bearer sk-fake" | jq

# Create embeddings
curl -s -X POST http://localhost:4280/embeddings \
  -H "Authorization: Bearer sk-fake" \
  -H "Content-Type: application/json" \
  -d '{"model":"text-embedding-3-small","input":"Hello world"}' | jq

# Image generation
curl -s -X POST http://localhost:4280/images/generations \
  -H "Authorization: Bearer sk-fake" \
  -H "Content-Type: application/json" \
  -d '{"model":"dall-e-3","prompt":"a cat","n":1}' | jq
```

> **Note:** OpenAI's spec defines paths relative to `https://api.openai.com/v1`, so imported paths don't include the `/v1/` prefix. Use `/chat/completions` not `/v1/chat/completions`.

## Use With Your SDK

Point your OpenAI SDK at mockd:

### Python

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-fake",
    base_url="http://localhost:4280",
)

response = client.chat.completions.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello"}],
)
print(response.choices[0].message.content)
```

### Node.js

```javascript
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: 'sk-fake',
  baseURL: 'http://localhost:4280',
});

const response = await openai.chat.completions.create({
  model: 'gpt-4',
  messages: [{ role: 'user', content: 'Hello' }],
});
console.log(response.choices[0].message.content);
```

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

## For SSE Streaming

The spec import gives you sync endpoints. For realistic token-by-token streaming, use the mockd-templates OpenAI template alongside the spec import:

```bash
# Import the spec for all endpoints
mockd import openai.yaml

# Add the streaming template for realistic SSE chat responses
curl -sL https://raw.githubusercontent.com/getmockd/mockd-templates/main/services/openai/chat-completions/template.yaml | mockd import
```

The template creates a higher-priority mock that handles `"stream": true` requests with Server-Sent Events, delivering tokens one at a time — just like the real API.

## Files in This Sample

```
openai-api/
├── README.md         ← You're here
├── setup.sh          ← Downloads spec + imports (one script)
└── docker-compose.yml ← Run the whole thing in Docker
```

## Links

- [mockd GitHub](https://github.com/getmockd/mockd)
- [mockd Documentation](https://docs.mockd.io)
- [Install mockd](https://get.mockd.io)
- [OpenAI OpenAPI spec](https://github.com/openai/openai-openapi)
