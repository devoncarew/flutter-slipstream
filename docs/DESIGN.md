# Design: Flutter Slipstream

> For agents working on this repo: why the plugin exists, how it's distributed,
> and the rationale for each tool. Read before adding or changing a tool.

## Problem Statement

AI coding agents working on Dart and Flutter projects face two structural
failure modes:

1. **Training cutoff drift.** Agents hallucinate outdated or discontinued
   package APIs. When they attempt to self-correct by reading raw source from
   `.pub-cache`, they consume large amounts of context window on implementation
   details rather than public API surface.

2. **No runtime visibility.** Static analysis alone is insufficient for Flutter
   development. Agents cannot observe layout failures, verify state changes, or
   diagnose render issues without being able to "see" the running app.

## Distribution

Shipped as a Claude Code plugin and a GitHub Copilot plugin. Each distribution
registers the same MCP servers and skills — the agent-facing tool surface is
identical across both.

Low-friction installation: no manual server setup or prompt engineering
required. Tools are automatically available via native primitives (Hooks, MCP)
without requiring explicit agent instruction.

## Tool 1: Package Safety Skill

**Mechanism:** An `add-package` skill that fires automatically when an agent is
about to add a Dart or Flutter package dependency (via `flutter pub add`,
`dart pub add`, or a direct `pubspec.yaml` edit).

**Behavior:** The skill instructs the agent to use `flutter pub add` (not direct
pubspec edits) so that pub output is always visible, then to read that output
carefully before proceeding:

- **Discontinued:** `(discontinued replaced by X)` in pub output → agent removes
  the package and adds the replacement instead.
- **Old major version:** `(X.Y.Z available)` on a direct dependency just added →
  agent runs `flutter pub outdated` to confirm the gap, then updates the
  constraint to the current major.
- Transitive dependency gaps are flagged as informational only.

**Rationale for skill over hooks:** Hooks required per-agent syntax variations
(different event names, field shapes, and shell-vs-JSON invocation across Claude
Code, Gemini CLI, and GitHub Copilot) and had inconsistent surfacing — some
agents showed the warning to the user but not the LLM, and
`permissionDecision: ask` was silently ignored in some tool contexts. The pub
command already outputs exactly the information the agent needs; the skill
teaches the agent to read and act on it, which gives richer corrective guidance
than a pre-add intercept.

## Tool 2: Package API Retrieval (packages MCP)

**Motivation:** Agents need accurate package API information, but their two
natural paths are both expensive:

- **Reading `.pub-cache` source directly** is token-inefficient — they read
  implementation files, private members, and method bodies, none of which are
  needed.
- **Relying on training-data summaries** produces subtly wrong results —
  incorrect parameter names, missing required vs. optional distinctions, wrong
  constructor shapes. Causes first-attempt failures and correction loops that
  consume more tokens than reading the source would have.

Observed during development: for `dart_mcp`, `flutter_daemon`, and
`unique_names_generator`, training-data summaries had meaningful errors each
time. Accurate signatures up front would have eliminated the correction step.

**Output format — Dart stubs:** Responses are `.d.ts` analogues for Dart: public
API with signatures only, no bodies, no private members. Preferred over Markdown
because:

- The agent is writing Dart; no translation step means fewer transcription
  errors. `Future<void> restart({bool? fullRestart, String? reason})` is
  unambiguous in a way that a prose description is not.
- Dart's type system captures nullability, required/optional, generics, and
  function types exactly. Markdown approximates them.
- Import lines appear as literal Dart imports — the exact lines the agent will
  write.

**Interaction model — progressive detail:**

| Tool              | Returns                                                             |
| ----------------- | ------------------------------------------------------------------- |
| `package_summary` | Version, import, README excerpt, library list, exported name groups |
| `library_stub`    | Full public API for one library as a Dart stub                      |
| `class_stub`      | Stub for a single named class, mixin, or extension                  |

Source: `.pub-cache` only — already downloaded, always matches `pubspec.lock`,
no network required.

**Limitation:** Does not cover string constants used as protocol/event
identifiers (e.g. `'app.started'` in the Flutter daemon protocol). These live in
implementation code, not the public API surface.

## Tool 3: Flutter UI Agent (inspector MCP)

A Playwright analogue for Flutter. Enables agents to observe and interact with a
running Flutter app for layout debugging, state verification, and workflow
validation.

Key design decisions:

- **Pull-based output:** `get_output` drains a server-side buffer rather than
  streaming. Agents call it explicitly after each operation. `_serverLog` is
  diagnostic-only and never agent-visible.
- **Device auto-selection:** `run_app` selects the best available device
  automatically — desktop first (fast builds, full inspector support), then
  simulator/emulator if already running, then physical device. Web is
  deprioritized. See `docs/inspector_design.md` for full logic.
- **Companion detection:** `ext.slipstream.ping` at session start. When the
  companion is present, tools route through in-process service extensions; when
  absent, they fall back to VM service evaluate strings. The fallback always
  works — companion presence is never required.

See `docs/inspector_design.md` for device selection logic, `get_route`
capabilities and limitations, and the go_router path enrichment implementation.

## Architecture

Tools 2 and 3 are separate Dart MCP servers (`packages` and `inspector`). Dart
is the natural fit for this domain and avoids introducing a Node.js runtime
dependency. Separate servers give independent lifecycles and failure modes: the
`packages` server is stateless; the `inspector` server is stateful and
subprocess-heavy.

## Open Questions

- **App state and authentication:** Navigating apps that require login or
  specific seeded data before reaching the UI under test is unsolved. A future
  design may define an `.agent_state.md` convention for specifying startup
  states, mock data, or auth bypasses.
