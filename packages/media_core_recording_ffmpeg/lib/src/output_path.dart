import 'package:path/path.dart' as p;

/// The [p.Context] whose separators match [path].
///
/// The style comes from the string the caller was given, not from the host this
/// code runs on. A recording's paths are written by FFmpeg and read back by
/// this package, and both sides have to agree on the separator even when the
/// output directory was built on one platform and is being inspected on another
/// (a desktop host passing a Windows path, a test running on any of them).
p.Context pathContextFor(String path) => path.contains(r'\') ? p.windows : p.posix;

/// Joins [directory] and [name] with the separator [directory] already uses.
String joinOutputPath(String directory, String name) => pathContextFor(directory).join(directory, name);

/// The directory [path] lives in, or the path itself when it has no parent.
String outputDirectoryOf(String path) {
  final parent = pathContextFor(path).dirname(path);

  return parent.isEmpty ? '.' : parent;
}
