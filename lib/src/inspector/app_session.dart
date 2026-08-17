import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../common.dart';
import '../utils.dart';
import 'diagnostics_node.dart';
import 'error_summarizers.dart';
import 'flutter_service_extensions.dart';

/// Manages a `flutter run --machine` subprocess.
///
/// Use [AppSession.start] to launch a Flutter app and obtain a session.
/// The session provides [events] for monitoring app lifecycle and output,
/// [restart] for hot reload/restart, [stop] to terminate the app, and
/// [serviceExtensions] for direct access to Flutter VM service extensions.
class AppSession {
  AppSession._(
    this._process,
    this._eventListener,
    this._sessionFinishedListener, {
    this.deviceId,
    required this.serverLog,
  }) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);

    // Listen for process exit.
    _process.exitCode.then(_handleDone);
  }

  final Process _process;
  String? _appId;

  /// The Flutter CLI executable name.
  ///
  /// On Windows the launcher is `flutter.bat`; a bare `'flutter'` spawn fails
  /// because `CreateProcess` only appends `.exe` to an extensionless name
  /// (PATHEXT is applied by `cmd.exe`, not the Win32 API), so it never resolves
  /// to `flutter.bat`.
  static final String _flutterExecutable =
      Platform.isWindows ? 'flutter.bat' : 'flutter';

  /// The 'flutter run' device ID that we launched on.
  final String? deviceId;

  final DebugLogger serverLog;

  // Used to time reload / restart operations.
  Stopwatch? reloadTimer;

  final Completer<void> _startedCompleter = Completer<void>();
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  final EventCallback _eventListener;
  final SessionFinishedCallback _sessionFinishedListener;
  bool _sessionEnded = false;

  String? _vmServiceUri;
  FlutterServiceExtensions? _serviceExtensions;
  StreamSubscription<Event>? _vmIsolateEventSubscription;
  StreamSubscription<Event>? _vmExtensionEventSubscription;

  // Output buffer — prefixed lines accumulated since the last drain or reload.
  final List<String> _outputBuffer = [];

  /// This will complete once the app has been launched successfully.
  Future<void> get started => _startedCompleter.future;

  /// Appends a prefixed line to the output buffer.
  void addOutput(String prefix, String line) {
    final pre = '[$prefix] ';
    line = line.trimRight();
    line = line.replaceAll('\n', '\n  ');
    _outputBuffer.addAll('$pre$line'.split('\n'));
  }

  /// Returns all buffered output lines and clears the buffer.
  List<String> drainOutput() {
    final lines = List<String>.from(_outputBuffer);
    _outputBuffer.clear();
    return lines;
  }

  /// Whether the slipstream_agent companion package is installed in the running
  /// app.
  ///
  /// Determined by calling `ext.slipstream.ping` after the VM service connects.
  /// False until the first ping completes, then stable until the next hot
  /// restart (after which it is re-determined automatically).
  bool get hasCompanion => _serviceExtensions?.companionVersion != null;

  /// The slipstream_agent companion version string (e.g. `"0.1.0"`), or null
  /// if the companion is not installed.
  String? get companionVersion => _serviceExtensions?.companionVersion;

  /// Access to Flutter VM service extensions for this session.
  ///
  /// Available once the app has started and the VM service has connected
  /// (i.e. after [start] returns). Null if the VM service has not yet
  /// connected or has been disposed.
  FlutterServiceExtensions? get serviceExtensions => _serviceExtensions;

  /// Launches `flutter run --machine` in [workingDirectory].
  ///
  /// When [deviceId] is omitted, auto-selects the best available device
  /// (preferring desktop, then simulators/emulators, then physical devices).
  ///
  /// Throws a [DaemonException] if the process exits before the app starts
  /// or if no suitable device can be found.
  static Future<AppSession> start({
    required String workingDirectory,
    required EventCallback eventListener,
    required SessionFinishedCallback sessionFinishedListener,
    String? deviceId,
    String? target,
    required DebugLogger serverLog,
  }) async {
    deviceId ??= await _autoSelectDevice(workingDirectory);

    final List<String> args = [
      'run',
      '--machine',
      if (deviceId != null) ...['--device-id', deviceId],
      if (target != null) ...['--target', target],
    ];

    final Process process = await Process.start(
      _flutterExecutable,
      args,
      workingDirectory: workingDirectory,
    );

    final AppSession session = AppSession._(
      process,
      eventListener,
      sessionFinishedListener,
      deviceId: deviceId,
      serverLog: serverLog,
    );
    return session;
  }

  /// Runs `flutter devices --machine` and returns the best device ID for the
  /// given project, or null if no devices are found.
  ///
  /// Preference order: desktop (host OS) > iOS Simulator > Android emulator >
  /// physical device. Web and cross-compile desktop are skipped. Each candidate
  /// is checked for platform support (e.g. a `macos/` folder must exist).
  static Future<String?> _autoSelectDevice(String workingDirectory) async {
    final List<Map<String, dynamic>> devices;
    try {
      devices = await _getDevices();
    } on DaemonException {
      // Fail open — let `flutter run` pick a device itself.
      return null;
    }

    if (devices.isEmpty) return null;

    // Map targetPlatform (from `flutter devices --machine`) to the project
    // platform folder name. Note: devices report 'darwin' but the folder and
    // `flutter create --platforms=` flag use 'macos'.
    const Map<String, String> platformFolders = {
      'darwin': 'macos',
      'linux': 'linux',
      'windows': 'windows',
      'android': 'android',
      'ios': 'ios',
      'web-javascript': 'web',
    };

    bool projectSupports(String targetPlatform) {
      final String? folder = platformFolders[targetPlatform];
      if (folder == null) {
        // Unknown platform — don't filter.
        return true;
      }
      return Directory(path.join(workingDirectory, folder)).existsSync();
    }

    final String hostPlatform = _hostTargetPlatform();

    // Score each device: lower is better. Null means skip entirely.
    int? devicePriority(Map<String, dynamic> device) {
      final String target = device['targetPlatform'] as String? ?? '';
      final bool isEmulator = device['emulator'] as bool? ?? false;

      // Desktop matching host OS.
      if (target == hostPlatform) return 0;

      // iOS Simulator (running).
      if (target == 'ios' && isEmulator) return 1;

      // Android emulator (running).
      if (target == 'android' && isEmulator) return 2;

      // Physical mobile device.
      if (target == 'ios' || target == 'android') return 3;

      // Skip cross-compile desktop (e.g. linux on macOS) — unlikely to work.
      if (target == 'darwin' || target == 'linux' || target == 'windows') {
        return null;
      }

      // Skip web — inspector and evaluate don't work the same way.
      if (target == 'web-javascript') return null;

      return 4;
    }

    // Filter to supported, non-skipped devices and sort by priority.
    final List<Map<String, dynamic>> candidates =
        devices
            .where(
              (d) =>
                  projectSupports(d['targetPlatform'] as String? ?? '') &&
                  devicePriority(d) != null,
            )
            .toList()
          ..sort((a, b) => devicePriority(a)!.compareTo(devicePriority(b)!));

    if (candidates.isEmpty) {
      final String deviceList = devices
          .map(
            (d) =>
                '  - ${d['name']} (${d['id']}, '
                'platform: ${d['targetPlatform']})',
          )
          .join('\n');
      final String hostPlatformName = _hostPlatformName();
      throw DaemonException(
        'No device matches this project\'s enabled platforms.\n\n'
        'Available devices:\n$deviceList\n\n'
        'To enable desktop, run: '
        'flutter create --platforms=$hostPlatformName .',
      );
    }

    final String selectedId = candidates.first['id'] as String;
    return selectedId;
  }

  /// Returns the `targetPlatform` string for the host OS.
  static String _hostTargetPlatform() {
    if (Platform.isMacOS) return 'darwin';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return '';
  }

  /// Returns the Flutter platform name for the host OS (used in
  /// `flutter create --platforms=`).
  static String _hostPlatformName() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'macos';
  }

  /// Runs `flutter devices --machine` and returns the parsed JSON list.
  static Future<List<Map<String, dynamic>>> _getDevices() async {
    final ProcessResult result = await Process.run(_flutterExecutable, [
      'devices',
      '--machine',
    ]);

    if (result.exitCode != 0) {
      throw DaemonException(
        'flutter devices failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }

    final String stdout = result.stdout as String;

    // `flutter devices --machine` may emit non-JSON lines before the JSON
    // array (e.g. "Waiting for another flutter command..."). Find the array.
    final int jsonStart = stdout.indexOf('[');
    if (jsonStart == -1) {
      throw DaemonException('flutter devices returned no JSON output.');
    }

    final Object? decoded = jsonTryParse(stdout.substring(jsonStart));
    if (decoded is! List) {
      throw DaemonException('flutter devices returned unexpected output.');
    }

    return decoded.cast<Map<String, dynamic>>();
  }

  /// Hot reloads the app. If [fullRestart] is true, performs a hot restart
  /// instead.
  ///
  /// Throws a [DaemonException] if there were issues performing the restart.
  Future<void> restart({bool fullRestart = false}) async {
    _outputBuffer.clear();

    final String appId = _appId!;
    final Map<String, dynamic> result = await _sendCommand('app.restart', {
      'appId': appId,
      'fullRestart': fullRestart,
    });
    final int code = (result['code'] as num?)?.toInt() ?? 0;
    if (code != 0) {
      final String message = result['message'] as String? ?? 'unknown error';
      throw DaemonException('app.restart failed (code $code): $message');
    }
  }

  /// Stops the running app.
  Future<void> stop() async {
    await _sendCommand('app.stop', {'appId': _appId!});
  }

  /// Takes a screenshot of the root widget, returning base64-encoded PNG data.
  ///
  /// The root widget's object id and size are resolved automatically.
  /// Size is obtained via VM service `evaluate` (exact physical pixels);
  /// falls back to the inspector details subtree if that fails.
  /// [maxPixelRatio] scales the output resolution.
  ///
  /// Throws an [RPCError] if there are issues taking the screenshot.
  Future<String> takeScreenshot({double? maxPixelRatio}) async {
    final FlutterServiceExtensions extensions = _serviceExtensions!;

    // getRootWidget returns full detail including valueId — the inspector
    // object handle required by the screenshot extension.
    final DiagnosticsNode rootNode = await extensions.getRootWidget();
    final String? rootId = rootNode.valueId;
    if (rootId == null) {
      throw rpcError(
        'getRootWidget did not return a valueId',
        fromMethod: 'take_screenshot',
      );
    }

    var size = await extensions.getPhysicalWindowSize();
    if (size == null) {
      throw rpcError(
        'Could not determine widget size for screenshot',
        fromMethod: 'take_screenshot',
      );
    }

    final String? base64Data = await extensions.screenshot(
      id: rootId,
      width: size.$1,
      height: size.$2,
      maxPixelRatio: maxPixelRatio,
    );
    if (base64Data == null) {
      throw rpcError(
        'Screenshot returned null — widget may not be on screen',
        fromMethod: 'take_screenshot',
      );
    }
    return base64Data;
  }

  Future<Map<String, dynamic>> _sendCommand(
    String method,
    Map<String, dynamic> params,
  ) {
    final int id = _nextId++;
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final String message =
        '[${jsonEncode({'id': id, 'method': method, 'params': params})}]';
    _process.stdin.writeln(message);
    return completer.future;
  }

  void _handleLine(String line) {
    // Daemon messages are wrapped in [ ... ].
    final String trimmed = line.trimRight();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      // Convert regular stdio output to log messages.
      if (!_sessionEnded) {
        _eventListener(AppEvent('app.log', {'appId': _appId, 'log': trimmed}));
      }
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return;
    }

    if (decoded is! List || decoded.isEmpty) return;
    final Object? msg = decoded.first;
    if (msg is! Map<String, dynamic>) return;

    if (msg.containsKey('id')) {
      // Response to a command we sent.
      final int id = msg['id'] as int;
      final Completer<Map<String, dynamic>>? completer = _pending.remove(id);
      if (completer != null) {
        final Object? error = msg['error'];
        if (error != null) {
          final String errorMsg =
              error is Map
                  ? (error['message'] as String? ?? '$error')
                  : '$error';
          completer.completeError(DaemonException(errorMsg));
        } else {
          final Object? result = msg['result'];
          completer.complete(
            result is Map<String, dynamic> ? result : <String, dynamic>{},
          );
        }
      }
    } else if (msg.containsKey('event')) {
      // Unsolicited event from the daemon.
      final String event = msg['event'] as String;
      final Map<String, dynamic> params =
          (msg['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      if (event == 'app.start') {
        _appId = params['appId'] as String?;
      } else if (event == 'app.started') {
        if (!_startedCompleter.isCompleted) {
          _startedCompleter.complete();
        }
      } else if (event == 'app.debugPort') {
        _vmServiceUri = params['wsUri'] as String?;
        _connectVmService(_vmServiceUri!);
      } else if (event == 'app.devTools') {
        // _devToolsUri = params['uri'] as String?;
      } else if (event == 'app.dtd') {
        // _dtdToolsUri = params['uri'] as String?;
      } else if (event == 'app.progress') {
        // {id: '2', progressId: 'hot.reload', finished: true}
        final progressId = params['progressId'] as String? ?? '';
        final finished = params['finished'] == true;

        if (finished && progressId == 'hot.reload') {
          final duration = reloadTimer?.elapsed;
          reloadTimer = null;

          if (hasCompanion) {
            serviceExtensions?.slipstreamLog(
              'reload',
              kind: 'reload',
              details: describeShortDuration(duration),
            );
          }
        } else if (finished && progressId == 'hot.restart') {
          // Stop the timer now. The companion agent hasn't had a chance to boot
          // up and register its 'ping' or 'log' extensions. Wait until we see
          // an extension registragion go by for them, then send a
          // slipstreamLog('restart') message.
          reloadTimer?.stop();
        }
      }

      if (!_sessionEnded) {
        _eventListener(AppEvent(event, params));
      }
    }
  }

  // Perform the second half of a hot restart notification. We've already
  // stopped the timer, and we're only called here after the companion agent
  // has become available.
  void _checkHotRestartTimer() {
    if (reloadTimer == null) return;

    final duration = reloadTimer!.elapsed;
    reloadTimer = null;

    serviceExtensions?.slipstreamLog(
      'restart',
      kind: 'reload',
      details: describeShortDuration(duration),
    );
  }

  Future<void> _connectVmService(String wsUri) async {
    final vmService = await vmServiceConnectUri(wsUri);

    _serviceExtensions = FlutterServiceExtensions(vmService);

    // Bootstrap semantics on initial connect. Best-effort — app.started has
    // fired by the time _connectVmService is called, so the Flutter binding
    // is initialized. The app.progress/hot.restart handler below re-bootstraps
    // after every full restart.
    _serviceExtensions!.bootstrapSemantics().ignore();

    // Detect companion package. Best-effort — fails open if not installed.
    _pingCompanion();

    // Isolate events
    vmService.streamListen(EventStreams.kIsolate).ignore();
    _vmIsolateEventSubscription = vmService.onIsolateEvent.listen((
      Event event,
    ) {
      if (event.kind == EventKind.kServiceExtensionAdded) {
        final rpcName = event.extensionRPC;
        if (rpcName == 'ext.slipstream.ping') {
          _pingCompanion(ifAvailable: _checkHotRestartTimer);
        }
      }
    });

    // Extension events
    vmService.streamListen(EventStreams.kExtension).ignore();
    _vmExtensionEventSubscription = vmService.onExtensionEvent.listen((
      Event event,
    ) {
      if (event.extensionKind == 'Flutter.Error') {
        final data = event.extensionData?.data;
        if (data != null) {
          final error = FlutterError.tryParse(data);
          if (error != null) {
            _eventListener(
              AppEvent('flutter.error', {'summary': compactSummarizer(error)}),
            );
          }
        }
      } else if (event.extensionKind == 'ext.slipstream.routeChanged') {
        final data = event.extensionData?.data;
        final String? path = data?['path'] as String?;
        if (path != null) {
          _eventListener(AppEvent('slipstream.routeChanged', {'path': path}));
        }
      } else if (event.extensionKind == 'ext.slipstream.windowResized') {
        final data = event.extensionData?.data;
        if (data != null) {
          _eventListener(AppEvent('slipstream.windowResized', Map.of(data)));
        }
      } else if (event.extensionKind == 'Flutter.FrameworkInitialization') {
        // This happens early after a full restart.
      } else if (event.extensionKind == 'Flutter.FirstFrame') {
        // This is the last event we receive after a full restart.

        // Re-bootstrap semantics and re-detect companion after hot restart.
        _serviceExtensions?.bootstrapSemantics().ignore();
        _pingCompanion();
      }
    });
  }

  /// Calls [FlutterServiceExtensions.pingCompanion] and stores the result.
  /// Best-effort — called on initial connect and after each hot restart.
  void _pingCompanion({Function? ifAvailable}) {
    _serviceExtensions?.pingCompanion().then((version) {
      if (ifAvailable != null) {
        ifAvailable();
      }
    });
  }

  void _handleDone(int exitCode) {
    // Process stdout closed — the subprocess exited.
    if (!_startedCompleter.isCompleted) {
      _startedCompleter.completeError(
        DaemonException(
          'flutter run exited before app started (exit code $exitCode).',
        ),
      );
    }
    for (final Completer<Map<String, dynamic>> c in _pending.values) {
      c.completeError(DaemonException('flutter run process exited'));
    }
    _pending.clear();

    // If the app was running and we didn't initiate the stop ourselves,
    // emit a synthetic app.stop so the server can clean up the session.
    if (!_sessionEnded && _appId != null) {
      _eventListener(AppEvent('app.stop', {'appId': _appId}));
    }

    _sessionEnded = true;
    _sessionFinishedListener(this);

    _vmIsolateEventSubscription?.cancel();
    _vmIsolateEventSubscription = null;
    _vmExtensionEventSubscription?.cancel();
    _vmExtensionEventSubscription = null;
    _serviceExtensions?.dispose();
    _serviceExtensions = null;
  }
}

/// An event emitted by the running Flutter app.
///
/// These are either events directly from the `flutter run --machine` daemon
/// protocol or semantic events from the VM service protocol.
class AppEvent {
  final String event;
  final Map<String, dynamic> params;

  AppEvent(this.event, this.params);
}

/// An error returned from a command sent to 'flutter run' over the daemon
/// protocol.
class DaemonException implements Exception {
  final String message;

  DaemonException(this.message);

  @override
  String toString() => 'DaemonException: $message';
}

/// A Flutter framework error received via the `Flutter.Error` VM service
/// extension event.
class FlutterError {
  FlutterError({required this.node, required this.errorsSinceReload});

  /// The full diagnostic node tree for this error. The root [node.description]
  /// is the generic category (e.g., "Exception caught by rendering library").
  /// The specific error message is the `ErrorSummary` property (level ==
  /// `'summary'`), e.g. "A RenderFlex overflowed by 900 pixels on the bottom".
  final DiagnosticsNode node;

  /// The cumulative error count since the last hot reload, as reported by the
  /// framework (`errorsSinceReload` field).
  final int errorsSinceReload;

  /// Short category label, e.g. "Exception caught by rendering library".
  String get description => node.description;

  /// The specific error message from the `ErrorSummary` property (level ==
  /// `'summary'`), if present. Falls back to [description] otherwise.
  String get detail {
    for (final prop in node.properties) {
      if (prop.level == 'summary' && prop.description.isNotEmpty) {
        return prop.description;
      }
    }
    return description;
  }

  /// A single-line summary combining [description] and [detail].
  String get summary {
    final d = detail;
    return d == description ? description : '$description ▸ $d';
  }

  /// Parses a [FlutterError] from [data], the `extensionData.data` map of a
  /// `Flutter.Error` VM service event. Returns null if the required fields are
  /// absent.
  static FlutterError? tryParse(Map<String, dynamic> data) {
    if (data['description'] == null) return null;
    final int errorsSinceReload =
        (data['errorsSinceReload'] as num?)?.toInt() ?? 0;
    return FlutterError(
      node: DiagnosticsNode.fromJson(data),
      errorsSinceReload: errorsSinceReload,
    );
  }

  @override
  String toString() => 'FlutterError: $summary';
}

typedef EventCallback = void Function(AppEvent);

typedef SessionFinishedCallback = void Function(AppSession);
