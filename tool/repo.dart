import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_mcp/client.dart';
import 'package:flutter_slipstream/src/inspector/inspector_mcp.dart';
import 'package:flutter_slipstream/src/shorthand/packages_mcp.dart';
import 'package:path/path.dart' as path;
import 'package:stream_channel/stream_channel.dart';

/// Repository maintenance tool for flutter-slipstream.
///
/// Usage:
///   dart run tool/repo.dart `<command>` [options]
///
/// Commands:
///   check   Validate version consistency across manifests and CHANGELOG.md.
void main(List<String> args) async {
  final runner =
      CommandRunner<void>('repo', 'Repository tools for flutter-slipstream.')
        ..addCommand(CheckCommand())
        ..addCommand(ValidateManifestsCommand())
        ..addCommand(GenerateDocsCommand())
        ..addCommand(ExtractChangelogCommand())
        ..addCommand(BumpVersionCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    exit(1);
  }
}

final String claudeManifest = '.claude-plugin/plugin.json';
final String cursorManifest = '.cursor-plugin/plugin.json';
final String copilotManifest = '.github/plugin/plugin.json';

/// All plugin manifests whose versions are kept in sync.
final List<String> manifests = [
  claudeManifest,
  cursorManifest,
  copilotManifest,
];

// ---------------------------------------------------------------------------

class CheckCommand extends Command<void> {
  @override
  String get name => 'check-versions';

  @override
  String get description =>
      'Validate version consistency across the plugin manifests and '
      'CHANGELOG.md.';

  @override
  Future<void> run() async {
    final errors = <String>[];

    final Map<String, String?> versions = {
      for (final m in manifests) m: _readJsonVersion(m, errors),
    };
    final String? claudeVersion = versions[claudeManifest];
    final changelogVersions = _readChangelogVersions('CHANGELOG.md', errors);

    if (errors.isNotEmpty) {
      for (final e in errors) {
        stderr.writeln('error: $e');
      }
      exit(1);
    }

    var failed = false;

    // Versions in the manifest files must match.
    if (versions.values.toSet().length != 1) {
      stderr.writeln(
        'error: version mismatch; '
        '${versions.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
      );
      failed = true;
    }

    // The plugin version must appear as the first or second changelog entry.
    // During development the first entry is a "-wip" section; on release it
    // becomes the first entry.
    final window = changelogVersions.take(2).toList();
    if (!window.contains(claudeVersion)) {
      stderr.writeln(
        'error: plugin version $claudeVersion not found in the first two '
        'CHANGELOG.md entries (found: ${window.join(', ')})',
      );
      failed = true;
    }

    if (failed) exit(1);

    print(
      'ok — version $claudeVersion is consistent across '
      '${manifests.join(', ')}, and CHANGELOG.md',
    );
  }
}

// ---------------------------------------------------------------------------

class ValidateManifestsCommand extends Command<void> {
  static const _manifestKeys = [
    'name',
    'version',
    'description',
    'repository',
    'license',
    'keywords',
    'mcpServers',
  ];

  @override
  String get name => 'validate-manifests';

  @override
  String get description =>
      'Validate that plugin manifests are well-formed and contain required fields.';

  @override
  void run() {
    var failed = false;

    // Validate the plugin manifests.
    for (final m in manifests) {
      failed |= _validateJson(m, _manifestKeys);
    }
    failed |= _validateClaudeServerCommands(claudeManifest);

    if (failed) exit(1);
    print('ok — all manifests are valid');
  }

