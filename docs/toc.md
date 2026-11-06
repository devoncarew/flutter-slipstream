# Documentation TOC

> For agents working on this repo: a map of the docs, what each covers, and
> when to read it. Open a doc only when the task needs it.

## Architecture

- [DESIGN.md](DESIGN.md) — why the plugin exists, how it's distributed, and the
  rationale for each tool. Read before adding or changing a tool.
- [inspector_design.md](inspector_design.md) — inspector internals: device
  auto-selection, `get_route` limits, go_router path enrichment, `navigate`
  fallbacks. Read when working on `run_app`, `get_route`, or `navigate`.
- [slipstream_agent.md](slipstream_agent.md) — the optional in-app companion
  package: service extensions, ghost overlay, detection. Read when working on
  `ext.slipstream.*` calls.

## MCP tool reference

- [inspector_mcp.md](inspector_mcp.md) — inspector server: code layout,
  session lifecycle, every tool's parameters.
- [packages_mcp.md](packages_mcp.md) — packages server: code layout,
  `package_summary` / `library_stub` / `class_stub` parameters.

## Flutter protocol reference

- [flutter_inspection.md](flutter_inspection.md) — Flutter's four trees, VM
  service `evaluate` patterns, semantics flag/action tables. Read when touching
  semantics or layout tools.
- [inspector_protocol.md](inspector_protocol.md) — `ext.flutter.inspector.*`
  extensions, parameter quirks, `DiagnosticsNode` shape. Read when implementing
  or debugging inspector protocol calls.

## Shipped skills (audience: end-user agents)

- [add-package](../skills/add-package/SKILL.md) — safe dependency adds via
  `pub add` output.
- [slipstream-inspector](../skills/slipstream-inspector/SKILL.md) — inspector
  workflows and gotchas.
- [slipstream-packages](../skills/slipstream-packages/SKILL.md) — when to use
  the packages tools.

## Clients and process

- [.claude-plugin/readme.md](../.claude-plugin/readme.md),
  [.github/plugin/readme.md](../.github/plugin/readme.md) — per-client manifest
  quirks, distribution, and local loading.
- [CONTRIBUTING.md](../CONTRIBUTING.md) — local dev, tests, release process.

## Human-facing

- [smoke-test.md](smoke-test.md) — end-to-end smoke-test prompt.
- [study-setup.md](study-setup.md) — user-study setup and prompt.
- [privacy_policy.md](../privacy_policy.md) — plugin privacy policy.
