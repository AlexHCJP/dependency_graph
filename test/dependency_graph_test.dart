import 'dart:io';

import 'package:dependency_graph/dependency_graph.dart';

/// `dart run --enable-asserts tools/dependency_graph/test/dependency_graph_test.dart`
void main() {
  assert(
    workspaceMembers(
          'name: w\nworkspace:\n  - apps/a\n  # note\n  - packages/b\n\nother: 1\n',
        ).join(',') ==
        'apps/a,packages/b',
  );
  assert(packageName('name: feature_x\nversion: 1') == 'feature_x');

  final found = directives('''
import 'dart:io';
import 'package:b/x.dart' show X;
export 'src/y.dart';
part 'z.g.dart';
part of 'w.dart';
''');
  assert(
    found.map((d) => '${d.$1} ${d.$2}').join('|') ==
        'import dart:io|import package:b/x.dart|export src/y.dart|part z.g.dart',
  );

  final locked = lockedPackages('''
packages:
  http:
    dependency: transitive
    description:
      name: http
      url: "https://pub.dev"
    source: hosted
    version: "1.2.0"
  flutter:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.0"
sdks:
  dart: ">=3.12.0 <4.0.0"
''');
  assert(locked.length == 2, '$locked');
  assert(locked['http'] == ('1.2.0', 'hosted'));
  assert(locked['flutter'] == ('0.0.0', 'sdk'));

  final local = {'a', 'b'};
  assert(resolve('dart:io', 'a/f.dart', local) == null);
  assert(resolve('package:flutter/w.dart', 'a/f.dart', local) == null);
  assert(resolve('package:b/x.dart', 'a/f.dart', local) == 'b/x.dart');
  assert(resolve('../y.dart', 'a/data/f.dart', local) == 'a/y.dart');

  // A whole workspace on disk: a imports b, and a file that is not there yet.
  final root = Directory.systemTemp.createTempSync('dependency_graph');
  try {
    File('${root.path}/pubspec.yaml')
      ..createSync()
      ..writeAsStringSync('workspace:\n  - p/a\n  - p/b\n');
    File('${root.path}/pubspec.lock')
      ..createSync()
      ..writeAsStringSync(
        'packages:\n  http:\n    source: hosted\n    version: "1.2.0"\n'
        '  meta:\n    source: hosted\n    version: "1.0.0"\n',
      );
    void file(String path, String text) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    file('p/a/pubspec.yaml', 'name: a');
    file('p/b/pubspec.yaml', 'name: b');
    file(
      'p/a/lib/main.dart',
      "import 'package:b/b.dart';\nimport 'package:http/http.dart';\n"
          "import 'package:unknown/u.dart';\npart 'main.g.dart';",
    );
    file('p/b/lib/b.dart', "export 'src/c.dart';");
    file('p/b/lib/src/c.dart', '');
    final graph = scan(root);
    final edges = (graph['edges'] as List)
        .map((e) => '${e['from']}>${e['to']}:${e['kind']}')
        .toList();
    assert(edges.length == 2, '$edges');
    assert(edges.contains('a/main.dart>b/b.dart:import'));
    assert(edges.contains('b/b.dart>b/src/c.dart:export'));
    assert((graph['external'] as List).length == 2);
    final uses = graph['uses'] as List;
    assert(uses.length == 1 && uses.first['to'] == 'http', '$uses');
    assert(render(graph).contains('"a/main.dart"'));
  } finally {
    root.deleteSync(recursive: true);
  }

  // A lone package, no workspace: the root is the one package.
  final lone = Directory.systemTemp.createTempSync('dependency_graph');
  try {
    File('${lone.path}/pubspec.yaml').writeAsStringSync('name: solo\n');
    File('${lone.path}/lib/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'b.dart';");
    File('${lone.path}/lib/b.dart').writeAsStringSync('');
    final graph = scan(lone);
    assert((graph['packages'] as List).single['name'] == 'solo');
    assert((graph['edges'] as List).single['to'] == 'solo/b.dart');
  } finally {
    lone.deleteSync(recursive: true);
  }
  stdout.writeln('dependency_graph: ok');
}
