# MCP Workflow: AI Agents Create Mocks via Tool Calls

No CLI commands. No config files. Just ask your AI agent to create a REST API, and mockd builds it through MCP tool calls.

This sample shows the MCP-first workflow: an AI agent creates a stateful todo API entirely through `manage_state` and `manage_mock` tool calls. The equivalent config file is included for reference.

## Setup

### 1. Install mockd

```bash
curl -fsSL https://get.mockd.io | sh
```

### 2. Start the MCP server

mockd's MCP server runs as a stdio transport — your AI editor launches it automatically. You just need to configure it.

### 3. Configure your editor

**Claude Desktop** (`~/.config/claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "mockd": {
      "command": "mockd",
      "args": ["mcp"]
    }
  }
}
```

**Cursor** (`.cursor/mcp.json` in your project root):

```json
{
  "mcpServers": {
    "mockd": {
      "command": "mockd",
      "args": ["mcp"]
    }
  }
}
```

**OpenCode** (`opencode.json` in your project root):

```json
{
  "mcpServers": {
    "mockd": {
      "command": "mockd",
      "args": ["mcp"]
    }
  }
}
```

After configuring, restart your editor. The mockd tools will appear in the agent's tool list.

### 4. Start mockd

The MCP server connects to a running mockd instance. Start one before chatting:

```bash
mockd start --no-auth
```

## Example Conversation

You say:

> Create a REST API for a todo app. I need full CRUD — list, create, get, update, delete. Seed it with a couple of sample todos.

The agent makes these tool calls:

### Step 1: Create the stateful resource

The agent calls `manage_state` to create a `todos` table with seed data:

```json
{
  "tool": "manage_state",
  "arguments": {
    "action": "add_resource",
    "resource": "todos",
    "seed_data": [
      { "id": "1", "title": "Buy groceries", "completed": false },
      { "id": "2", "title": "Write tests", "completed": true }
    ]
  }
}
```

> Created resource "todos" with 2 seed items.

### Step 2: Create the list endpoint

```json
{
  "tool": "manage_mock",
  "arguments": {
    "action": "create",
    "type": "http",
    "http": {
      "matcher": { "method": "GET", "path": "/api/todos" }
    },
    "extend": { "table": "todos", "action": "list" }
  }
}
```

> Created mock `http_...` — GET /api/todos (list from todos table)

### Step 3: Create the create endpoint

```json
{
  "tool": "manage_mock",
  "arguments": {
    "action": "create",
    "type": "http",
    "http": {
      "matcher": { "method": "POST", "path": "/api/todos" }
    },
    "extend": { "table": "todos", "action": "create" }
  }
}
```

> Created mock `http_...` — POST /api/todos (create in todos table)

### Step 4: Create the get endpoint

```json
{
  "tool": "manage_mock",
  "arguments": {
    "action": "create",
    "type": "http",
    "http": {
      "matcher": { "method": "GET", "path": "/api/todos/{id}" }
    },
    "extend": { "table": "todos", "action": "get" }
  }
}
```

> Created mock `http_...` — GET /api/todos/{id} (get from todos table)

### Step 5: Create the update endpoint

```json
{
  "tool": "manage_mock",
  "arguments": {
    "action": "create",
    "type": "http",
    "http": {
      "matcher": { "method": "PUT", "path": "/api/todos/{id}" }
    },
    "extend": { "table": "todos", "action": "update" }
  }
}
```

> Created mock `http_...` — PUT /api/todos/{id} (update in todos table)

### Step 6: Create the delete endpoint

```json
{
  "tool": "manage_mock",
  "arguments": {
    "action": "create",
    "type": "http",
    "http": {
      "matcher": { "method": "DELETE", "path": "/api/todos/{id}" }
    },
    "extend": { "table": "todos", "action": "delete" }
  }
}
```

> Created mock `http_...` — DELETE /api/todos/{id} (delete from todos table)

### Step 7: Verify it works

The agent can verify the setup by calling `get_server_status`:

```json
{
  "tool": "get_server_status",
  "arguments": {}
}
```

> Server healthy on :4280 (mock) / :4290 (admin). 5 mocks registered. 1 stateful resource (todos: 2 items).

## Try It

Once the agent finishes, the API is live:

```bash
# List todos (2 from seed data)
curl -s http://localhost:4280/api/todos | jq .

# Create a new todo
curl -s -X POST http://localhost:4280/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to production","completed":false}' | jq .

# Get it by ID (use the ID from the create response)
curl -s http://localhost:4280/api/todos/3 | jq .

# Update it — mark as completed
curl -s -X PUT http://localhost:4280/api/todos/3 \
  -H "Content-Type: application/json" \
  -d '{"title":"Deploy to production","completed":true}' | jq .

# Delete it
curl -s -X DELETE http://localhost:4280/api/todos/3

# List again — back to the 2 seed todos
curl -s http://localhost:4280/api/todos | jq .
```

## What Else Can the Agent Do?

The MCP workflow isn't limited to CRUD. The agent has 18 tools:

| Tool | What it does |
|------|--------------|
| `manage_mock` | Create, update, delete, list, toggle mocks |
| `manage_state` | Add resources, seed data, browse items, reset state |
| `manage_custom_operation` | Register domain logic (e.g., "mark todo as archived") |
| `import_mocks` | Import from OpenAPI, Postman, HAR, WireMock, cURL |
| `export_mocks` | Export current mocks as YAML/JSON |
| `get_server_status` | Health check, ports, statistics |
| `get_request_logs` | See all traffic hitting the mock server |
| `verify_mock` | Assert a mock was called N times |
| `set_chaos_config` | Inject latency, errors, apply chaos profiles |
| `manage_workspace` | Isolate mock configs in separate workspaces |

Example follow-ups you might ask:

- "Add pagination to the list endpoint"
- "Import my OpenAPI spec and wire up stateful tables"
- "Show me what requests hit the server in the last minute"
- "Inject 500ms latency on all POST requests"
- "Verify that GET /api/todos was called at least 3 times"

## Config File Equivalent

The `mockd.yaml` in this directory creates the exact same API via config file instead of MCP:

```bash
mockd start -c mockd.yaml --no-auth
```

Both approaches produce identical behavior — the MCP workflow is just more interactive.

## Running the Test

```bash
./test.sh
```

The test script starts mockd with the config file and exercises all CRUD operations.

## Files

```
mcp-workflow/
├── README.md       <- You're here
├── mockd.yaml      <- Config file equivalent of the MCP workflow
└── test.sh         <- CRUD regression tests
```

## Links

- [mockd](https://github.com/getmockd/mockd) — The mock server
- [docs.mockd.io](https://docs.mockd.io) — Documentation
- [Install mockd](https://get.mockd.io)
