# Inspector MCP Tool Reference

> For agents working on this repo: the inspector MCP server's code layout and
> tool parameters. End-user agent guidance is in the `slipstream-inspector`
> skill.

Server entry point: `bin/inspector_mcp.dart`

Tools for launching, inspecting, and interacting with a running Flutter app.

## Code layout

Each tool is one class per file in `lib/src/inspector/tools/`, implementing the
`InspectorTool` abstract class (`lib/src/inspector/tool_context.dart`). The
server registers each tool in `lib/src/inspector/inspector_mcp.dart`.

## Session lifecycle

`run_app` starts a session; `close_app` ends it. Only one session is active at a
time — `run_app` stops any existing session first.

## Standard workflow

```
run_app → get_output → take_screenshot
  → edit source → reload → get_output → take_screenshot → repeat
```

Always call `get_output` after `run_app`, after `reload`, and after any
interaction tool — it drains the buffer. If a `[flutter.error]` line appears,
the widget ID in the summary can be passed to `inspect_layout`.

## `run_app(working_directory, [target, device, flavor])`

Builds and launches the Flutter app. Call `get_output` after to see startup
output.

- `working_directory` (required) — absolute path to the Flutter project.
- `target` — entry point (e.g. `lib/main.dart`). Defaults to project default.
- `device` — device ID override. Omit to auto-select (prefers desktop for fast
  builds, then iOS simulator, then Android emulator, then physical device).
- `flavor` — build flavor passed as `--flavor`. Required for projects whose
  Android or iOS targets define flavor schemes.

## `reload([full_restart])`

Applies source changes to the running app. Prefer hot reload; use
`full_restart: true` when state must reset (`initState` changes, new routes,
changed widget keys).

## `get_output()`

Returns buffered output since the last call and clears the buffer.

Output prefixes:

- `[app]` — `print()` / `debugPrint()` from the app
- `[stdout]` — other process stdout
- `[flutter.error]` — framework errors; widget IDs usable with `inspect_layout`
- `[route]` — navigation events (requires `slipstream_agent`)
- `[window]` — window resize events (requires `slipstream_agent`)

## `take_screenshot([pixel_ratio])`

Captures a PNG of the running app. Only the Flutter view is captured — native
system UI (share sheets, permission dialogs) will not appear. If a red
`flutter.error` chip is visible, call `get_output` to clear it.

## `inspect_layout([widget_id, subtree_depth])`

Returns constraints, size, flex parameters, and children for a widget. Omit
`widget_id` to start from root. Widget IDs appear in `[flutter.error]` output.
Increase `subtree_depth` to see deeper child layout.

## `evaluate(expression, [library_uri])`

Evaluates a Dart expression on the main isolate. Defaults to root library scope
(`main.dart`). Pass `library_uri` to evaluate in a different scope — e.g.
`"package:flutter/src/widgets/widget_inspector.dart"` for `RendererBinding`,
`SemanticsNode`, etc.

## `get_route()`

Returns the current navigator stack with screen widget names and source
locations. Enriched with the router path when `slipstream_agent` is installed.

## `navigate(path)`

Navigates to a route path via the registered router adapter. Requires
`slipstream_agent` with `SlipstreamAgent.init(router: ...)`. `path` must start
with `"/"`.

## `get_semantics()`

Returns a flat list of visible semantics nodes. Each node includes: role, ID,
state flags, supported actions, label, and position/size. Node IDs are stable
until the next hot reload or restart. Pass them to `perform_semantic_action`.

After a `navigate` or tap that triggers a route transition, call
`take_screenshot` first to synchronise on a rendered frame before calling
`get_semantics`.

## `perform_semantic_action(action, [node_id, label, value])`

Dispatches a semantics action by node ID or label. Works without
`slipstream_agent`. One of `node_id` or `label` must be provided; prefer
`node_id` (faster — skips tree fetch).

Common actions: `tap`, `setText` (requires `value`), `longPress`, `focus`,
`scrollUp`, `scrollDown`, `increase`, `decrease`.

## `perform_tap(finder, finder_value)`

Taps a widget by finder. Requires `slipstream_agent`.

Finders: `byKey`, `byType`, `byText`, `byTextContaining`, `bySemanticsLabel`.

## `perform_set_text(finder, finder_value, text)`

Sets text field content by finder. Replaces current content; fires `onChanged`.
`TextInputFormatter`s are not applied. Call `perform_tap` on the field first if
focus is required. Requires `slipstream_agent`.

## `perform_scroll(finder, finder_value, direction, pixels)`

Scrolls a Scrollable by fixed logical pixels. `direction`: `"up"` | `"down"` |
`"left"` | `"right"`. Clamped to scroll extent bounds. Requires
`slipstream_agent`.

## `perform_scroll_until_visible(finder, finder_value, scroll_finder, scroll_finder_value)`

Scrolls until the target widget is visible. On `ListView.builder` with many
items the target may not exist in the tree yet — use `perform_scroll` first to
bring the region into view, then use a finder-based tool. Requires
`slipstream_agent`.

## `close_app()`

Stops the running app and releases its session.

---

## `slipstream_agent` Companion Integration

Detected via `ext.slipstream.ping`. When present, the inspector server routes
tools through in-process service extensions instead of evaluate-based fallbacks.

| Extension                         | Used by MCP tool                                                                    |
| --------------------------------- | ----------------------------------------------------------------------------------- |
| `ext.slipstream.ping`             | Detection; also installs ghost overlay                                              |
| `ext.slipstream.perform_action`   | `perform_tap`, `perform_set_text`, `perform_scroll`, `perform_scroll_until_visible` |
| `ext.slipstream.navigate`         | `navigate`                                                                          |
| `ext.slipstream.get_route`        | `get_route`                                                                         |
| `ext.slipstream.get_semantics`    | `get_semantics` (screen-space coords)                                               |
| `ext.slipstream.enable_semantics` | Called before `get_semantics`                                                       |
| `ext.slipstream.overlays`         | Called before/after `take_screenshot`                                               |
| `ext.slipstream.log`              | Called for `reload`, `screenshot`, `evaluate`                                       |
| `ext.slipstream.clear_errors`     | Called after `get_output` drains errors                                             |

Typed wrappers for all companion calls live in
`lib/src/inspector/flutter_service_extensions.dart` (`slipstreamTap`,
`slipstreamSetText`, etc.). Never call `callSlipstreamExtension` directly from
tool code — always use the typed wrappers.