  /// Claude Code spawns `command` as an executable; inline arguments belong in
  /// `args`. A command string with arguments fails at spawn time with ENOENT.
  bool _validateClaudeServerCommands(String filePath) {
    final json =
        jsonDecode(File(filePath).readAsStringSync()) as Map<String, dynamic>;
    final servers = json['mcpServers'] as Map<String, dynamic>? ?? const {};
    var failed = false;
    for (final entry in servers.entries) {
      final server = entry.value as Map<String, dynamic>;
      final command = server['command'] as String? ?? '';
      final args = server['args'] as List<dynamic>? ?? const [];
      if (args.isEmpty && command.contains(' ')) {
        stderr.writeln(
          'error: $filePath: mcpServers.${entry.key}.command contains inline '
          'arguments; move them into "args"',
        );
        failed = true;
      }
    }
    return failed;
  }

  bool _validateJson(String filePath, List<String> requiredKeys) {
    final file = File(filePath);
    if (!file.existsSync()) {
      stderr.writeln('error: $filePath not found');
      return true;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      stderr.writeln('error: $filePath: invalid JSON — $e');
      return true;
    }

    final missing = requiredKeys.where((k) => !json.containsKey(k)).toList();
    if (missing.isNotEmpty) {
      stderr.writeln('error: $filePath: missing fields: ${missing.join(', ')}');
      return true;
    }

    return false;
  }
}

// ---------------------------------------------------------------------------

class ExtractChangelogCommand extends Command<void> {
  @override
  String get name => 'extract-changelog';

  @override
  String get description =>
      'Print the CHANGELOG.md section for a given version to stdout.';

  @override
  String get invocation =>
      '${runner!.executableName} extract-changelog <version>';

  @override
  void run() {
    final String version;
    if (argResults!.rest.isEmpty) {
      final errors = <String>[];
      final changelogVersions = _readChangelogVersions('CHANGELOG.md', errors);
      if (errors.isNotEmpty) {
        for (final e in errors) {
          stderr.writeln('error: $e');
        }
        exit(1);
      }
      version = changelogVersions.first;
    } else {
      version = argResults!.rest.first;
    }

    final file = File('CHANGELOG.md');
    if (!file.existsSync()) {
      stderr.writeln('error: CHANGELOG.md not found');
      exit(1);
    }

    final lines = file.readAsLinesSync();
    final heading = '## $version';

    // Find the start of the requested section.
    final start = lines.indexWhere((l) => l.trim() == heading);
    if (start == -1) {
      stderr.writeln('error: no changelog section found for version $version');
      exit(1);
    }

    // Collect lines until the next ## heading.
    final body = StringBuffer();
    for (var i = start + 1; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) break;
      body.writeln(lines[i]);
    }

    print(body.toString().trim());
  }
}

// ---------------------------------------------------------------------------

class BumpVersionCommand extends Command<void> {
  @override
  String get name => 'bump-version';

  @override
  String get description =>
      'Bump the release version in the plugin manifests and CHANGELOG.md. '
      'Defaults to the current -wip version.';

  @override
  String get invocation => '${runner!.executableName} bump-version [<version>]';

  @override
  void run() {
    final String version;

    if (argResults!.rest.isEmpty) {
      // Derive from the first changelog entry, which must end in '-wip'.
      final errors = <String>[];
      final entries = _readChangelogVersions('CHANGELOG.md', errors);
      if (errors.isNotEmpty) {
        for (final e in errors) {
          stderr.writeln('error: $e');
        }
        exit(1);
      }
      final first = entries.first;
      if (!first.endsWith('-wip')) {
        stderr.writeln(
          'error: first CHANGELOG.md entry is "$first", which does not end '
          'in "-wip". Pass an explicit version or add a -wip section.',
        );
        exit(1);
      }
      version = first.substring(0, first.length - '-wip'.length);
    } else {
      version = argResults!.rest.first;
    }

    for (final m in manifests) {
      _bumpJsonVersion(m, version);
    }

    // Rename the -wip heading in CHANGELOG.md.
    _bumpChangelog('CHANGELOG.md', version);

    // Confirm and show what will be released.
    print('Bumped to v$version.');
    print('');
    print('Changelog for v$version:');
    print('');

    // Re-use extract logic: find and print the section.
    final lines = File('CHANGELOG.md').readAsLinesSync();
    final start = lines.indexWhere((l) => l.trim() == '## $version');
    final body = StringBuffer();
    for (var i = start + 1; i < lines.length; i++) {
      if (lines[i].startsWith('## ')) break;
      body.writeln(lines[i]);
    }
    print(body.toString().trim());
    print('');
    print(
      'Note that merging a PR with these changes will trigger a release of v$version.',
    );
  }

