// Launches each MCP server exactly as the plugin manifests declare it, from a
// fresh copy of the plugin (no .dart_tool/) and a different working directory.
// This mirrors a first run after a marketplace install.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support.dart';

const Map<String, String> _manifests = {
  '.claude-plugin/plugin.json': r'${CLAUDE_PLUGIN_ROOT}',
  '.github/plugin/plugin.json': r'${PLUGIN_ROOT}',
};

void main() {
  late Directory pluginRoot;
  late Directory projectDir;

  setUpAll(() async {
    final Directory temp = await Directory.systemTemp.createTemp('slipstream');
    pluginRoot = Directory(path.join(temp.path, 'plugin'))..createSync();
    projectDir = Directory(path.join(temp.path, 'project'))..createSync();

    for (final String name in ['bin', 'lib']) {
      _copyDir(Directory(name), Directory(path.join(pluginRoot.path, name)));
    }
    for (final String name in ['pubspec.yaml', 'pubspec.lock']) {
      File(name).copySync(path.join(pluginRoot.path, name));
    }
  });

  tearDownAll(() async {
    await pluginRoot.parent.delete(recursive: true);
  });

  for (final MapEntry(key: manifest, value: rootVar) in _manifests.entries) {
    final Map<String, dynamic> json =
        jsonDecode(File(manifest).readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> servers =
        json['mcpServers'] as Map<String, dynamic>;

    group(manifest, () {
      for (final MapEntry(key: name, value: server) in servers.entries) {
        test('$name starts from a fresh install', () async {
          final Map<String, dynamic> config = server as Map<String, dynamic>;
          final List<String> args = [
            for (final Object? arg in config['args'] as List)
              (arg as String).replaceAll(rootVar, pluginRoot.path),
          ];

          final Process process = await Process.start(
            config['command'] as String,
            args,
            workingDirectory: projectDir.path,
            runInShell: Platform.isWindows,
          );
          addTearDown(process.kill);
          final StringBuffer stderrText = StringBuffer();
          process.stderr.transform(utf8.decoder).listen(stderrText.write);

          final List<String> tools;
          try {
            tools = await listMcpTools(
              process,
            ).timeout(const Duration(minutes: 2));
          } catch (e) {
            fail('$name failed to start: $e\nstderr:\n$stderrText');
          }
          expect(tools, isNotEmpty);
        });
      }
    });
  }
}

void _copyDir(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final FileSystemEntity entity in from.listSync()) {
    final String target = path.join(to.path, path.basename(entity.path));
    if (entity is Directory) {
      _copyDir(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}
