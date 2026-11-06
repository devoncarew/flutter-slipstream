import 'dart:async';

import 'package:vm_service/vm_service.dart';

import 'app_session.dart';
import 'diagnostics_node.dart';
import 'semantic_node.dart';

/// Provides 1:1 access to Flutter VM service extensions.
///
/// Each method maps directly to one `ext.flutter.*` service extension call.
/// Higher-level convenience methods that combine multiple calls belong in
/// [AppSession] instead.
class FlutterServiceExtensions {
  // Object group name used for inspector extension calls. The inspector uses
  // groups to manage the lifetime of server-side object references.
  static const String inspectorGroup = 'flutter_slipstream';

  final VmService _vmService;

  // Cache from extension RPC name to isolate ID. Populated on first call to
  // _isolateIdForExtension (full scan) and kept up to date via isolate events.
  final Map<String, String> _extensionToIsolateId = {};
  StreamSubscription<Event>? _isolateEventSub;

  // TODO: We need to null this out when the associated isolate stops (as part
  // of a hot restart).
  String? companionVersion;

  /// The isolate hosting the companion package;
  String? _companionIsolateId;

  FlutterServiceExtensions(this._vmService) {
    // Ensure the kIsolate stream is active (safe to call even if app_session
    // has already called it — the resulting StreamAlreadySubscribed error is
    // ignored by the caller there).
    _vmService.streamListen(EventStreams.kIsolate).ignore();
    _isolateEventSub = _vmService.onIsolateEvent.listen(_handleIsolateEvent);
  }

  void _handleIsolateEvent(Event event) {
    if (event.kind == EventKind.kServiceExtensionAdded) {
      final ext = event.extensionRPC;
      final isolateId = event.isolate?.id;
      if (ext != null && isolateId != null) {
        _extensionToIsolateId[ext] = isolateId;
      }
    } else if (event.kind == EventKind.kIsolateExit) {
      final isolateId = event.isolate?.id;

      // Remove all related extension methods from the cache.
      if (isolateId != null) {
        _extensionToIsolateId.removeWhere((_, id) => id == isolateId);
      }

      // If the exiting isolate hosts the companion agent, reset that info.
      if (_companionIsolateId == isolateId) {
        companionVersion = null;
        _companionIsolateId = null;
      }
    }
  }

  void dispose() {
    _isolateEventSub?.cancel();
    _isolateEventSub = null;
    _vmService.dispose();
  }

  // ---------------------------------------------------------------------------
  // VM service (non-extension) helpers

