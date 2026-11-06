# slipstream_agent Companion Package

An optional Flutter dependency that upgrades the Slipstream MCP server from
external observation (VM service + evaluate strings) to in-process cooperation
(typed service extensions running inside the app).

## Design Principles

- **Zero-config baseline.** All inspector tools work without this package. The
  companion unlocks enhanced capabilities; it never hard-requires it.
- **Opt-in.** The MCP server must not add this package to `pubspec.yaml` without
  explicit developer consent.
- **Debug-only.** All registration is guarded by `kDebugMode`. The package is
  declared as a regular `dependency:` (not `dev_dependencies:`) because it is
  imported from `lib/` code, but `SlipstreamAgent.init()` is a no-op in release
  builds.

## Installation

```yaml
dependencies:
  slipstream_agent: ^1.0.0
```

```dart
// main.dart
import 'package:flutter/foundation.dart';
import 'package:slipstream_agent/slipstream_agent.dart';

void main() {
  if (kDebugMode) {
    SlipstreamAgent.init(
      router: GoRouterAdapter(appRouter),  // optional
    );
  }
  runApp(const MyApp());
}
```

`SlipstreamAgent.init()` registers all service extensions and starts telemetry.
The `router` parameter is optional; omit it if the app doesn't use go_router or
doesn't need `navigate` / `get_route`.

### Custom entrypoints

If the app is launched through its own `flutter_driver` entrypoint — for
example a local-only `lib/main_driver.dart` used for screenshots and widget
dumps — initialize the agent first, then install the driver extension before
any other binding:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:slipstream_agent/slipstream_agent.dart';

import 'main.dart' as app;

void main() {
  SlipstreamAgent.init();
  // Flutter Driver's text-entry emulation installs a mock IME, so TextFields
  // focus but the system keyboard never opens. Disable it to drive the real
  // app; perform_set_text still works because it writes through the controller.
  enableFlutterDriverExtension(enableTextEntryEmulation: false);
  app.main();
}
```

`enableTextEntryEmulation: false` makes `FlutterDriver.enterText` fail, but
Slipstream's `perform_set_text` writes through the controller and does not
depend on it. `SlipstreamAgent.init()` registers VM service extensions and does
not initialize a binding, so `enableFlutterDriverExtension()` can still install
its own.

Import `package:flutter/material.dart` (or `package:flutter/widgets.dart`) in
the entrypoint even if no code there names it: `evaluate` defaults to the root
library, and the screenshot probe evaluates
`WidgetsBinding.instance.platformDispatcher…` in that scope.

Keep this entrypoint local and out of release builds.

## Companion Detection

The MCP server calls `ext.slipstream.ping` when connecting to the VM service:

- **Ping fails** (method not found): baseline mode — all tools use VM service
  evaluate strings.
- **Ping succeeds**: enhanced mode — tools route through `ext.slipstream.*`
  extensions for better accuracy and ghost overlay visibility.

`ping` also installs the ghost overlay (disables Flutter debug banner, shows
Slipstream command log) as a side effect.

## Registered Service Extensions

| Extension                         | Description                                                     |
| --------------------------------- | --------------------------------------------------------------- |
| `ext.slipstream.ping`             | Checks agent status; installs ghost overlay. Returns `version`. |
| `ext.slipstream.get_route`        | Returns `path` from the registered router adapter.              |
| `ext.slipstream.navigate`         | Navigates to `path` via the router adapter.                     |
| `ext.slipstream.perform_action`   | Finder-based tap/set_text/scroll/scroll_until_visible.          |
| `ext.slipstream.enable_semantics` | Enables the semantics tree and waits for the next frame.        |
| `ext.slipstream.get_semantics`    | Returns visible semantics nodes with screen-space coordinates.  |
| `ext.slipstream.overlays`         | Shows/hides Slipstream overlays (e.g. before screenshots).      |
| `ext.slipstream.log`              | Logs an external command (reload, screenshot) to the overlay.   |
| `ext.slipstream.clear_errors`     | Clears the persistent `flutter.error` banner.                   |

### `perform_action` parameters

`action`: `"tap"` | `"set_text"` | `"scroll"` | `"scroll_until_visible"`

`finder`: `"byKey"` | `"byType"` | `"byText"` | `"byTextContaining"` |
`"bySemanticsLabel"`

`finderValue`: string to match against the finder

Additional params by action:

- `set_text`: `text` (required)
- `scroll`: `direction` (`"up"`/`"down"`/`"left"`/`"right"`), `pixels` (double)
- `scroll_until_visible`: `scrollFinder`, `scrollFinderValue` (finder for the
  Scrollable; the target widget is located lazily since it may not be in tree
  yet)

### `get_semantics` return format

Returns `{ ok, nodes }` where each node has: `id`, `role`, `label`, `value`,
`hint`, `checked`, `toggled`, `selected`, `enabled`, `focused`, `actions`,
`left`, `top`, `right`, `bottom` (screen-space logical pixels).

## Ghost Overlay

Installed on the first `ping`. Inserts a named overlay entry into the first
`OverlayState` in the widget tree. Provides:

- **Command log** — transient chips showing agent actions (tap, navigate,
  reload, screenshot) with icons for read/interact/reload/screenshot.
- **Error banner** — persistent count + summary from `FlutterError.onError`.
  Cleared by `ext.slipstream.clear_errors` or `get_output`.
- **Visualizations** — per-action: `"flash"` (full-screen tint), `"outline"`
  (widget bounding box), `"layout"` (box + layout annotations), `"semantics"`
  (all semantics node outlines).
- **Overlay toggle** — `ext.slipstream.overlays` hides/restores everything (used
  by the MCP server before taking screenshots).

The overlay re-installs itself after a hot restart via lazy detection on the
next `log` or `install` call.

## Telemetry

`initTelemetry()` (called by `initialize`) wraps `FlutterError.onError` to
surface framework errors in the ghost overlay. Currently the only telemetry
hook; new hooks should be added in `lib/src/telemetry.dart` and documented
there.

## Key Source Files

| File                          | Contents                                           |
| ----------------------------- | -------------------------------------------------- |
| `lib/slipstream_agent.dart`   | Public API: `SlipstreamAgent.init()`               |
| `lib/src/agent.dart`          | Extension registration, `Agent.initialize()`       |
| `lib/src/ghost_overlay.dart`  | Overlay widget, command log, error banner          |
| `lib/src/actions.dart`        | `tapElement`, `setTextInElement`, `scrollElement`  |
| `lib/src/finder.dart`         | `findElement` — byKey/byType/byText resolution     |
| `lib/src/semantics.dart`      | `getSemanticsNodes` — screen-space coordinate walk |
| `lib/src/router_adapter.dart` | `RouterAdapter`, `GoRouterAdapter`                 |
| `lib/src/telemetry.dart`      | `initTelemetry` — FlutterError hook                |
| `lib/src/overlays.dart`       | Overlay enable/disable (`setOverlaysEnabled`)      |
