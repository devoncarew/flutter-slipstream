# Flutter Inspector Protocol Reference

> For agents working on the inspector server: `ext.flutter.inspector.*`
> protocol details from DevTools source (extension list, parameter quirks,
> `DiagnosticsNode` shape). Read when implementing or debugging protocol calls.

## Extension Name Prefix

```dart
const inspectorExtensionPrefix = 'ext.flutter.inspector';
```

The inspector singleton inside the app is `WidgetInspectorService.instance`.

## Full `ext.flutter.inspector.*` Extension List

| Extension name              | Key params                                                       | Returns              |
| --------------------------- | ---------------------------------------------------------------- | -------------------- |
| `getRootWidget`             | `objectGroup`                                                    | DiagnosticsNode JSON |
| `getRootWidgetTree`         | `groupName`, `isSummaryTree`, `withPreviews`, `fullDetails`      | DiagnosticsNode JSON |
| `getDetailsSubtree`         | `objectGroup`, `arg` (valueId), `subtreeDepth`                   | DiagnosticsNode JSON |
| `getChildren`               | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getChildrenSummaryTree`    | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getChildrenDetailsSubtree` | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getProperties`             | `arg` (nodeRef.id), `objectGroup`                                | List of nodes        |
| `getParentChain`            | `arg` (valueId), `objectGroup`                                   | DiagnosticsNode JSON |
| `getSelectedWidget`         | `objectGroup`                                                    | DiagnosticsNode JSON |
| `getLayoutExplorerNode`     | `groupName`, `id` (valueId), `subtreeDepth`                      | DiagnosticsNode JSON |
| `isWidgetTreeReady`         | (none)                                                           | bool                 |
| `isWidgetCreationTracked`   | (none)                                                           | bool                 |
| `disposeGroup`              | `objectGroup`                                                    | void                 |
| `screenshot`                | `id`, `width`, `height`, `margin`, `maxPixelRatio`, `debugPaint` | base64 PNG string    |
| `widgetLocationIdMap`       | (none)                                                           | Map\<id, location\>  |
| `addPubRootDirectories`     | `arg0`, `arg1`, … (indexed)                                      | void                 |
| `structuredErrors`          | `enabled` ("true"/"false")                                       | void                 |

## Critical Protocol Quirks

### Boolean and numeric params are strings

Pass `'true'`/`'false'`, not `true`/`false`. Same for numeric values like
`subtreeDepth`. Getting this wrong silently passes the wrong type.

### `groupName` vs `objectGroup` inconsistency

There is no consistent parameter name for the object group — you must use the
right one for each extension or group registration is silently skipped:

- `groupName`: `getRootWidgetTree`, `getLayoutExplorerNode`
- `objectGroup`: `getDetailsSubtree`, `getChildren*`, `getProperties`,
  `setSelectionById`, `getRootWidget`, `getParentChain`, `screenshot`
- No group at all: `addPubRootDirectories` / `removePubRootDirectories` (use
  indexed args: `arg0`, `arg1`, etc.)

### `screenshot` uses `id`, not `arg`

Most single-object extensions use `arg` for the `valueId`. Screenshot is the
exception — it uses `id`.

### `valueId` ≠ VM service object ID

Inspector `valueId` strings (e.g. `"inspector-42"`) are scoped to the Flutter
inspector protocol and cannot be passed directly to the VM service `evaluate`
RPC. See "Converting `valueId` to VM Object ID" below.

### `Flutter.Navigation` → wait for `Flutter.Frame`

The widget tree is not repainted at the moment of navigation. Always wait for
the next `Flutter.Frame` event before fetching the tree after a navigation.

### Summary tree `widgetRuntimeType` vs full tree `type`

In summary tree responses, the widget class name is in `widgetRuntimeType`. In
full detail responses it is in `type` (the Dart runtime type of the
DiagnosticsNode wrapper, not the widget). Both may be present.

## Object Groups — Memory Management

Every inspector call that returns a `DiagnosticsNode` must be associated with a
named group. The app holds strong references to objects in that group until
`disposeGroup` is called.

For a simple MCP server making one call at a time, a single static group name is
fine. Call `disposeGroup` periodically to avoid memory accumulation.

## `getRootWidgetTree` Parameters

```dart
invokeServiceMethodDaemonParams('getRootWidgetTree', {
  'groupName': groupName,
  'isSummaryTree': 'true',   // omits framework-internal widgets — right default
  'withPreviews': 'false',   // PNG thumbnails; expensive for agents, set false
  'fullDetails': 'false',    // set true to inline render object data per node
});
```

With `fullDetails: 'false'`, use a separate `getDetailsSubtree` call to get
render data (constraints, size, parentData) for a specific widget.

## `getDetailsSubtree` Pattern

```dart
invokeServiceMethodDaemonParams('getDetailsSubtree', {
  'objectGroup': groupName,    // note: "objectGroup", not "groupName"
  'arg': node.valueId,
  'subtreeDepth': '2',         // string; how deep to recurse
});
```

The response includes a `renderObject` property whose `properties` contain
`constraints`, `size`, and `parentData` as structured sub-maps:

```jsonc
{
  "name": "renderObject",
  "properties": [
    {
      "name": "constraints",
      "description": "BoxConstraints(w=390.0, h=844.0)",
    },
    { "name": "size", "description": "Size(390.0, 200.0)" },
    { "name": "parentData", "description": "offset=Offset(0.0, 0.0)" },
  ],
}
```

## DiagnosticsNode JSON Shape

Inspector extensions return `{ 'result': <node>, 'errorMessage': null }`. Always
extract via `response.json['result']`.

```jsonc
{
  "description": "MyWidget",          // human-readable label
  "type": "DiagnosticableTreeNode",   // Dart runtime type of the node
  "widgetRuntimeType": "MyWidget",    // widget class name (summary tree)
  "valueId": "inspector-42",          // object handle (full detail only)
  "hasChildren": true,
  "children": [ ... ],
  "properties": [ ... ],
  "creationLocation": {               // only in debug builds with creation tracking
    "file": "file:///path/to/lib/main.dart",
    "line": 42,
    "column": 8
  }
}
```

## Converting `valueId` to VM Service Object ID

Inspector `valueId` strings cannot be passed to the VM service `evaluate` RPC
directly. To evaluate an expression on a specific widget instance:

```dart
// Step 1: evaluate this in the inspector library scope
//   (library URI: package:flutter/src/widgets/widget_inspector.dart)
final result = await vmService.evaluate(
  isolateId,
  inspectorLibraryId,
  "WidgetInspectorService.instance.toObject('$valueId')",
) as InstanceRef;
final String vmObjectId = result.id!;  // e.g. "objects/1234"

