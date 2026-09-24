# Local MCP bridge

`bands-mcp` is a dependency-free MCP server that speaks newline-delimited
JSON-RPC 2.0 on stdin/stdout. It is intended to be configured as a local MCP
server in an MCP client:

```json
{
  "mcpServers": {
    "bands": {
      "command": "/absolute/path/to/bands-mcp"
    }
  }
}
```

The helper connects to the Unix-domain socket at
`~/Library/Application Support/bands/mcp.sock`, or to the path in
`BANDS_MCP_SOCKET`. The Bands app bridge must create that socket, accept one
request per connection, and return one newline-terminated JSON object for each
request. The helper sends this backend envelope:

```json
{"jsonrpc":"2.0","id":1,"method":"bands.command","params":{"name":"capture","arguments":{"text":"buy milk"}}}
```

The bridge must implement these command names and return a JSON-RPC `result`
containing JSON-serializable data (or a JSON-RPC `error`):

* `list_bands`
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

## Secure tokens

User-supplied service tokens are stored locally with the app's
`LocalTokenStore`, using namespaced keys such as `bands:jev_key`. The store
writes `~/Library/Application Support/bands/tokens.json` atomically with mode
`0600`; its parent directory has mode `0700`. It deliberately does not use
macOS Keychain. This is appropriate for low-risk tokens: it protects against
other macOS users and accidental disclosure, but not software running as the
current user. FileVault should be enabled. Existing Keychain tokens are not
migrated, so users enter their token once after upgrading.

Band objects returned by `list_bands` and `list_thoughts` include `id`, `name`,
`description`, `order`, and `createdAt`. `description` is `null` for bands
created before band descriptions were added or for bands without a description.
