# GitHub Copilot plugin info

> For agents working on this repo: Copilot manifest quirks, distribution, and
> loading the plugin locally.

## Implementation specific files

- .github/plugin/plugin.json

## MCP servers

Variable for the plugin root: `${PLUGIN_ROOT}`

MCP servers require `"type": "local"`. The `command` field must be the
executable name only (no shell expansion — spaces are not supported). Arguments
go in `args`, which is a required field for schema validation even when empty.

No `cwd` field is supported. For `dart run <absolute-path>`, this is fine
because Dart resolves the pubspec by walking up from the script file's location.

```json
"mcpServers": {
  "packages": {
    "type": "local",
    "command": "dart",
    "args": ["run", "${PLUGIN_ROOT}/bin/packages_mcp.dart"]
  }
}
```

## Distribution

Distribution is via the https://github.com/devoncarew/slipstream marketplace.

```
copilot plugin marketplace add devoncarew/slipstream
copilot plugin install flutter-slipstream@slipstream
```

## Running locally

Run:

```
copilot plugin install ./my-plugin
```

Then verify with `copilot plugin list`.

And uninstall with:

```
copilot plugin uninstall flutter-slipstream
```
