import 'dart:async';

import 'package:media_core_download/media_core_download.dart';

/// A transport that serves synthetic bytes.
///
/// A download demo without a network: the queue, the resume verification, the
/// retry budget and the failure statuses are all decided by
/// [DownloadManager], and none of them needs a real file on a real server to be
/// observable. What the transport must do is behave the way servers actually
/// misbehave — answer a ranged request with the whole body, end a stream early,
/// fail twice before succeeding.
///
/// The "remote file" is deterministic: byte `n` equals `n % 251`, so a resumed
/// file can be checked for being a true prefix without storing anything.
final class FakeDownloadTransport implements DownloadTransport {
  /// Creates a fake transport.
  new({
    this.totalBytes = 64 * 1024,
    this.chunkBytes = 8 * 1024,
    this.chunkDelay = const Duration(milliseconds: 40),
    this.ignoreRanges = false,
    this.failuresBeforeSuccess = 0,
    this.truncateAfterBytes,
  });

  /// Size of the synthetic file.
  int totalBytes;

  /// Bytes per emitted chunk.
  int chunkBytes;

  /// Delay between chunks.
  Duration chunkDelay;

  /// Answer ranged requests with `200` and the whole body.
  ///
  /// A real failure mode: a server (or a proxy) that ignores `Range` makes the
  /// app append the whole file to the part it already had, which is why the
  /// manager restarts the file in that case.
  bool ignoreRanges;

  /// Fail this many requests before serving one.
  int failuresBeforeSuccess;

  /// End the stream after this many bytes of a response, simulating a dropped
  /// connection. `null` means "serve everything".
  int? truncateAfterBytes;

  /// Requests this transport received, in order.
  final List<String> requests = <String>[];

  int _sequence = 0;

  /// Byte value of the synthetic file at [offset].
  static int byteAt(int offset) => offset % 251;

  @override
  Future<DownloadResponse> fetch(DownloadRequest request) async {
    requests.add(
      'GET ${request.url} '
      '${request.startByte}..${request.endByte ?? 'end'}'
      '${request.headers.isEmpty ? '' : ' headers=${request.headers.length}'}',
    );

    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw StateError('fake transport refused request #${++_sequence}');
    }

    final ranged = request.startByte > 0 || request.endByte != null;
    final honoursRange = ranged && !ignoreRanges;

    final from = honoursRange ? request.startByte : 0;
    final to = request.endByte == null ? totalBytes : request.endByte! + 1;
    final end = truncateAfterBytes == null
        ? (to > totalBytes ? totalBytes : to)
        : (from + truncateAfterBytes! > totalBytes ? totalBytes : from + truncateAfterBytes!);

    return DownloadResponse(
      statusCode: honoursRange ? 206 : 200,
      acceptsRanges: !ignoreRanges,
      contentLength: end - from,
      totalBytes: totalBytes,
      byteStream: _bytes(from, end),
    );
  }

  Stream<List<int>> _bytes(int from, int end) async* {
    var offset = from;
    while (offset < end) {
      final size = (end - offset) < chunkBytes ? end - offset : chunkBytes;
      if (chunkDelay > Duration.zero) {
        await Future<void>.delayed(chunkDelay);
      }
      yield List<int>.generate(size, (index) => byteAt(offset + index));
      offset += size;
    }
  }

  @override
  Future<void> dispose() async {}
}

/// A file sink that keeps bytes in memory.
///
/// The point of the fake: a demo can assert "the partial file survived a pause"
/// without touching the disk, and printing the store's contents is itself an
/// illustration of what resume verification is for.
final class FakeDownloadFileSink implements DownloadFileSink {
  final Map<String, List<int>> _files = <String, List<int>>{};

  /// Files currently held, path → bytes.
  Map<String, List<int>> get files => Map<String, List<int>>.unmodifiable(_files);

  /// Appends this many bytes out of nowhere, as a leftover from a previous run.
  ///
  /// Used to set up the "the file on disk is not a prefix of the remote one"
  /// case: a partial file whose bytes were never served by the fake transport.
  void seed(String path, int length) {
    _files[path] = List<int>.generate(length, (index) => 200);
  }

  /// Whether [path] is a true prefix of the synthetic remote file.
  bool looksLikePrefixOf(String path) {
    final bytes = _files[path];
    if (bytes == null) {
      return true;
    }
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != FakeDownloadTransport.byteAt(index)) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<int> length(String path) async => _files[path]?.length ?? 0;

  @override
  Future<List<int>> readTail(String path, int count) async {
    final bytes = _files[path] ?? const <int>[];
    final start = bytes.length - count;
    if (start <= 0) {
      return List<int>.of(bytes);
    }
    return bytes.sublist(start);
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    (_files[path] ??= <int>[]).addAll(bytes);
  }

  @override
  Future<void> truncate(String path, int length) async {
    final bytes = _files[path];
    if (bytes == null) {
      return;
    }
    if (length <= 0) {
      bytes.clear();
      return;
    }
    if (length < bytes.length) {
      _files[path] = bytes.sublist(0, length);
    }
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<void> ensureParentDirectory(String path) async {}
}