  void _bumpJsonVersion(String filePath, String version) {
    final file = File(filePath);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      stderr.writeln('error: $filePath: invalid JSON — $e');
      exit(1);
    }
    json['version'] = version;
    // Preserve a trailing newline.
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
    print('  updated $filePath');
  }

  void _bumpChangelog(String filePath, String version) {
    final file = File(filePath);
    final original = file.readAsStringSync();
    // Replace the first occurrence of a -wip heading with the release version.
    final updated = original.replaceFirst(
      RegExp(r'^## .+-wip$', multiLine: true),
      '## $version',
    );
    if (updated == original) {
      stderr.writeln(
        'warning: no -wip heading found in $filePath; changelog not updated',
      );
      return;
    }
    file.writeAsStringSync(updated);
    print('  updated $filePath');
  }
}

// ---------------------------------------------------------------------------

class GenerateDocsCommand extends Command<void> {
  @override
  String get name => 'generate-docs';

  @override
  String get description =>
      'Generate MCP command tables in README.md and docs/slipstream_doc.md.';

  @override
  Future<void> run() async {
    final docFile = File(path.join('docs', 'slipstream_doc.md'));
    final buf = StringBuffer();
    buf.writeln('# Flutter Slipstream');
    buf.writeln();
    buf.writeln(
      "Generated documentation on Slipstream's MCP servers, and their "
      'instructions and tools.',
    );
    buf.writeln();

    // packages server
    var (initializeResult, tools) = await _listTools(PackagesMCPServer.new);
    var serverInfo = initializeResult.serverInfo;
    await _updateReadmeSection(
      marker: '<!-- ${serverInfo.name} -->',
      tools: tools,
    );
    _writeServerDocs(buf, initializeResult, tools);

    // inspector server
    (initializeResult, tools) = await _listTools(InspectorMCPServer.new);
    serverInfo = initializeResult.serverInfo;
    await _updateReadmeSection(
      marker: '<!-- ${serverInfo.name} -->',
      tools: tools,
    );
    _writeServerDocs(buf, initializeResult, tools);

    // TODO: Delete this path, or, have a CLI flag to emit it to stdout.
    // ignore: dead_code
    if (false) {
      docFile.writeAsStringSync(buf.toString());
      print('README.md, ${docFile.path} updated.');
      Process.runSync('npx', ['prettier', '--write', 'docs/slipstream_doc.md']);
    }

    // After generation, as a best effort, run the prettier npm tool.
    final result = Process.runSync('npx', ['prettier', '--write', 'README.md']);
    print('npx prettier: ${result.exitCode}');
    if (result.exitCode != 0) {
      print(result.stdout);
      print(result.stderr);
    }
  }

  void _writeServerDocs(
    StringBuffer buf,
    InitializeResult initializeResult,
    List<Tool> tools,
  ) {
    final server = initializeResult.serverInfo;
    buf.writeln('## `${server.name}` server');
    buf.writeln();
    buf.writeln(initializeResult.instructions);

    for (final tool in tools) {
      buf.writeln();
      buf.writeln('### `${server.name}:${tool.name}`');
      buf.writeln();
      buf.writeln('```');
      buf.writeln(_toolSig(tool));
      buf.writeln('```');
      buf.writeln();
      buf.writeln(tool.description);

      buf.writeln();
      final inputSchema = tool.inputSchema;
      for (final param in inputSchema.properties!.keys) {
        final schema = inputSchema.properties![param]!;
        final required = inputSchema.required!.contains(param);
        final requiredDesc = required ? ' (required) ' : '';
        buf.writeln('- `$param`: $requiredDesc${schema.description}');
      }
    }
  }

