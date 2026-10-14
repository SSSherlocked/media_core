import 'dart:io';

/// Local file operations a download needs.
///
/// The seam keeps the queue testable on any host and lets a host put downloads
/// somewhere other than a plain file — an app-sandboxed path, a content URI, a
/// storage abstraction.
abstract interface class DownloadFileSink {
  /// Size of [path], or `0` when it does not exist.
  Future<int> length(String path);

  /// Last [count] bytes of [path], or fewer when the file is shorter.
  Future<List<int>> readTail(String path, int count);

  /// Appends [bytes] to [path], creating it when needed.
  Future<void> append(String path, List<int> bytes);

  /// Truncates [path] to [length] bytes, creating it when needed.
  Future<void> truncate(String path, int length);

  /// Deletes [path] when it exists.
  Future<void> delete(String path);

  /// Whether the parent directory of [path] exists, creating it when asked.
  Future<void> ensureParentDirectory(String path);
}

/// [DownloadFileSink] backed by `dart:io`.
final class IoDownloadFileSink implements DownloadFileSink {
  /// Creates a `dart:io`-backed sink.
  const IoDownloadFileSink();

  @override
  Future<int> length(String path) async {
    final file = File(path);
    return file.existsSync() ? await file.length() : 0;
  }

  @override
  Future<List<int>> readTail(String path, int count) async {
    final file = File(path);
    if (!file.existsSync() || count <= 0) {
      return const <int>[];
    }
    final length = await file.length();
    final start = length - count;
    if (start < 0) {
      return const <int>[];
    }
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      return await handle.read(count);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    final file = File(path);
    await ensureParentDirectory(path);
    await file.writeAsBytes(bytes, mode: FileMode.append);
  }

  @override
  Future<void> truncate(String path, int length) async {
    final file = File(path);
    await ensureParentDirectory(path);
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.truncate(length);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<void> ensureParentDirectory(String path) async {
    final separator = path.contains(r'\') ? r'\' : '/';
    final index = path.lastIndexOf(separator);
    if (index <= 0) {
      return;
    }
    await Directory(path.substring(0, index)).create(recursive: true);
  }
}