  /// Returns all extension RPCs registered across all live isolates.
  Future<List<String>> listServiceExtensions() async {
    final VM vm = await _vmService.getVM();
    final List<String> extensions = [];
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      extensions.addAll(isolate.extensionRPCs ?? []);
    }
    extensions.sort();
    return extensions;
  }

  // ---------------------------------------------------------------------------
  // ext.slipstream.* — companion package

  /// Calls `ext.slipstream.ping` to detect the slipstream_agent companion
  /// package.
  ///
  /// Returns the companion version string (e.g. `"0.1.0"`) if the companion is
  /// installed and registered, or `null` if it is not. Never throws — fails
  /// open so the caller does not need to handle the no-companion case specially.
  Future<String?> pingCompanion() async {
    // Short circuit the call when we already have the agent info.
    if (companionVersion != null) {
      return companionVersion;
    }

    try {
      final response = await _callExtension('ext.slipstream.ping');
      final versionResponse = response.json?['version'] as String?;

      _companionIsolateId = await _isolateIdForExtension('ext.slipstream.ping');
      companionVersion = versionResponse;

      return versionResponse;
    } catch (_) {
      // Extension not registered — companion not installed. Fail open.
      return null;
    }
  }

  /// Calls `ext.slipstream.perform_action` to tap a widget located by
  /// [finder]/[finderValue].
  ///
  /// Returns `(ok: true)` on success or `(ok: false, error: '...')` on failure.
  Future<({bool ok, String? error})> slipstreamTap({
    required String finder,
    required String finderValue,
  }) => _slipstreamAction({
    'action': 'tap',
    'finder': finder,
    'finderValue': finderValue,
  });

  /// Calls `ext.slipstream.perform_action` to set text on a widget located by
  /// [finder]/[finderValue].
  ///
  /// Returns `(ok: true)` on success or `(ok: false, error: '...')` on failure.
  Future<({bool ok, String? error})> slipstreamSetText({
    required String finder,
    required String finderValue,
    required String text,
  }) => _slipstreamAction({
    'action': 'set_text',
    'finder': finder,
    'finderValue': finderValue,
    'text': text,
  });

  /// Calls `ext.slipstream.perform_action` to scroll a [Scrollable] widget
  /// located by [finder]/[finderValue] by [pixels] logical pixels in
  /// [direction].
  ///
  /// Returns `(ok: true)` on success or `(ok: false, error: '...')` on failure.
  Future<({bool ok, String? error})> slipstreamScroll({
    required String finder,
    required String finderValue,
    required String direction,
    required double pixels,
  }) => _slipstreamAction({
    'action': 'scroll',
    'finder': finder,
    'finderValue': finderValue,
    'direction': direction,
    'pixels': pixels,
  });

  /// Calls `ext.slipstream.perform_action` to scroll the [Scrollable] located
  /// by [scrollFinder]/[scrollFinderValue] until the widget located by
  /// [finder]/[finderValue] is visible.
  ///
  /// Returns `(ok: true)` on success or `(ok: false, error: '...')` on failure.
  Future<({bool ok, String? error})> slipstreamScrollUntilVisible({
    required String finder,
    required String finderValue,
    required String scrollFinder,
    required String scrollFinderValue,
  }) => _slipstreamAction({
    'action': 'scroll_until_visible',
    'finder': finder,
    'finderValue': finderValue,
    'scrollFinder': scrollFinder,
    'scrollFinderValue': scrollFinderValue,
  });

  Future<({bool ok, String? error})> _slipstreamAction(
    Map<String, dynamic> args,
  ) async {
    final response = await _callExtension(
      'ext.slipstream.perform_action',
      args: args,
    );
    final json = (response.json ?? {}).cast<String, dynamic>();
    return (ok: json['ok'] as bool? ?? false, error: json['error'] as String?);
  }

  /// Calls `ext.slipstream.navigate` to navigate the app to [path] via the
  /// registered router adapter.
  ///
  /// Returns `(ok: true)` on success or `(ok: false, error: '...')` on failure.
  Future<({bool ok, String? error})> slipstreamNavigate(String path) async {
    final response = await _callExtension(
      'ext.slipstream.navigate',
      args: {'path': path},
    );
    final json = (response.json ?? {}).cast<String, dynamic>();
    return (ok: json['ok'] as bool? ?? false, error: json['error'] as String?);
  }

  /// Calls `ext.slipstream.get_route` to get the current route path from the
  /// registered router adapter.
  ///
  /// Returns `(ok: true, path: '/...')` on success or
  /// `(ok: false, error: '...')` on failure.
  Future<({bool ok, String? path, String? error})> slipstreamGetRoute() async {
    final response = await _callExtension('ext.slipstream.get_route');
    final json = (response.json ?? {}).cast<String, dynamic>();
    return (
      ok: json['ok'] as bool? ?? false,
      path: json['path'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Calls `ext.slipstream.enable_semantics` to enable the Flutter semantics
  /// tree and schedule a frame so the tree is populated.
  Future<void> slipstreamEnableSemantics() async {
    await _callExtension('ext.slipstream.enable_semantics');
  }

  /// Calls `ext.slipstream.get_semantics` to get a flat list of visible
  /// semantics nodes with screen-space coordinates.
  ///
  /// Returns `(ok: true, nodes: [...])` on success or
  /// `(ok: false, error: '...')` on failure (e.g. semantics not enabled).
  Future<({bool ok, List<SemanticNode> nodes, String? error})>
  slipstreamGetSemantics() async {
    final response = await _callExtension('ext.slipstream.get_semantics');
    final json = (response.json ?? {}).cast<String, dynamic>();
    final bool ok = json['ok'] as bool? ?? false;
    return (
      ok: ok,
      nodes:
          ok
              ? parseCompanionSemanticsNodes(
                json['nodes'] as List<dynamic>? ?? [],
              )
              : const <SemanticNode>[],
      error: json['error'] as String?,
    );
  }

  /// Calls `ext.slipstream.log` to record an agent command in the ghost
  /// overlay command log.
  ///
  /// [command] is a short label such as `"reload"`, `"screenshot"`, or
  /// `"evaluate"`. [details] is an optional string appended after a colon
  /// (e.g. a path or expression snippet). In-process extensions
  /// (`perform_action`, `navigate`, etc.) log themselves automatically — call
  /// this only for operations that go through the MCP server directly.
  ///
  /// [kind] is the icon category shown in the overlay:
  /// `"reload"`, `"screenshot"`, `"read"`, or `"interact"`.
  ///
  /// [finder] and [finderValue] identify the widget of interest (used with
  /// `viz: "outline"` or `viz: "layout"`).
  ///
  /// [viz] requests an extra visualisation:
  /// `"flash"`, `"outline"`, `"layout"`, or `"semantics"`.
  ///
  /// Best-effort: failures are silently ignored so a logging hiccup never
  /// breaks the calling tool.
  Future<void> slipstreamLog(
    String command, {
    String? details,
    String? kind,
    String? finder,
    String? finderValue,
    String? viz,
  }) async {
    try {
      final Map<String, dynamic> args = {'command': command};
      if (details != null) args['details'] = details;
      if (kind != null) args['kind'] = kind;
      if (finder != null) args['finder'] = finder;
      if (finderValue != null) args['finderValue'] = finderValue;
      if (viz != null) args['viz'] = viz;
      await _callExtension('ext.slipstream.log', args: args);
    } catch (_) {
      // Logging is best-effort — never let it break the calling tool.
    }
  }

  /// Calls `ext.slipstream.clear_errors` to dismiss the persistent
  /// `flutter.error` banner from the ghost overlay.
  ///
  /// Call after draining output that contained `[flutter.error]` lines, or
  /// whenever the agent has acknowledged the errors. Best-effort: failures are
  /// silently ignored.
  Future<void> slipstreamClearErrors() async {
    try {
      await _callExtension('ext.slipstream.clear_errors');
    } catch (_) {
      // Best-effort — don't let a clear-errors failure break the calling tool.
    }
  }

  /// Calls `ext.slipstream.overlays` to show or hide Slipstream-managed
  /// overlays (currently the Flutter debug banner).
  ///
  /// Pass `enabled: false` before taking a screenshot to hide overlays, then
  /// `enabled: true` to restore them. Best-effort: failures are silently
  /// ignored.
  Future<void> slipstreamOverlays({required bool enabled}) async {
    try {
      await _callExtension(
        'ext.slipstream.overlays',
        args: {'enabled': enabled},
      );
    } catch (_) {
      // Best-effort — don't let an overlay failure break the screenshot.
    }
  }

  // ---------------------------------------------------------------------------
  // Semantics

  /// Enables the Flutter semantics tree and schedules a frame so the tree
  /// is populated immediately.
  ///
  /// Should be called once after the VM service connects and again after each
  /// hot restart (which creates a new isolate and resets all Dart state).
  /// Callers should wrap this in a try/catch — it is best-effort and may fail
  /// if the Flutter framework has not yet initialized.
  ///
  /// The [SemanticsHandle] returned by [ensureSemantics] is intentionally not
  /// retained — Dart's GC does not call [SemanticsHandle.dispose], so the
  /// reference count stays incremented and the tree remains active for the
  /// lifetime of the app process. Safe to call multiple times.
  Future<void> bootstrapSemantics() async {
    // RendererBinding is not in the root library scope, so we evaluate in
    // widget_inspector.dart which imports package:flutter/rendering.dart.
    await evaluate(
      'RendererBinding.instance.ensureSemantics()',
      libraryUri: 'package:flutter/src/widgets/widget_inspector.dart',
    );
    await evaluate(
      'WidgetsBinding.instance.scheduleFrame()',
      libraryUri: 'package:flutter/src/widgets/widget_inspector.dart',
    );
  }

  /// Dispatches [actionType] on a semantics node identified by [nodeId] or
  /// [label].
  ///
  /// If [nodeId] is provided, the action is dispatched directly without
  /// fetching the semantics tree. If only [label] is provided, the tree is
  /// fetched and the first node whose label contains [label]
  /// (case-insensitive) is used.
  ///
  /// [actionType] must be a valid `SemanticsAction` name from `dart:ui`
  /// (e.g. `tap`, `longPress`, `scrollUp`, `scrollDown`, `increase`,
  /// `decrease`, `setText`, `focus`).
  ///
  /// Returns a success message, or an `"error:..."` string if the node cannot
  /// be found.
  Future<String> performSemanticsAction({
    required String actionType,
    int? nodeId,
    String? label,
    String? arguments,
  }) async {
    assert(
      nodeId != null || label != null,
      'performSemanticsAction: one of nodeId or label must be provided',
    );

    final int resolvedId;

    if (nodeId != null) {
      resolvedId = nodeId;
    } else {
      final List<SemanticNode> nodes = await getSemanticsTree();
      final String labelLower = label!.toLowerCase();
      final SemanticNode? match =
          nodes
              .where((n) => n.label.toLowerCase().contains(labelLower))
              .firstOrNull;
      if (match == null) {
        return 'error: no visible semantics node with label containing "$label"';
      }
      resolvedId = match.id;
    }

    // Build the arguments part of the SemanticsActionEvent constructor.
    // setText requires arguments: 'the text'; most other actions pass none.
    final String argsParam =
        arguments != null
            ? ", arguments: '${arguments.replaceAll("'", "\\'")}'"
            : '';

    await evaluate(
      'SemanticsBinding.instance.performSemanticsAction('
      'SemanticsActionEvent('
      'type: SemanticsAction.$actionType, '
      'nodeId: $resolvedId, '
      'viewId: (SemanticsBinding.instance as dynamic)'
      '.platformDispatcher.implicitView!.viewId$argsParam))',
      // rendering/binding.dart imports package:flutter/semantics.dart, making
      // both SemanticsAction and SemanticsActionEvent available without a prefix.
      libraryUri: 'package:flutter/src/rendering/binding.dart',
    );

    return "performed '$actionType' on node id $resolvedId";
  }

  /// Returns the current Flutter semantics tree as a flat list of
  /// [SemanticNode]s.
  ///
  /// Semantics must be enabled first (done automatically at session start via
  /// [enableSemantics]). Hidden, invisible, and merged-into-parent nodes are
  /// excluded. Ordering is depth-first (top-to-bottom on screen, roughly).
  ///
  /// Throws an [RPCError] on VM service failures. Returns an empty list if the
  /// tree is not yet populated (retry after the next frame).
  Future<List<SemanticNode>> getSemanticsTree() async {
    final String json = await _getSemanticsTreeJson();
    if (json.startsWith('error:')) return [];
    return parseSemanticsTree(json);
  }

  /// Evaluates the semantics tree IIFE on the main isolate and returns the raw
  /// JSON string. The JSON is a flat array of tuples — see [parseSemanticsTree]
  /// for the format.
  ///
  /// Returns an `"error:..."` string if semantics is not enabled or the tree
  /// is empty. Throws an [RPCError] on VM service failures.
  Future<String> _getSemanticsTreeJson() async {
    // Evaluate in semantics.dart scope: SemanticsNode, SemanticsBinding,
    // CheckedState, and Tristate are all in scope there. RendererBinding is
    // not in scope, but we access pipelineOwner via
    // (SemanticsBinding.instance as dynamic).pipelineOwner.
    const String inspectorLibUri =
        'package:flutter/src/semantics/semantics.dart';

    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = _libraryIdForUri(isolate, inspectorLibUri);
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        _kSemanticsTreeExpression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? '_getSemanticsTreeJson failed',
          fromMethod: '_getSemanticsTreeJson',
        );
      }
      if (result is InstanceRef) {
        // valueAsString is truncated for long strings — fetch the full object.
        if (result.valueAsStringIsTruncated == true) {
          final obj = await _vmService.getObject(ref.id!, result.id!);
          if (obj is Instance) {
            return obj.valueAsString ?? 'error:null result';
          }
        }
        return result.valueAsString ?? 'error:null result';
      }
    }
    throw rpcError(
      'No suitable isolate found for _getSemanticsTreeJson',
      fromMethod: '_getSemanticsTreeJson',
    );
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.debugPaint

  /// Returns whether the debug paint overlay is currently enabled.
  Future<bool> getDebugPaint() async {
    final Response response = await _callExtension('ext.flutter.debugPaint');
    return response.json!['enabled'] == 'true';
  }

  /// Enables or disables the debug paint overlay (layout debug lines).
  Future<void> setDebugPaint(bool enabled) async {
    await _callExtension(
      'ext.flutter.debugPaint',
      args: {'enabled': enabled.toString()},
    );
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.*

  /// Returns the root widget as a [DiagnosticsNode] JSON map.
  ///
  /// Returns the root widget node with full detail, including [DiagnosticsNode.valueId]
  /// which is the inspector object handle needed by [screenshot].
  ///
  /// This is a separate implementation from [getRootWidgetTree] and takes no
  /// tree-shape parameters.
  Future<DiagnosticsNode> getRootWidget() async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getRootWidget',
      args: {'objectGroup': inspectorGroup},
    );
    return DiagnosticsNode.fromJson(_unwrapResponse('getRootWidget', response));
  }

  /// Returns the root widget tree, with control over its shape.
  ///
  /// [isSummaryTree] omits lower-level internal widgets (default true).
  /// [withPreviews] includes screenshot thumbnails for each node (default false).
  /// [fullDetails] includes full property detail (default true).
  Future<DiagnosticsNode> getRootWidgetTree({
    bool? isSummaryTree,
    bool? withPreviews,
    bool? fullDetails,
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getRootWidgetTree',
      args: {
        'groupName': inspectorGroup,
        if (isSummaryTree != null) 'isSummaryTree': isSummaryTree.toString(),
        if (withPreviews != null) 'withPreviews': withPreviews.toString(),
        if (fullDetails != null) 'fullDetails': fullDetails.toString(),
      },
    );
    return DiagnosticsNode.fromJson(
      _unwrapResponse('getRootWidgetTree', response),
    );
  }

  /// Returns the details subtree for the object with [id].
  ///
  /// The response includes full property detail, including render object sizes.
  ///
  /// [subtreeDepth] will default to 2 if not passed.
  Future<DiagnosticsNode> getDetailsSubtree(
    String diagnosticableId, {
    int? subtreeDepth,
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getDetailsSubtree',
      args: {
        'objectGroup': inspectorGroup,
        'arg': diagnosticableId,
        if (subtreeDepth != null) 'subtreeDepth': subtreeDepth.toString(),
      },
    );

    return DiagnosticsNode.fromJson(
      _unwrapResponse('getDetailsSubtree', response),
    );
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.getParentChain

  /// Returns the chain of ancestor nodes from the root down to the widget with
  /// [diagnosticableId], as a [DiagnosticsNode].
  ///
  /// Useful for understanding where a widget sits in the overall tree without
  /// needing to walk the entire tree from the root. Each node in the chain has
  /// its children populated only enough to show the path.
  Future<DiagnosticsNode> getParentChain(String diagnosticableId) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.getParentChain',
      args: {'arg': diagnosticableId, 'objectGroup': inspectorGroup},
    );
    return DiagnosticsNode.fromJson(
      _unwrapResponse('getParentChain', response),
    );
  }

  // ---------------------------------------------------------------------------
  // VM service evaluate on an object instance

  /// Evaluates [expression] in the context of the VM object with [vmObjectId].
  ///
  /// Unlike [evaluate] (which runs in the root library scope), this evaluates
  /// with `this` bound to the specified object — fields and methods of that
  /// object are directly in scope.
  ///
  /// [vmObjectId] must be a raw VM service object ID (e.g. `objects/123`), as
  /// returned by [evaluateToObjectId]. Inspector group handles such as
  /// `inspector-29` are NOT valid here — those are scoped to the Flutter
  /// inspector protocol and cannot be used directly as VM evaluate targets.
  ///
  /// Returns the `toString()` of the result. Throws an [RPCError] on failure.
  Future<String> evaluateOnObject(String vmObjectId, String expression) async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Response result = await _vmService.evaluate(
        ref.id!,
        vmObjectId,
        expression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'evaluateOnObject failed',
          fromMethod: 'evaluateOnObject',
        );
      }
      if (result is InstanceRef) {
        return result.valueAsString ??
            result.classRef?.name ??
            result.kind ??
            '?';
      }
    }
    throw rpcError(
      'No suitable isolate found for evaluateOnObject',
      fromMethod: 'evaluateOnObject',
    );
  }

  /// Evaluates [expression] in the root library scope and returns the raw VM
  /// service object ID of the result, rather than its string representation.
  ///
  /// Use this to obtain a [vmObjectId] for [evaluateOnObject]. For example,
  /// to call methods on a GoRouter stored as a top-level variable `_router`:
  ///
  /// ```dart
  /// final id = await extensions.evaluateToObjectId('_router');
  /// final result = await extensions.evaluateOnObject(id, 'go("/home")');
  /// ```
  ///
  /// Returns null if the result has no object identity (e.g. it is a primitive
  /// like `int` or `String`). Throws an [RPCError] on failure.
  Future<String?> evaluateToObjectId(String expression) async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = isolate.rootLib?.id;
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        expression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'evaluateToObjectId failed',
          fromMethod: 'evaluateToObjectId',
        );
      }
      if (result is InstanceRef) {
        return result.id;
      }
    }
    throw rpcError(
      'No suitable isolate found for evaluateToObjectId',
      fromMethod: 'evaluateToObjectId',
    );
  }

  /// Converts an inspector `valueId` (e.g. `"inspector-42"`) to a raw VM
  /// service object ID (e.g. `"objects/1234"`) suitable for use with
  /// [evaluateOnObject].
  ///
  /// Inspector handles are scoped to the Flutter inspector protocol and cannot
  /// be passed directly to the VM service `evaluate` RPC as a target object.
  /// This method bridges them by evaluating
  /// `WidgetInspectorService.instance.toObject(valueId)` in the inspector
  /// library scope — the same technique used by DevTools (`evalOnRef` in
  /// `inspector_service.dart`).
  ///
  /// Returns null if the inspector handle cannot be resolved (e.g. the object
  /// has been garbage collected or the group was disposed). Throws an [RPCError]
  /// on failure.
  Future<String?> inspectorIdToVmObjectId(String valueId) async {
    const String inspectorLibUri =
        'package:flutter/src/widgets/widget_inspector.dart';

    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = _libraryIdForUri(isolate, inspectorLibUri);
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        "WidgetInspectorService.instance.toObject('$valueId')",
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'inspectorIdToVmObjectId failed',
          fromMethod: 'inspectorIdToVmObjectId',
        );
      }
      if (result is InstanceRef) {
        return result.id;
      }
    }
    throw rpcError(
      'No suitable isolate found for inspectorIdToVmObjectId',
      fromMethod: 'inspectorIdToVmObjectId',
    );
  }

  /// Returns the library ID for the library with [uri] in [isolate], or null
  /// if no such library is loaded.
  String? _libraryIdForUri(Isolate isolate, String uri) {
    for (final lib in isolate.libraries ?? <LibraryRef>[]) {
      if (lib.uri == uri) return lib.id;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.setSelectionById

  /// Moves the inspector selection to the widget with [id] on the connected
  /// device or emulator.
  ///
  /// This is the same action DevTools performs when you click a widget in the
  /// Widget Tree — it forces the on-screen highlight to move to the widget
  /// without requiring a physical tap.
  ///
  /// Pass `null` for [id] to clear the current selection.
  ///
  /// Returns `true` if the selection was changed.
  Future<bool> setSelectionById(String? id) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.setSelectionById',
      args: {'arg': id, 'objectGroup': inspectorGroup},
    );
    return response.json!['result'] as bool? ?? false;
  }

  // ---------------------------------------------------------------------------
  // ext.flutter.inspector.screenshot

  /// Takes a screenshot of the object with [id], rendered at [width] × [height]
  /// logical pixels. Returns base64-encoded PNG data, or null if the object is
  /// not currently visible.
  ///
  /// [margin] will default to 0 if not passed.
  /// [maxPixelRatio] will default to 1.0 if not passed.
  /// [debugPaint] will default to false if not passed.
  Future<String?> screenshot({
    required String id,
    required double width,
    required double height,
    double? margin,
    double? maxPixelRatio,
    bool? debugPaint,
  }) async {
    final Response response = await _callExtension(
      'ext.flutter.inspector.screenshot',
      args: {
        'id': id,
        'width': width.toString(),
        'height': height.toString(),
        if (margin != null) 'margin': margin.toString(),
        if (maxPixelRatio != null) 'maxPixelRatio': maxPixelRatio.toString(),
        if (debugPaint != null) 'debugPaint': debugPaint.toString(),
      },
    );
    return response.json!['result'] as String?;
  }

  // ---------------------------------------------------------------------------
  // VM service evaluate

  /// Evaluates [expression] on the main isolate and returns the result as a
  /// string.
  ///
  /// By default the expression is evaluated in the context of the isolate's
  /// root library (`main.dart`), so top-level declarations and globals like
  /// `WidgetsBinding.instance` are in scope.
  ///
  /// Pass [libraryUri] to evaluate in a different library scope. For example,
  /// `package:flutter/src/widgets/widget_inspector.dart` imports
  /// `package:flutter/rendering.dart` and `dart:ui`, making `RendererBinding`,
  /// `SemanticsNode`, `CheckedState`, `Tristate`, etc. available.
  ///
  /// Returns the `toString()` of the result. Throws an [RPCError] if the
  /// expression fails to compile or throws at runtime — the error message
  /// includes the Dart exception text.
  Future<String> evaluate(String expression, {String? libraryUri}) async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId =
          libraryUri != null
              ? _libraryIdForUri(isolate, libraryUri)
              : isolate.rootLib?.id;
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        expression,
      );

      if (result is ErrorRef) {
        throw rpcError(
          result.message ?? 'evaluate failed',
          fromMethod: 'evaluate',
        );
      }
      if (result is InstanceRef) {
        // Primitive values (String, int, double, bool, null) have their value
        // inline. For other types, valueAsString holds the toString() output.
        return result.valueAsString ??
            result.classRef?.name ??
            result.kind ??
            '?';
      }
    }
    throw rpcError(
      'No suitable isolate found for evaluate',
      fromMethod: 'evaluate',
    );
  }

  // ---------------------------------------------------------------------------
  // Window size via VM service evaluate

  /// Returns the physical window size by evaluating a Dart expression on the
  /// main isolate.
  ///
  /// This avoids the inspector extension string-parsing path entirely — the VM
  /// service `evaluate` RPC runs real Dart code and returns the exact value.
  /// Returns null if the expression cannot be evaluated or the result cannot
  /// be parsed.
  ///
  /// Evaluates in `widgets/binding.dart` rather than the root library, so this
  /// works for entrypoints that don't import Flutter widgets (#135).
  Future<(double, double)?> getPhysicalWindowSize() async {
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      final String? libId = _libraryIdForUri(
        isolate,
        'package:flutter/src/widgets/binding.dart',
      );
      if (libId == null) continue;

      final Response result = await _vmService.evaluate(
        ref.id!,
        libId,
        'WidgetsBinding.instance.platformDispatcher.views.first.physicalSize'
        '.toString()',
      );

      if (result is InstanceRef && result.valueAsString != null) {
        final match = _sizeRegExp.firstMatch(result.valueAsString!);
        if (match != null) {
          return (double.parse(match.group(1)!), double.parse(match.group(2)!));
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Size helpers

  /// Returns the logical size of the widget with [diagnosticableId] by
  /// examining its details subtree. Returns null values if the size cannot be
  /// determined.
  Future<(double?, double?)> getWidgetSize(String diagnosticableId) async {
    try {
      // Depth 4 to ensure we reach the RenderBox node, which may be several
      // levels below the root element in the details subtree.
      final DiagnosticsNode node = await getDetailsSubtree(
        diagnosticableId,
        subtreeDepth: 4,
      );
      final (double, double)? size = _extractSize(node);
      if (size != null) return size;
    } catch (_) {
      // Fall through to null.
    }
    return (null, null);
  }

  /// Extracts a logical pixel size from [node]'s details subtree.
  ///
  /// Navigates to the `renderObject` property and reads its `view size`
  /// property, which contains the logical pixel dimensions as a string like
  /// "Size(390.0, 844.0)". Recurses into children.
  (double, double)? _extractSize(DiagnosticsNode node) {
    final renderObject = node.propertyNamed('renderObject');
    final size = renderObject?.propertyNamed('view size');

    if (size != null) {
      final RegExpMatch? match = _sizeRegExp.firstMatch(size.description);
      if (match != null) {
        return (double.parse(match.group(1)!), double.parse(match.group(2)!));
      }
    }

    for (final DiagnosticsNode child in node.children) {
      final (double, double)? result = _extractSize(child);
      if (result != null) return result;
    }

    return null;
  }

  // "Size(740.0, 1645.6) (in physical pixels)"
  static final RegExp _sizeRegExp = RegExp(
    r'Size\((\d+\.?\d*),\s*(\d+\.?\d*)\)',
  );

  // ---------------------------------------------------------------------------
  // Internal

  /// Unwraps the `result` key from an inspector extension response.
  ///
  /// Inspector extensions return `{'result': node}` rather than the node
  /// directly. This helper extracts the inner map. Throws an [RPCError] if
  /// `result` is null or not a map — which happens when the widget ID is
  /// invalid or the object has been garbage collected.
  Map<String, dynamic> _unwrapResponse(
    String callingMethod,
    Response response,
  ) {
    if (response.json?['error'] != null) {
      throw RPCError.parse(callingMethod, response.json!['error']);
    }

    if (response.json!['result'] == null) {
      throw RPCError(
        callingMethod,
        0,
        'Widget ID invalid or object garbage collected',
      );
    }

    return (response.json!['result'] as Map).cast();
  }

  /// Calls [method] on the first isolate that has it registered.
  ///
  /// Throws an [RPCError] if no isolate has the extension registered.
  Future<Response> _callExtension(
    String method, {
    Map<String, dynamic>? args,
  }) async {
    final String isolateId = await _isolateIdForExtension(method);
    return _vmService.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args,
    );
  }

  /// Returns the isolate ID of the first isolate that has [extensionName]
  /// registered.
  ///
  /// Returns immediately from the cache when available. On a cache miss,
  /// performs a full scan via getVM()/getIsolate() and pre-populates the cache
  /// with every extension found, so subsequent calls are instant.
  Future<String> _isolateIdForExtension(String extensionName) async {
    final cached = _extensionToIsolateId[extensionName];
    if (cached != null) return cached;

    // Cache miss: scan all isolates and populate the cache fully.
    final VM vm = await _vmService.getVM();
    for (final IsolateRef ref in vm.isolates ?? []) {
      final Isolate isolate = await _vmService.getIsolate(ref.id!);
      for (final ext in isolate.extensionRPCs ?? []) {
        _extensionToIsolateId[ext] = ref.id!;
      }
    }

    final resolved = _extensionToIsolateId[extensionName];
    if (resolved != null) return resolved;

    throw rpcError(
      'No isolate found with extension: $extensionName',
      fromMethod: '_callExtension',
    );
  }
}

// ---------------------------------------------------------------------------
// Dart IIFE evaluated inside the running app to dump the semantics tree.
//
// Design constraints:
//   - No local named function declarations — some Dart VM evaluate
//     implementations do not support them. All logic is inlined.
//   - No '{' or '}' inside string literals — avoid potential brace-counting
//     bugs in simpler expression parsers. Error results use the prefix
//     "error:" and the data format uses JSON arrays ([]) not objects ({}).
//   - Evaluated in widget_inspector.dart library scope, which imports
//     package:flutter/rendering.dart and dart:ui so RendererBinding,
//     SemanticsNode, CheckedState, and Tristate are all in scope.
//
// Output: a flat JSON array of tuples, one per visible non-hidden node:
//   [[id, role, label, value, hint, checked, toggled, selected, enabled,
//     focused, actions, rectLeft, rectTop, rectRight, rectBottom], ...]
//
// Field indices (0-based):
//   0  id       int     — SemanticsNode.id (usable with performSemanticsAction)
//   1  role     String  — "button"|"textfield"|"slider"|"link"|"image"|
//                         "header"|"checkbox"|"toggle"|"radio"|""
//   2  label    String  — primary accessibility label
//   3  value    String  — current value (slider pos, text content, etc.)
//   4  hint     String  — hint text
//   5  checked  bool?   — null if not applicable
//   6  toggled  bool?   — null if not applicable (Switch)
//   7  selected bool?   — null if not applicable (Tab, ListItem)
//   8  enabled  bool?   — null if not applicable
//   9  focused  bool
//   10 actions  int     — SemanticsAction bitmask
//   11..14 rect doubles — left, top, right, bottom in local coordinates
//
// On error, returns the string "error:<message>".
// The expression must be a single line — the Dart VM evaluate endpoint does
// not support multi-line IIFE bodies. Named local functions and multi-line
// strings with { } characters also cause "Can't find '}' to match '{'" errors.
//
// Library scope: package:flutter/src/semantics/semantics.dart
// (SemanticsNode, SemanticsBinding, CheckedState, Tristate all in scope)
// RendererBinding is not in scope there, so we reach pipelineOwner via
// (SemanticsBinding.instance as dynamic).pipelineOwner.
const String _kSemanticsTreeExpression =
    r"""(() { final owner = (SemanticsBinding.instance as dynamic).pipelineOwner.semanticsOwner; if (owner == null) return 'error:semantics not enabled'; final root = owner.rootSemanticsNode; if (root == null) return 'error:semantics tree empty - retry after a frame renders'; final parts = []; final stack = [root]; while (stack.isNotEmpty) { final node = stack.removeLast(); if (node.isInvisible) continue; final d = node.getSemanticsData(); final f = d.flagsCollection; if (f.isHidden) continue; final r = node.rect; final role = f.isButton ? 'button' : f.isTextField ? 'textfield' : f.isSlider ? 'slider' : f.isLink ? 'link' : f.isImage ? 'image' : f.isHeader ? 'header' : f.isChecked != CheckedState.none ? 'checkbox' : f.isToggled != Tristate.none ? 'toggle' : f.isInMutuallyExclusiveGroup ? 'radio' : ''; final lb = '${node.label}'.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' '); final vl = '${node.value}'.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' '); final hn = '${node.hint}'.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', ' '); final checked = f.isChecked == CheckedState.none ? 'null' : f.isChecked == CheckedState.isTrue ? 'true' : 'false'; final toggled = f.isToggled == Tristate.none ? 'null' : f.isToggled == Tristate.isTrue ? 'true' : 'false'; final selected = f.isSelected == Tristate.none ? 'null' : f.isSelected == Tristate.isTrue ? 'true' : 'false'; final enabled = f.isEnabled == Tristate.none ? 'null' : f.isEnabled == Tristate.isTrue ? 'true' : 'false'; final focused = f.isFocused == Tristate.isTrue; parts.add('[${node.id},"$role","$lb","$vl","$hn",$checked,$toggled,$selected,$enabled,$focused,${d.actions},${r.left},${r.top},${r.right},${r.bottom}]'); if (!node.mergeAllDescendantsIntoThisNode) node.visitChildren((child) => (stack..add(child)).isNotEmpty); } return '[${parts.join(",")}]'; })()""";

RPCError rpcError(String message, {required String fromMethod}) =>
    RPCError(fromMethod, 0, message);
