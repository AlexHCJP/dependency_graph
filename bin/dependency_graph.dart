import 'dart:io';

import 'package:dependency_graph/dependency_graph.dart';

const usage = '''
Usage: dependency_graph [root] [out.html]

Writes an HTML page of who imports whom in a Dart package or pub workspace.

  root       the package or workspace root (default: .)
  out.html   where to write the page (default: <root>/build/dependency_graph/index.html)''';

void main(List<String> args) {
  if (args.contains('-h') || args.contains('--help')) {
    stdout.writeln(usage);
    return;
  }
  final root = Directory(args.isNotEmpty ? args[0] : '.');
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('No pubspec.yaml in ${root.path}\n\n$usage');
    exitCode = 64;
    return;
  }
  final out = File(
    args.length > 1
        ? args[1]
        : '${root.path}/build/dependency_graph/index.html',
  );
  final graph = scan(root);
  out
    ..createSync(recursive: true)
    ..writeAsStringSync(render(graph));
  final packages = (graph['packages'] as List).length;
  final files = (graph['files'] as List).length;
  final edges = (graph['edges'] as List).length;
  final external = (graph['external'] as List).length;
  stdout.writeln(
    '$packages packages, $files files, $edges edges, '
    '$external external libraries → '
    '${out.absolute.uri.normalizePath().toFilePath()}',
  );
}
