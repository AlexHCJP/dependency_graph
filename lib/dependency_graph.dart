import 'dart:convert';
import 'dart:io';

import 'package:dependency_graph/src/template.dart';

/// The workspace members named in the root `pubspec.yaml`, as paths relative
/// to it: `apps/shop`, `packages/feature_auth`, …
List<String> workspaceMembers(String rootPubspec) {
  final section = RegExp(
    r'^workspace:\s*\n((?:[ \t]+-.*\n?|[ \t]*#.*\n?|\s*\n)+)',
    multiLine: true,
  ).firstMatch(rootPubspec);
  if (section == null) return const [];
  return RegExp(
    r'^[ \t]+-[ \t]+(\S+)',
    multiLine: true,
  ).allMatches(section[1]!).map((m) => m[1]!).toList();
}

/// The `name:` of a pubspec.
String? packageName(String pubspec) =>
    RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec)?[1];

/// Every `import`, `export` and `part` of a Dart file, as (kind, uri). A
/// conditional import counts by its default uri; `part of` is not a
/// dependency of its own — the library's `part` already is the edge.
List<(String, String)> directives(String source) => RegExp(
  r'''^[ \t]*(import|export|part)[ \t]+['"]([^'"]+)['"]''',
  multiLine: true,
).allMatches(source).map((m) => (m[1]!, m[2]!)).toList();

/// Every package `pubspec.lock` pinned — what `pub get` downloaded — as
/// name → (version, source: hosted, sdk, git, path).
Map<String, (String, String)> lockedPackages(String lock) {
  final found = <String, (String, String)>{};
  for (final m in RegExp(
    r'^  (\S+):\n(?:    .*\n)*?    source: (\S+)\n    version: "([^"]*)"',
    multiLine: true,
  ).allMatches(lock)) {
    found[m[1]!] = (m[3]!, m[2]!);
  }
  return found;
}

/// The id (`package/path/under/lib.dart`) a directive in the file [fromId]
/// points at, or null when that is outside the workspace — `dart:` or a pub
/// package. Whether the file exists is `scan`'s to check.
String? resolve(String uri, String fromId, Set<String> local) {
  if (uri.startsWith('dart:')) return null;
  final target = Uri.parse('package:$fromId').resolveUri(Uri.parse(uri));
  if (!target.isScheme('package')) return null;
  final package = target.pathSegments.first;
  if (!local.contains(package)) return null;
  return target.path;
}

/// The whole workspace as data — or the one package, when [root]'s pubspec
/// names no workspace: its packages, their `lib/` files, an edge per
/// directive that lands on one of those files, the pub packages `pubspec.lock`
/// pinned, and a use per directive that lands on one of those.
Map<String, Object> scan(Directory root) {
  final workspace = workspaceMembers(
    File('${root.path}/pubspec.yaml').readAsStringSync(),
  );
  final members = workspace.isEmpty ? const ['.'] : workspace;
  final packages = <Map<String, Object>>[];
  final sources = <String, String>{};
  for (final dir in members) {
    final pubspec = File('${root.path}/$dir/pubspec.yaml');
    final lib = Directory('${root.path}/$dir/lib');
    if (!pubspec.existsSync() || !lib.existsSync()) continue;
    final name = packageName(pubspec.readAsStringSync());
    if (name == null) continue;
    var count = 0;
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = f.path.substring(lib.path.length + 1).replaceAll(r'\', '/');
      sources['$name/$rel'] = f.readAsStringSync();
      count++;
    }
    packages.add({'name': name, 'dir': dir, 'files': count});
  }

  final local = {for (final p in packages) p['name'] as String};
  final files = [
    for (final MapEntry(key: id, value: src) in sources.entries)
      {'id': id, 'lines': '\n'.allMatches(src).length + 1},
  ];
  final lockFile = File('${root.path}/pubspec.lock');
  final locked = lockFile.existsSync()
      ? lockedPackages(lockFile.readAsStringSync())
      : const <String, (String, String)>{};
  final external = [
    for (final MapEntry(key: name, value: (version, source)) in locked.entries)
      if (!local.contains(name))
        {'name': name, 'version': version, 'source': source},
  ];
  final edges = <Map<String, String>>[];
  final uses = <Map<String, String>>[];
  for (final MapEntry(key: id, value: src) in sources.entries) {
    for (final (kind, uri) in directives(src)) {
      if (uri.startsWith('package:')) {
        final name = uri.substring(8).split('/').first;
        if (!local.contains(name) && locked.containsKey(name)) {
          uses.add({'from': id, 'to': name});
          continue;
        }
      }
      final to = resolve(uri, id, local);
      // A generated file not built yet is not a file to draw.
      if (to == null || !sources.containsKey(to) || to == id) continue;
      edges.add({'from': id, 'to': to, 'kind': kind});
    }
  }
  return {
    'packages': packages,
    'files': files,
    'edges': edges,
    'external': external,
    'uses': uses,
  };
}

/// The page: the template with the scan inlined, so it opens from disk.
String render(Map<String, Object> graph) => htmlTemplate.replaceFirst(
  '/*DATA*/null',
  // `</` would end the script tag early.
  jsonEncode(graph).replaceAll('</', r'<\/'),
);
