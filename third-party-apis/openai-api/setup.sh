#!/usr/bin/env bash
set -euo pipefail

# Mock the OpenAI API — one script
# Requires: mockd installed (curl -fsSL https://get.mockd.io | sh)

echo "Downloading OpenAI's OpenAPI spec..."
curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml
echo "Done ($(wc -l < openai.yaml) lines)"

echo ""
echo "Starting mockd..."
mockd start 2>/dev/null || true
sleep 1

echo ""
echo "Importing OpenAI spec..."
mockd import openai.yaml

echo ""
echo "OpenAI API is running at http://localhost:4280"
echo ""
echo "Try it:"
echo '  curl -X POST http://localhost:4280/chat/completions \'
echo '    -H "Authorization: Bearer sk-fake" \'
echo '    -H "Content-Type: application/json" \'
echo "    -d '{\"model\":\"gpt-4\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo ""
echo "Note: Paths don't include /v1/ prefix (OpenAI's spec is relative to the server base URL)"