  String _toolSig(Tool tool) {
    final inputSchema = tool.inputSchema;
    final buf = StringBuffer();
    var hasOptional = false;
    var isFirst = true;
    buf.write('${tool.name}(');
    for (final param in inputSchema.properties!.keys) {
      final required = inputSchema.required!.contains(param);
      if (!isFirst) buf.write(', ');
      isFirst = false;
      if (!required && !hasOptional) {
        buf.write('[');
        hasOptional = true;
      }
      buf.write(param);
    }
    if (hasOptional) buf.write(']');
    buf.write(')');
    return buf.toString();
  }

  Future<void> _updateReadmeSection({
    required String marker,
    required List<Tool> tools,
  }) async {
    final buf = StringBuffer();
    buf.writeln('<!-- prettier-ignore-start -->');
    buf.writeln('| Command | Description |');
    buf.writeln('|---------|-------------|');
    for (final tool in tools) {
      final desc = tool.description ?? '';
      final period = desc.indexOf('.');
      final summary = period >= 0 ? desc.substring(0, period + 1) : desc;
      buf.writeln('| `${tool.name}` | $summary |');
    }
    buf.writeln('<!-- prettier-ignore-end -->');

    final readme = File('README.md');
    final original = readme.readAsStringSync();
    final start = original.indexOf(marker);
    final end = original.indexOf(marker, start + marker.length);

    if (start == -1 || end == -1) {
      stderr.writeln('Could not find $marker markers in README.md');
      exitCode = 1;
      return;
    }

    final updated =
        '${original.substring(0, start + marker.length)}\n'
        '${buf.toString()}'
        '${original.substring(end)}';
    readme.writeAsStringSync(updated);
  }

  Future<(InitializeResult, List<Tool>)> _listTools(
    Function(StreamChannel<String>) serverFactory,
  ) async {
    final clientController = StreamController<String>();
    final serverController = StreamController<String>();

    final clientChannel = StreamChannel<String>.withCloseGuarantee(
      serverController.stream,
      clientController.sink,
    );
    final serverChannel = StreamChannel<String>.withCloseGuarantee(
      clientController.stream,
      serverController.sink,
    );

    final server = serverFactory(serverChannel);
    final client = _ScriptClient();
    final connection = client.connectServer(clientChannel);

    final initializeResult = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized(InitializedNotification());
    await server.initialized;

    final toolsResult = await connection.listTools(ListToolsRequest());

    await client.shutdown();
    await server.shutdown();

    return (initializeResult, toolsResult.tools);
  }
}

base class _ScriptClient extends MCPClient {
  _ScriptClient() : super(Implementation(name: 'readme-gen', version: '0.1.0'));
}

// ---------------------------------------------------------------------------
// Helpers

/// Reads the `version` field from a JSON manifest file.
String? _readJsonVersion(String filePath, List<String> errors) {
  final file = File(filePath);
  if (!file.existsSync()) {
    errors.add('$filePath not found');
    return null;
  }
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final version = json['version'] as String?;
    if (version == null) {
      errors.add('$filePath: missing "version" field');
    }
    return version;
  } on FormatException catch (e) {
    errors.add('$filePath: invalid JSON — $e');
    return null;
  }
}

/// Extracts the ordered list of version strings from `## X.Y.Z` headings in
/// the changelog.
List<String> _readChangelogVersions(String filePath, List<String> errors) {
  final file = File(filePath);
  if (!file.existsSync()) {
    errors.add('$filePath not found');
    return const [];
  }

  final versions = <String>[];
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('## ')) {
      versions.add(line.substring(3).trim());
    }
  }

  if (versions.isEmpty) {
    errors.add('$filePath: no version headings (## X.Y.Z) found');
  }

  return versions;
}
