# Flutter Runtime Inspection: Concepts and Data Models

> For agents working on the inspector server: Flutter runtime concepts (the
> four trees, VM service `evaluate`, semantics interaction) and the flag/action
> tables needed to filter the semantics tree.

## The Four Trees

Flutter's UI is composed of four interconnected trees:

1. **Widget Tree** — immutable blueprints written by the developer.
2. **Element Tree** — live instances with `State` objects.
3. **Render Tree** — geometry, constraints, painting. The source of truth for
   layout debugging (overflow, unbounded height, invisible widgets).
4. **Semantics Tree** — accessibility / interaction layer. Required for driving
   UI interactions without pointer coordinates.

## VM Service `evaluate` — Preferred Read Path

For live Dart values, prefer `evaluate` over inspector string-parsing. It runs
real Dart on the isolate and returns an exact typed value.

```dart
// Screen dimensions (no regex needed):
WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.toString()

// MediaQuery:
MediaQuery.of(context).toString()  // requires a valid BuildContext

// Any FlutterView property (physicalSize, padding, viewInsets, devicePixelRatio):
WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()
```

See `docs/research/inspector_protocol.md` section "Evaluate Expression Scopes"
for how to target the right library scope.

## UI Interaction via `performSemanticsAction`

Semantics actions do not require screen coordinates and work on unmodified apps.

```dart
// Enable semantics once at session start:
RendererBinding.instance.ensureSemantics()

// Tap:
SemanticsBinding.instance.performSemanticsAction(
  SemanticsActionEvent(
    type: SemanticsAction.tap,
    nodeId: 42,
    viewId: WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
  ),
)

// Set text field content:
SemanticsBinding.instance.performSemanticsAction(
  SemanticsActionEvent(
    type: SemanticsAction.setText,
    nodeId: 42,
    viewId: WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    arguments: 'hello world',
  ),
)
```

`viewId` is always `0` for single-window apps. The semantics node `id` is a
framework-internal integer — not an inspector handle. No conversion needed.

After calling `ensureSemantics()`, wait for the next frame before reading the
tree (the tree is built asynchronously on first enable):

```dart
SchedulerBinding.instance.addPostFrameCallback((_) { /* tree is ready */ });
```

Approaches that do NOT work on unmodified apps: `ext.flutter.driver.*`
extensions (require app-side registration) and `debugDumpSemanticsTree()`
(returns ASCII art, not structured data).

## Semantics Tree Access

```dart
// Root node (id == 0; null if semantics not yet built):
RendererBinding.instance.pipelineOwner.semanticsOwner?.rootSemanticsNode

// Walk children:
node.visitChildren((SemanticsNode child) => true);
```

### Filtering for Visible Interactive Nodes

When walking the tree:

1. Skip `isInvisible == true` (empty rect or zeroed transform)
2. Skip `flags & (1<<13) != 0` (`isHidden` — off-screen nodes)
3. Nodes with `mergeAllDescendantsIntoThisNode == true` carry the merged
   label/value of their subtree — treat as leaf, don't recurse
4. Nodes with `isMergedIntoParent == true` are already rolled up — skip

### Coordinate System

`rect` is in local coordinate space, not screen coordinates. The root node's
local system is screen coordinates. For child nodes, accumulate `transform`
values from the root. Most top-level widgets (AppBar, body, FAB) are direct
children of root, so their `rect` is already in screen coordinates.

## `SemanticsNode` Key Fields

| Field                             | Type       | Notes                                                       |
| --------------------------------- | ---------- | ----------------------------------------------------------- |
| `id`                              | `int`      | Root is 0. Directly usable as `SemanticsActionEvent.nodeId` |
| `rect`                            | `Rect`     | Bounding box in local coordinate space                      |
| `transform`                       | `Matrix4?` | Local → parent; null means identity                         |
| `label`                           | `String`   | Primary accessibility label                                 |
| `value`                           | `String`   | Current value (slider position, text field content)         |
| `isInvisible`                     | `bool`     | `rect.isEmpty \|\| transform.isZero()` — skip these         |
| `mergeAllDescendantsIntoThisNode` | `bool`     | When true, treat as leaf                                    |
| `isMergedIntoParent`              | `bool`     | Already rolled up into parent — skip or de-duplicate        |

## `SemanticsFlag` Bitmask Reference

| Flag                         | Bit     | Meaning                                         |
| ---------------------------- | ------- | ----------------------------------------------- |
| `hasCheckedState`            | 1       | Node can be checked/unchecked (checkbox, radio) |
| `isChecked`                  | 2       | Currently checked                               |
| `isCheckStateMixed`          | `1<<25` | Tristate checkbox — mixed state                 |
| `hasSelectedState`           | `1<<28` | Node can be selected (tab, list item)           |
| `isSelected`                 | 4       | Currently selected                              |
| `isButton`                   | 8       | Button role                                     |
| `isTextField`                | 16      | Text input field                                |
| `isSlider`                   | `1<<23` | Slider control                                  |
| `isLink`                     | `1<<22` | Interactive hyperlink                           |
| `isImage`                    | `1<<14` | Image                                           |
| `isHeader`                   | `1<<9`  | Section header                                  |
| `isFocusable`                | `1<<21` | Can receive input focus                         |
| `isFocused`                  | `1<<5`  | Currently has input focus                       |
| `hasEnabledState`            | `1<<6`  | Node can be enabled/disabled                    |
| `isEnabled`                  | `1<<7`  | Currently enabled                               |
| `isInMutuallyExclusiveGroup` | `1<<8`  | Radio button (one of a group)                   |
| `isObscured`                 | `1<<10` | Password field                                  |
| `isMultiline`                | `1<<19` | Multi-line text field                           |
| `isReadOnly`                 | `1<<20` | Read-only text field                            |
| `hasToggledState`            | `1<<16` | Node can be toggled on/off (Switch)             |
| `isToggled`                  | `1<<17` | Currently toggled on                            |
| `hasExpandedState`           | `1<<26` | Can expand/collapse                             |
| `isExpanded`                 | `1<<27` | Currently expanded                              |
| `isHidden`                   | `1<<13` | Off-screen; skip for visible-element queries    |
| `isLiveRegion`               | `1<<15` | Updates auto-announced (SnackBar)               |
| `hasImplicitScrolling`       | `1<<18` | Container scrolls to reveal focus (ListView)    |
| `scopesRoute`                | `1<<11` | Root of a route subtree (Dialog, Drawer)        |
| `namesRoute`                 | `1<<12` | Label names the current route                   |
| `hasRequiredState`           | `1<<29` | Form field that may be required                 |
| `isRequired`                 | `1<<30` | Currently required                              |

## `SemanticsAction` Bitmask Reference

| Action                       | Bit               | Use                               |
| ---------------------------- | ----------------- | --------------------------------- |
| `tap`                        | 1                 | Tap the node                      |
| `longPress`                  | 2                 | Long press                        |
| `scrollLeft` / `scrollRight` | 4 / 8             | Horizontal scroll                 |
| `scrollUp` / `scrollDown`    | 16 / 32           | Vertical scroll                   |
| `increase` / `decrease`      | 64 / 128          | Slider adjustment                 |
| `setText`                    | `1<<21`           | Replace text field content        |
| `setSelection`               | `1<<11`           | Move cursor / set selection range |
| `focus`                      | `1<<22`           | Request input focus               |
| `expand` / `collapse`        | `1<<24` / `1<<25` | Expand or collapse                |
| `dismiss`                    | `1<<18`           | Dismiss (dialog, snackbar)        |
| `showOnScreen`               | `1<<8`            | Scroll to make this node visible  |