// Step 2: evaluate on the widget instance
await vmService.evaluate(isolateId, vmObjectId, 'runtimeType.toString()');
```

DevTools does the same pattern internally (`evalOnRef`,
`inspector_service.dart:879`).

## Evaluate Expression Scopes

| Target     | Scope                                              | When to use                   |
| ---------- | -------------------------------------------------- | ----------------------------- |
| Library ID | Root library of the isolate (`isolate.rootLib.id`) | Top-level globals, bindings   |
| Object ID  | Instance members; `this` = the target object       | Evaluate on a specific widget |

```dart
// Get root library ID:
final Isolate isolate = await vmService.getIsolate(isolateRef.id!);
final String libId = isolate.rootLib!.id!;
await vmService.evaluate(isolateRef.id!, libId, expression);
```

## `Flutter.Navigation` Event

Emitted when the Navigator stack changes:

```dart
// event.extensionData.data == {
//   'route': { 'description': '/home', ... }
// }
String? desc = event.extensionData!.data['route']?['description'];
```

The `description` field is typically the widget class name, not a route path.
For go_router path, evaluate `GoRouter.of(context).location` or use
`ext.slipstream.get_route`. After receiving `Flutter.Navigation`, wait for the
next `Flutter.Frame` before fetching the widget tree.

## VM Service Extension Events

| Event kind                             | Description                                    |
| -------------------------------------- | ---------------------------------------------- |
| `Flutter.Error`                        | Unhandled Flutter framework error (structured) |
| `Flutter.Frame`                        | Each rendered frame (with timing data)         |
| `Flutter.FirstFrame`                   | First frame after app start / hot restart      |
| `Flutter.FrameworkInitialization`      | Framework init complete                        |
| `Flutter.Navigation`                   | Navigator stack change                         |
| `Flutter.Print`                        | `debugPrint()` output                          |
| `Flutter.RebuiltWidgets`               | Widgets rebuilt in last frame (performance)    |
| `Flutter.ServiceExtensionStateChanged` | A service extension was toggled                |

## `Flutter.Error` Event Node Types

When `structuredErrors` is enabled, errors arrive as DiagnosticsNode trees:

| `type` field             | Content                                                |
| ------------------------ | ------------------------------------------------------ |
| `ErrorSummary`           | One-line error message (`level == 'summary'`)          |
| `ErrorDescription`       | Prose context                                          |
| `ErrorHint`              | Suggested fix                                          |
| `DiagnosticsBlock`       | Named group of sub-nodes ("The relevant error widget") |
| `DiagnosticableTreeNode` | Offending widget; may include `valueId` for drill-down |
| `DiagnosticsStackTrace`  | Stack frames; first frame is the call site             |

A `valueId` in the error data can be passed to `getDetailsSubtree`.

## Pub Root Directories — Distinguishing Local vs. Framework Widgets

The simpler approach (implemented in `route_formatter.dart`): check whether the
`creationLocation.file` path contains `/.pub-cache/`. More robust than
`addPubRootDirectories` — works for local `path:` dependencies without
registration. `creationLocation` is only populated in debug builds.

## Pre-Call Checks

```dart
// Returns false if the widget tree hasn't built yet; wait for Flutter.Frame:
bool ready = await invokeServiceMethod('isWidgetTreeReady');

// Returns true only in debug builds with --track-widget-creation (default for
// flutter run). If false, creationLocation is absent from all responses:
bool tracked = await invokeServiceMethod('isWidgetCreationTracked');
```
