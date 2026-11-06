# Documentation Index

Agent navigation guide. Each entry describes what the document covers and when
to read it.

## Architecture and Design

- @docs/DESIGN.md — System overview: problem statement, distribution (Claude
  Code / GitHub Copilot), and rationale for each of the three tools
  (package safety skill, packages MCP, inspector MCP). Read first for
  architectural context before adding or changing any tool.

- @docs/inspector_design.md — Inspector MCP implementation details: device
  auto-selection logic, `get_route` capabilities and limitations, go_router path
  enrichment via VM evaluate, and the `navigate` fallback chain. Read when
  working on `run_app`, `get_route`, or `navigate`.

- @docs/slipstream_agent.md — The optional companion package: registered service
  extensions, ghost overlay, detection via `ext.slipstream.ping`, and source
  file map. Read when working on companion detection or `ext.slipstream.*`
  service extensions.

## Inspector Protocol Reference

- @docs/flutter_inspection.md — Flutter runtime concepts: the four-tree model,
  VM service `evaluate` patterns, semantics interaction via
  `performSemanticsAction`, `SemanticsFlag` and `SemanticsAction` bitmask
  tables, and tree-walking filter criteria. Read when working on tools that
  touch the semantics tree or layout debugging.

- @docs/inspector_protocol.md — Inspector protocol specifics from DevTools
  source: full `ext.flutter.inspector.*` extension list, critical quirks
  (`groupName` vs `objectGroup`, boolean params as strings, `valueId` ≠ VM
  object ID), `DiagnosticsNode` JSON shape, `Flutter.Navigation` event handling,
  and VM service extension event list. Read when implementing or debugging
  inspector protocol calls.

## MCP Tool Reference

- @docs/packages_mcp.md — Packages MCP server tool reference: `package_summary`,
  `library_stub`, `class_stub`, call sequence, and parameter details. Read when
  working on or debugging the packages server.

- @docs/inspector_mcp.md — Inspector MCP server tool reference: session
  lifecycle, standard workflow, all tool parameters, and the `slipstream_agent`
  companion extension mapping. Read when working on or debugging the inspector
  server.

## Agent Guidance

- @skills/add-package/SKILL.md — Shipped skill for safely adding Dart/Flutter
  package dependencies: preferred `pub add` workflow, reading pub output for
  discontinued-package and outdated-version warnings, and corrective actions for
  each. Read when improving this guidance.

- @skills/slipstream-inspector/SKILL.md — Shipped skill: when to use `run_app`
  vs. terminal commands, recommended workflows, and non-obvious gotchas for
  agents using the inspector tools. Read when improving guidance shipped to
  end-user agents.

- @skills/slipstream-packages/SKILL.md — Shipped skill that instructs agents to
  use the packages MCP tools when writing code against an unfamiliar package or
  one that may be newer than training data. Read when improving this guidance.

## Other

- @privacy_policy.md — Plugin privacy policy.
- @docs/smoke-test.md — Human-facing prompt for smoke-testing the plugin end to
  end.
- @docs/study-setup.md — Human-facing setup script and prompt for user studies.
- @AGENTS.md — Used by agents working on this repo; not used by consumers of
  this plugin.
