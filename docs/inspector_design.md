# Inspector MCP: Implementation Design

> For agents working on the inspector server: device auto-selection,
> `get_route` limits, go_router path enrichment, and programmatic navigation.
> Read when working on `run_app`, `get_route`, `navigate`, or session lifecycle.

## Device Auto-Selection

When `device` is omitted from `run_app`, the server runs
`flutter devices --machine` and selects the best available device using this
preference order:

1. **Desktop matching host OS** (macOS / Windows / Linux) — always available on
   the host platform, fast to build (no Xcode/Gradle overhead), full support for
   hot reload, inspector, and screenshots. Best default for agent use.
2. **iOS Simulator** (if already running, macOS only) — better mobile fidelity
   but requires Xcode. The server discovers a booted simulator but never
   launches one (30+ second startup; the agent can't know if the user wants it).
3. **Android emulator** (if already running) — same rationale as iOS.
4. **Connected physical device** — least predictable, but usable.
5. **Web (Chrome)** — deprioritized; `ext.flutter.inspector.screenshot` and VM
   service `evaluate` have reduced capabilities on web.

**Platform-support check:** Before selecting a device, the server verifies the
project has the corresponding platform folder (e.g. `macos/` for desktop-macOS).
A missing folder means `flutter run -d macos` would fail, so that device is
skipped.

**Actionable errors:** If no usable device is found, the error includes the full
`flutter devices` output and a concrete suggestion (e.g. "Run
`flutter create --platforms=macos .` to enable desktop, or start an iOS
simulator.").

**Why not a separate `flutter_list_devices` tool?** Auto-selection handles the
happy path; the error message handles discovery. A list tool adds a step agents
need to learn to call first — more friction, not less. If a need emerges, it can
be added without changing the launch flow.

## `get_route`: Capabilities and Limitations

`get_route` traverses the summary widget tree to find `Navigator` nodes and
resolves each stack entry to the first locally-defined screen widget (not from
`.pub-cache`). Navigators whose entire stack resolves to private-named widgets
(e.g. go_router's `_AppShell` shell-route wrapper) are suppressed.

**Good for:**

- Orientation: confirming which screen is on top before inspecting or editing.
- Back-stack context: understanding how the user arrived at the current screen.
- Pointing the agent at the right source file before reading or editing routing
  code.

**Limitations:**

- **Non-go_router apps:** output contains widget class names only, not route
  strings. The agent still has to read the routes file to discover valid paths
  and their required parameters.
- **Summary tree depth:** `isSummaryTree: true` omits internal Flutter widgets.
  If a project wraps all screens in a private class, those wrappers may be the
  first locally-created widget found, hiding the real screen name.
- **Multiple navigators:** nested setups (shell routes, dialogs, bottom-sheet
  navigators) each appear as a separate stack. The tool suppresses navigators
  composed entirely of private widgets but cannot always determine which is
  "primary."

## go_router Path Enrichment

When `slipstream_agent` is installed, `get_route` enriches the stack with the
current router path via `ext.slipstream.get_route`.

**Fallback — evaluate chain (no companion):** For go_router apps without the
companion, the current URI is extracted by locating `InheritedGoRouter` in the
widget tree and evaluating against its instance:

1. Walk the summary tree → find `InheritedGoRouter` → read its `valueId` (e.g.
   `"inspector-29"`).
2. `inspectorIdToVmObjectId(valueId)` → evaluate
   `WidgetInspectorService.instance.toObject(id)` in the inspector library
   scope. Note: this returns the `InheritedElement`, not the widget itself.
3. `evaluateOnObject(vmId, 'widget.goRouter.state.uri.toString()')` → `.widget`
   reaches the `InheritedGoRouter` widget; `.goRouter` is its field (not
   `.notifier`); `.state.uri` gives the live current path, e.g.
   `/podcast/787ae263b723`.

Detection: presence of `InheritedGoRouter` in the summary tree is sufficient to
identify a go_router app. Other routers (auto_route, beamer) follow the same
InheritedWidget pattern with different field names; they can be added as
separate cases. This enrichment is best-effort — if evaluation fails, the route
stack is still returned without the `Current path:` line.

## `navigate`: go_router Fallback

When `slipstream_agent` is installed, `navigate` calls `ext.slipstream.navigate`
via the registered router adapter.

**Fallback — go_router evaluate (no companion):** Once the `GoRouter` instance
is located via the same evaluate chain as above, navigation is driven directly:

```dart
evaluateOnObject(vmId, 'widget.goRouter.go("/podcast/123")')
```

`go()` returns void — a null/void `InstanceRef` result must be treated as
success, not an error. After calling `go()`, the tool waits for a
`Flutter.Navigation` event or the next `Flutter.Frame` before returning.

The agent still needs to know valid route paths and their parameters (reading
the app's route definition file first is an acceptable prerequisite).

## Known Limitations

- **App state and authentication:** Navigating apps that require login or seeded
  data before reaching the target UI is unsolved. A future design may define an
  `.agent_state.md` convention for startup states, mock data, or auth bypasses.
- **Semantics enable timing:** After calling `ensureSemantics()`, the semantics
  tree populates asynchronously. If `get_semantics` returns an empty tree on the
  first call, retry after a screenshot or hot reload — both synchronize on a
  rendered frame.
