// Package-boundary validator for the media_core workspace.
//
// Enforces the parts of `docs/engineering/package-standards.md` that can be
// checked without judgement: naming, required files, workspace membership,
// `resolution: workspace`, declared internal dependencies, import boundaries,
// approved git-dependency exceptions, and dependency cycles.
//
//     dart tool/validate_packages.dart
//
// Exits 1 on any violation, 2 when the workspace itself cannot be read.

// A command line tool reports on stdout; `avoid_print` is a rule for library
// code, and this file is not imported by anything.
// ignore_for_file: avoid_print

import 'dart:io';

/// Packages allowed to carry a `git:` dependency. pub.dev rejects git
/// dependencies, so these are held back from publishing and must say so with
/// `publish_to: none`; the same move anywhere else is an undocumented exception.
const Set<String> _gitDependencyExceptions = <String>{'media_core_ijk_player', 'media_core_media_kit'};

/// Composition roots. An app is the thing that imports everything else: it has
/// no `lib/<name>.dart` barrel, and it is exercised by the app it is part of
/// rather than by a `test/` directory of its own.
const Set<String> _apps = <String>{'example'};

bool _isApp(_Package package) => _apps.contains(package.name) || _basename(package.relative) == 'example';

final List<String> _violations = <String>[];
int _checks = 0;

