# flutter-slipstream

- an agentic tooling plugin to make coding agents more effective for Dart and
  Flutter projects
- docs table of contents at @docs/toc.md; open individual docs as needed
- user facing docs at `README.md`

## Feature: Flutter UI agent

- `inspector` MCP server for launching, inspecting, and interacting with a
  running Flutter app
- take screenshots, inspect the widget tree, evaluate arbitrary Dart
  expressions, and observe runtime errors with widget IDs
- implementation reference at `docs/inspector_mcp.md`
- 'slipstream-inspector' skill at `skills/slipstream-inspector/SKILL.md` used to
  help agents trigger on 'flutter run' and document workflows and gotchas
- has an optional in-process companion package, slipstream_agent;
  `docs/slipstream_agent.md`

## Feature: Package API retrieval

- `packages` MCP server returns package APIs as token efficient stubs
- call `package_summary`to orient on a package and `library_stub` and
  `class_stub` for details
- related 'slipstream-packages' skill at `skills/slipstream-packages/SKILL.md`
- implementation reference at `docs/packages_mcp.md`

## Feature: Package safety skill

- `add-package` skill at `skills/add-package/SKILL.md`
- fires when an agent is about to add a Dart or Flutter package dependency
- prevents adding a dependency on discontinued packages
- prevents adding a dependency on outdated versions (older major versions)

## Supported Coding Agents

- Claude Code implementation notes at `.claude-plugin/readme.md`
- GitHub Copilot implementation notes at `.github/plugin/readme.md`

## Development

- `dart analyze` for linting
- `dart test` for unit tests
- `dart format .` before committing
- new or changed docs: keep `docs/toc.md` current, and start each doc with a
  one- or two-line "what is this, who is it for" summary
