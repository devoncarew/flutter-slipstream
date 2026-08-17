## 1.6.1-wip

- Fixed `run_app` failing on Windows with "The system cannot find the file
  specified". The inspector now spawns `flutter.bat` on Windows instead of a
  bare `flutter`, which `CreateProcess` cannot resolve (#127).

## 1.6.0

- Added support for Cursor (note: not yet in cursor.com/marketplace /
  cursor.directory).
- Replaced the per-agent package validation hooks with a single `add-package`
  skill. The skill fires when an agent is about to add a Dart or Flutter package
  and instructs it to read `flutter pub add` output for discontinued-package and
  outdated-version warnings. Equivalent guidance is embedded in the Gemini CLI
  context file. This eliminates the per-agent hook infrastructure (different
  event names, field shapes, and invocation styles across Claude Code, Gemini
  CLI, and GitHub Copilot) and the external pub.dev network calls at hook time.
- Added a `slipstream-packages` skill that instructs the agent to use the
  packages MCP tools when writing code against an unfamiliar pub package or one
  whose version may be newer than its training data.
- Renamed the 'flutter-slipstream' skill to 'slipstream-inspector'.
- Updated the privacy policy to note that we no longer make calls to
  https://pub.dev for package metadata.
- Removed the Bash MCP entrypoint scripts in favor of calling the Dart MCP
  entrypoints directly.

## 1.5.0

- Added GitHub Copilot support (including both MCP servers and the package
  validation hooks).
- Added installation instructions for GitHub Copilot.
- Updated the installation instructions for Claude Code.
- Added a skill - 'flutter-slipstream' - to help the agent know when to use the
  MCP servers, to document recommended workflows, and to make agents aware of
  common gotchas when inspecting Flutter apps.

## 1.4.0

- Updated for `package:slipstream_agent` 1.2.0:
  - `get_output` now calls `ext.slipstream.clear_errors` after draining output
    that contains `[flutter.error]` lines, dismissing the error banner once the
    agent has acknowledged the errors.
  - Added `byTextContaining` finder support to `perform_tap`,
    `perform_set_text`, `perform_scroll`, and `perform_scroll_until_visible`.
    Matches any `Text` widget whose content contains the given value as a
    substring — useful when displayed text is truncated (e.g. `"Lorem ipsum..."`
    vs the full string).
  - `take_screenshot` tool description now explains the `flutter.error: <msg>`
    chip that appears when a Flutter framework error has been caught, and
    directs the agent to call `get_output` to read the full error.

## 1.3.1

- Disabled Gemini `BeforeTool` hooks for now: Claude Code rejects unknown keys
  in `hooks/hooks.json` at startup, and there is no way to declare hooks inside
  `gemini-extension.json` yet. Tracking in
  [gemini-cli#25630](https://github.com/google-gemini/gemini-cli/issues/25630).

## 1.3.0

- Fixed a race condition where app output emitted during startup was dropped;
  `run_app` now returns buffered output (build messages, initial route)
  alongside the launch result, and failure results include any output captured
  before the error. Session cleanup on process exit is now driven by the process
  `exitCode` future rather than the stdout `onDone` callback.
- Updated the plugin and extension descriptions.
- Updated the plugin and extension installation instructions.
- Added Gemini CLI hook support (`hooks/hooks.json`,
  `scripts/deps_check_gemini.sh`): the same package-currency checks (pub-add and
  pubspec-guard modes) now run as Gemini `BeforeTool` hooks.
- Updated the Claude code hooks to return more granular information to the agent
  (`'permissionDecision': 'ask'`).

## 1.2.0

- Addressed an issue where a 'restart' message could appear in the app under
  test at startup (and not just after a hot restart).
- Added `get_output` tool: returns buffered app stdout, Flutter errors, and
  route changes since the last call (or the last reload/restart), then clears
  the buffer. Replaces push-based MCP log notifications, which are not forwarded
  to agent context in Claude Code or Gemini CLI.

## 1.1.0

### `slipstream_agent` companion integration improvements

When `package:slipstream_agent` is installed in the target app, inspector tools
now report their activity to the companion's ghost overlay:

- `take_screenshot` suppresses the Flutter debug banner before capture and
  restores it afterward (via `ext.slipstream.overlays`)
- `reload` and hot restart log the operation with elapsed time
- `evaluate`, `inspect_layout`, and `perform_semantic_action` log their
  invocations with relevant context (expression snippet, widget ID, action
  target)
- Hot restart timing is handled correctly: the log fires after the companion
  re-registers its extensions post-restart

## 1.0.0

Initial public release.

### Package currency hook

- Warns when an agent adds a discontinued package (with official replacement if
  one is listed)
- Warns when a constraint targets an older major version than the current
  pub.dev release
- Warns when a package name is not found on pub.dev
- Fires on `flutter pub add` / `dart pub add` and on direct `pubspec.yaml` edits
- Always exits 0 — advisory only, never hard-blocks

### `packages` MCP server

- `package_summary` — version, entry-point import, README excerpt, public
  library list, and exported name groups
- `library_stub` — full public API for one library as a Dart stub file
  (signatures only, no bodies)
- `class_stub` — stub for a single named class, mixin, or extension

### `inspector` MCP server

- `run_app` — builds and launches a Flutter app; auto-selects the best available
  device (desktop > simulator > emulator > physical > web)
- `reload` — hot reload or hot restart
- `take_screenshot` — PNG screenshot via the inspector protocol
- `inspect_layout` — widget layout tree (subtree depth configurable)
- `evaluate` — arbitrary Dart expression on the main isolate
- `get_route` — navigator stack with screen widget names and source locations
- `navigate` — route navigation via registered router adapter (requires
  `slipstream_agent` companion)
- `get_semantics` — flat list of visible semantics nodes with role, ID, state,
  actions, label, and position
- `perform_semantic_action` — semantics action (tap, longPress, setText, …) by
  node ID or label
- `perform_tap` — finder-based tap (byKey/byType/byText/bySemanticsLabel);
  requires `slipstream_agent` companion
- `perform_set_text` — finder-based text field input; requires companion
- `perform_scroll` — scroll a Scrollable by fixed logical pixels; requires
  companion
- `perform_scroll_until_visible` — scroll until a target widget is in the
  viewport; requires companion
- `close_app` — stops the running app

### `slipstream_agent` companion integration

When `package:slipstream_agent` is installed in the target app, the inspector
server detects it via `ext.slipstream.ping` and activates enhanced mode:

- Finder-based widget interaction (byKey, byType, byText, bySemanticsLabel)
- Router-adapter navigation (GoRouter and others)
- Semantics nodes with accurate screen-space coordinates
- `[window]` log messages on resize
- `[route]` log messages on navigation