void main(List<String> arguments) {
  final root = _findRoot(Directory.current.path);

  if (root == null) {
    stderr.writeln('validate_packages: no pubspec.yaml with a `workspace:` list above ${Directory.current.path}');

    exit(2);
  }

  final declared = _readWorkspaceList(root);
  final members = <String, _Package>{};

  for (final relative in declared) {
    final directory = _p(root, relative);
    final pubspec = File(_p(directory, 'pubspec.yaml'));

    if (!pubspec.existsSync()) {
      _fail('the workspace lists `$relative`, which has no pubspec.yaml on disk (§6.1)');

      continue;
    }

    members[relative] = _Package(relative, directory, _read(pubspec));
  }

  _checkRoot(root);
  _checkMembership(root, declared, members);

  for (final package in members.values) {
    _checkPackage(package, members);
  }

  _checkImportBoundaries(members);
  _checkCycles(members);

  if (_violations.isEmpty) {
    print('validate_packages: $_checks checks passed, no violations.');

    exit(0);
  }

  print('validate_packages: ${_violations.length} violation(s) in $_checks checks');

  for (final violation in _violations) {
    print('  - $violation');
  }

  exit(1);
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

void _checkRoot(String root) {
  final text = _read(File(_p(root, 'pubspec.yaml')));

  // The root is a resolution scope rather than a package, so it must not be
  // publishable (§6.1).
  _require(text.contains('publish_to: none'), 'the workspace root must declare `publish_to: none` (§6.1)');
}

void _checkMembership(String root, List<String> declared, Map<String, _Package> members) {
  // A package directory missing from the list is invisible to the workspace and
  // therefore to every resolution and analysis run.
  final onDisk = <String>{
    for (final entity in Directory(_p(root, 'packages')).listSync())
      if (entity is Directory && File(_p(entity.path, 'pubspec.yaml')).existsSync())
        'packages/${_basename(entity.path)}',
  };

  for (final missing in onDisk.difference(declared.toSet())) {
    _fail('$missing has a pubspec.yaml but is not in the root workspace list (§6.1)');
  }

  _pass();

  for (final package in members.values) {
    _require(
      package.text.contains('resolution: workspace'),
      '${package.name.isEmpty ? package.relative : package.name}: does not declare `resolution: workspace` (§6.2)',
    );
  }
}

void _checkPackage(_Package package, Map<String, _Package> members) {
  final name = package.name;

  if (name.isEmpty) {
    _fail('${package.relative}: pubspec.yaml has no readable `name:`');

    return;
  }

  // §3.1: the directory name and the package name are the same thing. An app is
  // exempt: a nested example is named after what it demonstrates
  // (`media_core_native/example` → `media_core_native_example`), which is the
  // pub convention and is recorded as an exception in docs/decisions/.
  _require(
    _isApp(package) || _basename(package.relative) == name,
    '${package.relative}: the directory is `${_basename(package.relative)}` but the pubspec names it `$name` (§3.1)',
  );

  for (final required in const ['README.md', 'CHANGELOG.md', 'analysis_options.yaml']) {
    _require(File(_p(package.directory, required)).existsSync(), '$name: missing $required (§5)');
  }

  if (!_isApp(package)) {
    _require(
      File(_p(package.directory, 'lib', '$name.dart')).existsSync(),
      '$name: no public entry point lib/$name.dart (§8.2)',
    );
    _require(
      Directory(_p(package.directory, 'test')).existsSync(),
      '$name: no test/ directory (§12)',
    );
  }

  if (RegExp(r'^\s+git:', multiLine: true).hasMatch(package.text)) {
    _require(
      _gitDependencyExceptions.contains(name),
      '$name: carries a git dependency without an approved exception (§17)',
    );
    _require(
      package.text.contains('publish_to: none'),
      '$name: a git dependency makes it unpublishable, so it must declare `publish_to: none`',
    );
  }

  // §6.3: importing an internal package requires declaring it as a dependency.
  final undeclared = _internalImports(package).difference(package.dependencies).difference({name});

  _require(
    undeclared.isEmpty,
    '$name: imports ${undeclared.join(', ')} without declaring them as dependencies (§6.3)',
  );
}

void _checkImportBoundaries(Map<String, _Package> members) {
  for (final package in members.values) {
    for (final file in _dartFiles(package.directory)) {
      for (final match in RegExp('package:(media_core[a-zA-Z0-9_]*)/src/').allMatches(_read(file))) {
        final other = match.group(1)!;

        if (other != package.name) {
          _fail(
            '${package.relative}/${_relativeTo(package.directory, file.path)}: imports the private '
            'lib/src of `$other` (§7.1 rule 7)',
          );
        }
      }
    }
  }

  _pass();
}

/// Walks the declared internal graph; a cycle is reported once, at its start.
void _checkCycles(Map<String, _Package> members) {
  final edges = <String, Set<String>>{
    for (final package in members.values)
      package.name: package.dependencies.where((name) => members.containsKey(name)).toSet(),
  };

  final settled = <String>{};
  final reported = <String>{};

  void walk(String name, List<String> path) {
    if (settled.contains(name) || reported.contains(name)) {
      return;
    }

    final repeat = path.indexOf(name);

    if (repeat >= 0) {
      reported.add(name);
      _fail('dependency cycle: ${path.sublist(repeat).join(' -> ')} -> $name (§7.1 rule 6)');

      return;
    }

    for (final next in edges[name] ?? const <String>{}) {
      walk(next, <String>[...path, name]);
    }

    settled.add(name);
  }

  for (final name in edges.keys) {
    walk(name, const <String>[]);
  }

  _pass();
}

// ---------------------------------------------------------------------------
// Reading the workspace
// ---------------------------------------------------------------------------

/// Reads a file with line endings normalised.
///
/// The checkout carries CRLF endings, and every pattern below is line-oriented:
/// without this, a captured workspace entry keeps its trailing `\r` and matches
/// nothing.
String _read(File file) => file.readAsStringSync().replaceAll('\r\n', '\n');

String? _findRoot(String start) {
  var current = Directory(start);

  while (true) {
    final pubspec = File(_p(current.path, 'pubspec.yaml'));

    if (pubspec.existsSync() && _read(pubspec).contains('\nworkspace:')) {
      return current.path;
    }

    final parent = current.parent;

    if (parent.path == current.path) {
      return null;
    }

    current = parent;
  }
}

List<String> _readWorkspaceList(String root) {
  final text = _read(File(_p(root, 'pubspec.yaml')));

  return [
    for (final match in RegExp(r'^\s*-\s*(\S.*)$', multiLine: true).allMatches(_blockAfter(text, 'workspace')))
      match.group(1)!.trim(),
  ];
}

/// The indented block under [key], up to the next top-level key.
String _blockAfter(String text, String key) {
  final header = '\n'
      '$key:';
  final start = text.indexOf(header);

  if (start < 0) {
    return '';
  }

  // Everything after the header line, up to the next top-level key. Slicing by
  // the header's own length rather than by `key.length` is what keeps the colon
  // out of the block: leaving it in makes the next line look like the top-level
  // key the scan is hunting for, and the block comes back empty.
  final rest = text.substring(start + header.length);
  final next = RegExp(r'^\S', multiLine: true).firstMatch(rest);

  return next == null ? rest : rest.substring(0, next.start);
}

Set<String> _keysOf(String block) => <String>{
  for (final match in RegExp('^  ([A-Za-z0-9_]+):', multiLine: true).allMatches(block)) match.group(1)!,
};

/// Internal package names imported from anywhere in this package's sources.
Set<String> _internalImports(_Package package) => <String>{
  for (final file in _dartFiles(package.directory))
    for (final match in RegExp('package:(media_core[a-zA-Z0-9_]*)/').allMatches(_read(file)))
      match.group(1)!,
};

final class _Package {
  _Package(this.relative, this.directory, this.text);

  /// Path as written in the root workspace list.
  final String relative;

  /// Absolute directory of the package.
  final String directory;

  final String text;

  String get name => RegExp(r'^name:\s*(\S+)\s*$', multiLine: true).firstMatch(text)?.group(1) ?? '';

  /// Names under the top-level `dependencies:` block.
  Set<String> get dependencies => _keysOf(_blockAfter(text, 'dependencies'));
}

// ---------------------------------------------------------------------------
// Reporting and paths
// ---------------------------------------------------------------------------

void _require(bool ok, String violation) => ok ? _pass() : _fail(violation);

void _pass() => _checks++;

void _fail(String violation) {
  _checks++;

  _violations.add(violation);
}

String _p(String root, [String a = '', String b = '']) =>
    <String>[root, a, b].where((part) => part.isNotEmpty).join(Platform.pathSeparator);

String _basename(String path) =>
    path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty).last;

List<String> _parts(String path) => path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty).toList();

String _relativeTo(String root, String path) => path.startsWith(root) ? path.substring(root.length + 1) : path;

/// Paths that are not this package's own source: generated trees, and the
/// plugin symlinks a Flutter app creates to reach the packages it embeds.
/// Without this, a validator run inside `example/` reads the whole workspace
/// through `linux/flutter/ephemeral/.plugin_symlinks/` and reports every package
/// as violating the rules of the app that merely links it.
bool _isGeneratedPath(String path) {
  const blocked = <String>{'.dart_tool', 'build', 'ephemeral', '.plugin_symlinks', '.gradle', 'Pods', 'node_modules'};

  return _parts(path).any(blocked.contains);
}

/// Every `.dart` file under [directory], skipping build output.
Iterable<File> _dartFiles(String directory) sync* {
  final dir = Directory(directory);

  if (!dir.existsSync()) {
    return;
  }

  // Links are not followed: a Flutter app reaches its packages through
  // `.plugin_symlinks`, and walking those would make every package look like a
  // violation of the app that only links it.
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart') || _isGeneratedPath(entity.path)) {
      continue;
    }

    yield entity;
  }
}
