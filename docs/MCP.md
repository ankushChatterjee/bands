# Local MCP bridge

`lanes-mcp` is a dependency-free MCP server that speaks newline-delimited
JSON-RPC 2.0 on stdin/stdout. It is intended to be configured as a local MCP
server in an MCP client:

```json
{
  "mcpServers": {
    "lanes": {
      "command": "/absolute/path/to/lanes-mcp"
    }
  }
}
```

The helper connects to the Unix-domain socket at
`~/Library/Application Support/lanes/mcp.sock`, or to the path in
`LANES_MCP_SOCKET`. The Lanes app bridge must create that socket, accept one
request per connection, and return one newline-terminated JSON object for each
request. The helper sends this backend envelope:

```json
{"jsonrpc":"2.0","id":1,"method":"lanes.command","params":{"name":"capture","arguments":{"text":"buy milk"}}}
```

The bridge must implement these command names and return a JSON-RPC `result`
containing JSON-serializable data (or a JSON-RPC `error`):

* `list_lanes`
* `list_thoughts`
* `search`
* `get`
* `capture`
* `update_thought`
* `complete_thought`
* `release_thought`
* `move_thought`

The bridge owns all SwiftData work and must run it on the app's main actor.
Suggested arguments are documented by the MCP `tools/list` response. The
helper itself never writes to the app store and never emits diagnostics on
stdout, preserving the MCP transport.

Lane objects returned by `list_lanes` and `list_thoughts` include `id`, `name`,
`description`, `order`, and `createdAt`. `description` is `null` for lanes
created before lane descriptions were added or for lanes without a description.
