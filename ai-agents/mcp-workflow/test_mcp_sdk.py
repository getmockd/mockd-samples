#!/usr/bin/env python3
"""Test the MCP workflow sample using the official MCP Python SDK.

Connects to mockd's MCP server over stdio, creates a Todo API
entirely through MCP tool calls, then validates it works.

Usage: python3 test_mcp_sdk.py
Requires: mcp Python package, mockd binary in PATH or at MOCKD_BIN
"""

import asyncio
import json
import os
import sys
import httpx
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

MOCKD_BIN = os.environ.get("MOCKD_BIN", "mockd")
PASS = 0
FAIL = 0


def passed(msg):
    global PASS
    PASS += 1
    print(f"  ✓ {msg}")


def failed(msg):
    global FAIL
    FAIL += 1
    print(f"  ✗ {msg}")


async def call_tool(session: ClientSession, name: str, args: dict) -> dict:
    """Call an MCP tool and return the parsed JSON result."""
    result = await session.call_tool(name, args)
    for content in result.content:
        if hasattr(content, "text"):
            try:
                return json.loads(content.text)
            except json.JSONDecodeError:
                return {"_text": content.text, "_is_error": result.isError}
    return {}


async def main():
    global PASS, FAIL

    server_params = StdioServerParameters(
        command=MOCKD_BIN,
        args=["mcp"],
        env={
            **os.environ,
            "MOCKD_ADMIN_URL": "http://localhost:5280",
            "MOCKD_PORT": "5280",
            "MOCKD_ADMIN_PORT": "5290",
        },
    )

    print("=== MCP SDK Integration Test ===\n")

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # List available tools
            tools = await session.list_tools()
            tool_names = [t.name for t in tools.tools]
            print(f"Connected. {len(tool_names)} tools available.")
            if "manage_mock" in tool_names:
                passed("manage_mock tool available")
            else:
                failed("manage_mock tool not found")
            if "manage_state" in tool_names:
                passed("manage_state tool available")
            else:
                failed("manage_state tool not found")

            # 1. Get server status
            print("\n--- Server Status ---")
            status = await call_tool(session, "get_server_status", {})
            if status.get("healthy") or status.get("status") == "ok":
                passed(
                    f"Server healthy (uptime: {status.get('uptime', '?')}s, mocks: {status.get('mockCount', '?')})"
                )
            else:
                failed(f"Server not healthy: {status}")

            # 2. Create stateful resource "todos"
            print("\n--- Create Stateful Resource ---")
            state_result = await call_tool(
                session,
                "manage_state",
                {
                    "action": "add_resource",
                    "resource": "todos",
                },
            )
            text = str(state_result.get("_text", state_result))
            if state_result.get("_is_error") and "already exists" not in text:
                failed(f"Failed to create resource: {text}")
            else:
                passed("Created 'todos' resource")

            # 3. Create CRUD mocks via manage_mock with extend
            print("\n--- Create CRUD Mocks ---")
            crud_ops = [
                ("GET", "/api/todos", "list"),
                ("POST", "/api/todos", "create"),
                ("GET", "/api/todos/{id}", "get"),
                ("PUT", "/api/todos/{id}", "update"),
                ("DELETE", "/api/todos/{id}", "delete"),
            ]
            for method, path, action in crud_ops:
                result = await call_tool(
                    session,
                    "manage_mock",
                    {
                        "action": "create",
                        "type": "http",
                        "http": {
                            "matcher": {"method": method, "path": path},
                        },
                        "extend": {"table": "todos", "action": action},
                    },
                )
                mock_id = result.get("id", result.get("mock", {}).get("id", "?"))
                if mock_id and mock_id != "?":
                    passed(f"{method} {path} → {action} (id: {mock_id})")
                else:
                    failed(f"{method} {path} → {action}: {result}")

            # 4. Verify with HTTP requests
            print("\n--- Verify CRUD via HTTP ---")
            # Use the port from status, not hardcoded
            mock_port = 4280  # default
            for p in status.get("ports", []):
                if p.get("component") == "Mock Engine":
                    mock_port = p["port"]
            base = f"http://localhost:{mock_port}"
            print(f"  Using {base}")
            async with httpx.AsyncClient() as http:
                # Create a todo
                resp = await http.post(
                    f"{base}/api/todos",
                    json={
                        "title": "MCP SDK test",
                        "completed": False,
                    },
                )
                if resp.status_code == 201:
                    todo = resp.json()
                    todo_id = todo.get("id")
                    passed(f"POST /api/todos → 201 (id: {todo_id})")
                else:
                    failed(f"POST /api/todos → {resp.status_code}")
                    todo_id = None

                # List todos
                resp = await http.get(f"{base}/api/todos")
                if resp.status_code == 200:
                    data = resp.json()
                    count = len(data.get("data", []))
                    passed(f"GET /api/todos → 200 ({count} items)")
                else:
                    failed(f"GET /api/todos → {resp.status_code}")

                if todo_id:
                    # Get by ID
                    resp = await http.get(f"{base}/api/todos/{todo_id}")
                    if resp.status_code == 200:
                        passed(f"GET /api/todos/{todo_id} → 200")
                    else:
                        failed(f"GET /api/todos/{todo_id} → {resp.status_code}")

                    # Update
                    resp = await http.put(
                        f"{base}/api/todos/{todo_id}",
                        json={
                            "title": "Updated via MCP SDK",
                            "completed": True,
                        },
                    )
                    if resp.status_code == 200:
                        updated = resp.json()
                        if updated.get("completed") is True:
                            passed("PUT update → completed=true")
                        else:
                            failed(f"PUT update → completed={updated.get('completed')}")
                    else:
                        failed(f"PUT → {resp.status_code}")

                    # Delete
                    resp = await http.delete(f"{base}/api/todos/{todo_id}")
                    if resp.status_code in (200, 204):
                        passed(f"DELETE → {resp.status_code}")
                    else:
                        failed(f"DELETE → {resp.status_code}")

            # 5. Verify invocations via MCP
            print("\n--- Verify Invocations ---")
            mocks = await call_tool(session, "manage_mock", {"action": "list"})
            mock_list = mocks.get("mocks", mocks) if isinstance(mocks, dict) else mocks
            if isinstance(mock_list, list) and len(mock_list) >= 5:
                passed(f"5+ mocks registered ({len(mock_list)} total)")
            else:
                failed(f"Expected 5+ mocks, got {len(mock_list)}")

    print(f"\n{'=' * 40}")
    print(f"Results: {PASS} passed, {FAIL} failed")
    if FAIL > 0:
        sys.exit(1)
    print("=== ALL MCP SDK TESTS PASSED ===")


if __name__ == "__main__":
    asyncio.run(main())
