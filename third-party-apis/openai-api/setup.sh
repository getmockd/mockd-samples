#!/usr/bin/env bash
set -euo pipefail

# Mock the OpenAI API — one script
# Requires: mockd installed (curl -fsSL https://get.mockd.io | sh)

# Check mockd is installed
if ! command -v mockd &>/dev/null; then
  echo "mockd not found. Install it:"
  echo "  curl -fsSL https://get.mockd.io | sh"
  exit 1
fi

# Download the spec if not present
if [ ! -f openai.yaml ]; then
  echo "Downloading OpenAI's OpenAPI spec..."
  curl -sL https://app.stainless.com/api/spec/documented/openai/openapi.documented.yml -o openai.yaml
  echo "Done ($(wc -l < openai.yaml) lines)"
fi

echo ""
echo "Starting mockd with OpenAI config..."
mockd start -c mockd.yaml --no-auth

echo ""
echo "OpenAI API is running at http://localhost:4280"
echo ""
echo "Try it:"
echo "  curl http://localhost:4280/models | jq"
echo '  curl -X POST http://localhost:4280/chat/completions \'
echo '    -H "Content-Type: application/json" \'
echo "    -d '{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}' | jq"
