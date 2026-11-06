import 'dart:io';

import 'package:dart_mcp/server.dart';

import '../../common.dart';
import '../app_session.dart';
import '../tool_context.dart';

/// Implements the `run_app` MCP tool.
///
/// Builds and launches a Flutter app. If an app is already running it is
/// stopped first — only one session is active at a time.
class RunAppTool extends InspectorTool {
  RunAppTool({required this.eventListener});

  /// Called to forward daemon events from the session to the server.
  final void Function(AppEvent event) eventListener;

  @override
  final Tool definition = Tool(
    name: 'run_app',
    description:
        'Builds and launches the Flutter app. Call this first before '
        'inspecting, screenshotting, or evaluating. If an app is already '
        'running it is stopped and replaced. Call get_output after run_app '
        'to see initial app output and any startup errors.',
    inputSchema: Schema.object(
      properties: {
        'working_directory': Schema.string(
          description:
              'The Flutter project directory to launch.\n\n'
              'Note that this should be an absolute path.',
        ),
        'target': Schema.string(
          description:
              'The main entry point to launch (e.g. lib/main.dart). '
              'Defaults to the project default.',
        ),
        'device': Schema.string(
          description:
              'Optional device ID override. When omitted, auto-selects the '
              'best available device (prefers desktop for fast builds). Only '
              'pass this if the user requests a specific device.',
        ),
        'flavor': Schema.string(
          description:
              'Optional build flavor (passed as --flavor). Required for '
              'projects whose iOS/Android targets define flavor schemes.',
        ),
      },
      required: ['working_directory'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    context.validateParams(request, definition.inputSchema.required!);

    final Map<String, dynamic> args = request.arguments!;
    final String workingDirectory = args['working_directory'] as String;
    final String? device = args['device'] as String?;
    final String? target = args['target'] as String?;
    final String? flavor = args['flavor'] as String?;

    final dir = Directory(workingDirectory);
    if (!dir.isAbsolute) {
      throw ToolException("working_directory should be an absolute path.");
    }

    final previousSession = context.removeSession();
    if (previousSession != null) {
      await previousSession.stop().timeout(
        Duration(milliseconds: 250),
        onTimeout: () => null,
      );
    }

    final AppSession session;
    try {
      session = await AppSession.start(
        workingDirectory: workingDirectory,
        eventListener: eventListener,
        sessionFinishedListener: context.handleSessionClosed,
        deviceId: device,
        target: target,
        flavor: flavor,
        serverLog: context.log,
      );
    } catch (e) {
      final msg = e is DaemonException ? e.message : '$e';
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'failed to start app: $msg')],
      );
    }

    context.setSession(session);

    try {
      // We're starting the app, but wait for full startup.
      await session.started;

      final String deviceInfo =
          session.deviceId != null ? " device ID: '${session.deviceId}'" : '';
      final String replaced =
          previousSession != null ? '; previous app was stopped' : '';

      final output = session.drainOutput();

      return CallToolResult(
        content: [
          TextContent(text: 'Launched!$deviceInfo$replaced'),
          if (output.isNotEmpty) TextContent(text: output.join('\n')),
        ],
      );
    } catch (e) {
      final output = session.drainOutput();
      final msg = e is DaemonException ? e.message : '$e';
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'failed to start app: $msg'),
          if (output.isNotEmpty) TextContent(text: output.join('\n')),
        ],
      );
    }
  }
}
