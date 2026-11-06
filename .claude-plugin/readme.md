# Claude Code plugin info

> For agents working on this repo: Claude Code manifest quirks, distribution,
> and loading the plugin locally.

## Implementation specific files

- .claude-plugin/plugin.json

## MCP servers

Variable for the plugin root: `${CLAUDE_PLUGIN_ROOT}`

`command` must be the executable alone; arguments go in the `args` array.
Claude Code spawns `command` directly, so a shell-style string such as
`"dart run …/packages_mcp.dart"` fails to spawn. `cwd` is also supported and
should be set to `${CLAUDE_PLUGIN_ROOT}` so that `dart run` resolves the
pubspec correctly.

```json
"mcpServers": {
  "packages": {
    "command": "dart",
    "args": ["run", "${CLAUDE_PLUGIN_ROOT}/bin/packages_mcp.dart"],
    "cwd": "${CLAUDE_PLUGIN_ROOT}"
  }
}
```

## Distribution

Distribution is via the https://github.com/devoncarew/slipstream marketplace.

```
claude plugin marketplace add devoncarew/slipstream
claude plugin install flutter-slipstream@slipstream
```

## Running locally

Load the Claude Code plugin locally:

```
claude --plugin-dir /path/to/flutter-slipstream
```

Verify with `claude plugins list`.
