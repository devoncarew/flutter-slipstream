# Claude Code plugin info

> For agents working on this repo: Claude Code manifest quirks, distribution,
> and loading the plugin locally.

## Implementation specific files

- .claude-plugin/plugin.json

## MCP servers

Variable for the plugin root: `${CLAUDE_PLUGIN_ROOT}`

`command` must be the executable alone; arguments go in the `args` array.
Claude Code spawns `command` directly, so a shell-style string such as
`"dart run …/packages_mcp.dart"` fails to spawn.

Servers are launched from the user's project directory; `cwd` is ignored. Use
`dart pub -C <plugin-root> run`, not `dart run <abs-path>`: `dart run` only
resolves dependencies for the package in the current directory, so on a fresh
install (no `.dart_tool/`) it fails with "Couldn't resolve the package".

```json
"mcpServers": {
  "packages": {
    "command": "dart",
    "args": ["pub", "-C", "${CLAUDE_PLUGIN_ROOT}", "run", "bin/packages_mcp.dart"]
  }
}
```

`test/scripts/manifest_launch_test.dart` launches each server this way from a
fresh copy.

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
