---
name: slipstream-inspector
description: >-
  This skill should be used when the user asks to "run the Flutter app",
  "flutter run", "start the app", "launch the app", "test the UI", "take a
  screenshot of the app", "click a button in the app", "debug the layout", or
  any request involving launching, observing, or interacting with a running
  Flutter app. When the flutter-slipstream plugin is installed, MCP tools
  replace terminal commands for all Flutter app interaction.
user-invocable: false
---

# flutter-slipstream

The flutter-slipstream plugin provides MCP tools for launching, observing, and
interacting with a running Flutter app. Use these tools — not terminal commands
— for all Flutter app work.

## Use the plugin tools, not the terminal

When working on a Flutter app with this plugin installed, always prefer the MCP
tools over shell commands:

| Instead of...        | Use...       |
| -------------------- | ------------ |
| `flutter run`        | `run_app`    |
| Hot reload (shell)   | `reload`     |
| Reading terminal log | `get_output` |

`run_app` does more than `flutter run`: it auto-selects the best available
device, exposes app output via `get_output`, and enables screenshot capture,
layout inspection, and UI interaction — none of which are possible from a plain
terminal session.

## Standard workflow

```
run_app → get_output → take_screenshot
  → edit source → reload → get_output → take_screenshot → repeat
```

- Call `get_output` after `run_app`, after `reload`, and after any interaction
  tool. It drains the output buffer — skipping it causes output to accumulate
  silently across calls.
- Call `take_screenshot` after every reload to confirm the change looked right.
  Never assume a visual edit was correct without seeing it.
- When `get_output` returns a `[flutter.error]` line, the widget ID in the
  summary can be passed directly to `inspect_layout`.

## Orienting on an unfamiliar screen

1. `take_screenshot` — see what's on screen.
2. `get_route` — see the navigator stack and current screen widget names with
   source file locations. Use before editing to confirm which file to change.
3. `get_semantics` — see the interactive elements and their node IDs.

## Interacting with the app

When `slipstream_agent` is installed in the Flutter app, prefer finder-based
tools — they are more reliable than semantics-based interaction:

- `perform_tap(byKey: ...)` / `perform_set_text(byKey: ...)` — most reliable;
  add `ValueKey('my_key')` to the widget while writing it.
- `perform_tap(byText: ...)` — good for button labels.
- `perform_tap(byType: ...)` — useful for unique widget types.

Fall back to `perform_semantic_action` (works without `slipstream_agent`) when
the target widget has no key and no distinctive text — e.g. a built-in
`IconButton`.

## Hot reload vs. hot restart

`reload` (hot reload) preserves app state and is fast, but cannot apply
structural changes: new routes, modified `initState`, changed widget keys, or
constructor signature changes. Use `reload(full_restart: true)` when state must
reset. Expect the app to return to its initial state.

## Gotchas

### `get_output` must be called explicitly

`get_output` is a pull operation — it drains the buffer and clears it. Call it
after every `run_app`, `reload`, and interaction tool, even when no output is
expected. Skipping it causes errors to accumulate and makes `[flutter.error]`
entries harder to correlate with their cause.

### Tooltip text is not a semantics label

Flutter's built-in widgets sometimes set a `Tooltip` (e.g. the Drawer hamburger
button gets "Open navigation menu") but that string does **not** appear as a
semantics label in `get_semantics` output. If a button shows no label, use its
numeric node ID with `perform_semantic_action`.

### Screenshot captures the Flutter view only

`take_screenshot` captures only the Flutter-rendered view. Native system UI
(permission dialogs, share sheets) does not appear. If a red `flutter.error`
chip is visible in the screenshot, call `get_output` to clear it before
retaking.

### Custom entrypoints (e.g. `flutter_driver`)

Pass the entrypoint as `run_app(target: "lib/main_driver.dart")`. In that file,
call `SlipstreamAgent.init()` before `enableFlutterDriverExtension()`, and pass
`enableTextEntryEmulation: false` so the real keyboard works. `evaluate` uses
the entrypoint library's imports.

## Debugging layout problems

- `inspect_layout` with no `widget_id` starts from the root.
- Widget IDs from `[flutter.error]` output can be passed directly — no tree
  traversal needed.
- Increase `subtree_depth` when the relevant widget is several levels down.
- `evaluate` is useful for exact runtime values (`MediaQuery.of(...)`,
  controller state) that don't appear in the layout tree.
