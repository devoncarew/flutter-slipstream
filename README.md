![Flutter Slipstream in action](docs/slipstream_banner.png)

# Flutter Slipstream

Flutter Slipstream is an agentic plugin that makes AI coding agents more
effective for Dart and Flutter projects. It enables live app introspection for
Flutter apps: screenshots, widget-tree inspection, tap/type/scroll interaction,
and error capture, as well as Dart package API summarization for agents.

This addresses two structural problems that agents face:

- a lack of runtime visibility into a running Flutter app — agents can't see
  screenshots, inspect the widget tree, or verify that a state change took
  effect
- training cutoffs that leads to stale package choices and subtly wrong API
  signatures

## Features

- **Live app inspection** — launch a Flutter app, take screenshots, inspect the
  widget tree, evaluate Dart expressions, and observe runtime errors, all from
  agent tool calls.
- **Tap, type, and scroll** — interact with the running app via semantics or
  widget finders; no test harness required.
- **Accurate package APIs** — retrieve any package's public API directly from
  the local pub cache as a compact Dart stub, version-matched and free of
  implementation noise.
- **Package safety guidance** — the bundled skill instructs agents to read pub
  command output for discontinued packages and outdated major versions, and take
  corrective action before bad dependencies land.

## Installation

| Coding Agent   | Installing Slipstream                                                                                              |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| Claude Code \* | `claude plugin marketplace add devoncarew/slipstream` <br> `claude plugin install flutter-slipstream@slipstream`   |
| GitHub Copilot | `copilot plugin marketplace add devoncarew/slipstream` <br> `copilot plugin install flutter-slipstream@slipstream` |

> [!NOTE]
>
> If you see a "Failed to install plugin ... No ED25519 host key is known for
> github.com ... Host key verification failed" error, see
> anthropics/claude-code/issues/26588 / anthropics/claude-code/issues/50725 for
> possible workarounds.

## Getting Started / Using Slipstream

Install the plugin, then work on Flutter projects as you normally would. No
special prompting is required — Slipstream works in the background.

**UI development workflow:** When building or debugging UI, ask the agent to run
the app. It will launch on a desktop device automatically, then iterate using
hot reload after each source edit. Because the agent can take screenshots and
inspect the widget tree, it catches overflow errors, layout surprises, and
rendering regressions on its own — without you having to describe what went
wrong.

**Package hygiene:** When an agent adds a package, the bundled skill guides it
to read `flutter pub add` output for discontinued-package and outdated-version
warnings, and to take corrective action (switching to the replacement package,
or updating the version constraint) before the bad dependency lands.

**Optional: richer instrumentation.** Add
[`package:slipstream_agent`](https://pub.dev/packages/slipstream_agent) as a
dependency for finder-based interactions (tap by key, type, or text), scroll
support, and router-aware navigation. Without it, Slipstream still works well
via semantics and the Flutter inspector protocol.

## Tools

### Flutter UI agent (`inspector`)

MCP commands for launching, inspecting, and interacting with a running Flutter
app. Gives agents a [Playwright](https://playwright.dev/)-style interface to the
running app: take screenshots, inspect the widget tree, evaluate arbitrary Dart
expressions, and observe runtime errors with widget IDs.

<!-- inspector -->
<!-- prettier-ignore-start -->
| Command | Description |
|---------|-------------|
| `run_app` | Builds and launches the Flutter app. |
| `reload` | Applies source file changes to a running Flutter app. |
| `get_output` | Returns buffered app output and runtime events since the last call (or the last reload/restart). |
| `take_screenshot` | Captures a PNG screenshot of the running Flutter app. |
| `inspect_layout` | Use when debugging layout issues, overflow errors, or unexpected widget sizing. |
| `evaluate` | Evaluates a Dart expression on the running app's main isolate and returns the result as a string. |
| `get_route` | Returns the current navigator route stack with screen widget names and source locations. |
| `navigate` | Navigates the app to a route path. |
| `perform_tap` | Taps a widget located by a finder. |
| `perform_set_text` | Sets the text content of a text field located by a finder. |
| `perform_scroll` | Scrolls a Scrollable widget by a fixed number of logical pixels. |
| `perform_scroll_until_visible` | Scrolls a Scrollable until a target widget is visible in the viewport. |
| `get_semantics` | Returns a flat list of visible semantics nodes from the running Flutter app. |
| `perform_semantic_action` | Dispatches a semantics action on a widget by semantics node ID or label. |
| `close_app` | Stops the running Flutter app and releases its session. |
<!-- prettier-ignore-end -->
<!-- inspector -->

### Package API retrieval (`packages`)

Retrieves a package's public API surface directly from the local pub cache and
returns it as a compact Dart stub — signatures only, no bodies, no private
members. Agents get accurate, version-matched API information without reading
raw source files or relying on training-data summaries.

<!-- packages -->
<!-- prettier-ignore-start -->
| Command | Description |
|---------|-------------|
| `package_summary` | Returns API summaries for Dart or Flutter packages; start here to orient on an unfamiliar package. |
| `library_stub` | Returns the full public API for one library as a Dart stub (signatures only, no bodies). |
| `class_stub` | Returns the public API for a single named class, mixin, or extension as a Dart stub (signatures only, no bodies). |
<!-- prettier-ignore-end -->
<!-- packages -->

### Package safety skill

The `add-package` skill fires automatically when an agent is about to add a Dart
or Flutter package dependency. It instructs the agent to:

- Use `flutter pub add` rather than editing `pubspec.yaml` directly, so pub
  output is always visible.
- Read `pub add` output for `(discontinued replaced by X)` annotations and
  switch to the replacement package.
- Read `pub add` output for `(X.Y.Z available)` annotations on newly added
  direct dependencies, and run `flutter pub outdated` to confirm a major-version
  gap before proceeding.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
