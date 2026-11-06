# Codex plugin info

## Implementation specific files

- .codex-plugin/plugin.json
- .codex-plugin/mcp.json

## References

- https://developers.openai.com/codex/plugins/build

## MCP servers

Keep manifest paths relative to the plugin root and start them with ./.

MCP servers require `"type": "local"`. The `command` field must be the
executable name only (no shell expansion — spaces are not supported). Arguments
go in `args`.

```json
"mcpServers": {
  "packages": {
    "type": "local",
    "command": "dart",
    "args": ["run", "bin/packages_mcp.dart"]
  }
}
```

## Distribution

Distribution is via the https://github.com/devoncarew/slipstream marketplace.

TODO: `codex` doesn't seem to currently have a `plugin install` command.

```
codex plugin marketplace add devoncarew/slipstream
codex plugin install flutter-slipstream@slipstream
```

## Running locally

TODO:
