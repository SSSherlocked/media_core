import 'dart:async';
import 'dart:io';

import 'package:media_core_ingest/src/ingest_ffmpeg.dart';

/// Remuxes an upstream with FFmpeg into a rolling loopback HLS tree.
///
/// Some sources are outside what the player's own FFmpeg can parse - codec-id-12
/// HEVC FLV is the observed case - and some swap their signed URL underneath a
/// playing stream. Both are "give FFmpeg one job and let the player read a plain
/// local playlist" problems, which is what this relay is: one process, one
/// directory, one port, a rolling `index.m3u8`.
///
/// The player only ever sees `http://127.0.0.1:<port>/index.m3u8`; the playlist's
/// own segment names are relative to that URL, so nothing has to be rewritten.
final class FfmpegIngestRelay {
  FfmpegIngestRelay._({
    required HttpServer server,
    required Directory directory,
    required IngestFfmpegProcess execution,
    required this.source,
  }) : _server = server,
       _directory = directory,
       _execution = execution;

  /// Starts the pipeline and waits for the first playlist.
  ///
  /// FFmpeg writes `index.m3u8` only after it has probed the input, so the wait
  /// doubles as "the source is actually playable"; a timeout or a non-zero exit
  /// before the first playlist throws, and the caller can fall back to a direct
  /// open instead of showing a black player.
  ///
  /// [startFfmpeg] is the host's own FFmpeg runtime; this package starts no
  /// process by itself.
  static Future<FfmpegIngestRelay> start({
    required Uri source,
    required IngestFfmpegStarter startFfmpeg,
    Map<String, String> headers = const <String, String>{},
    Duration segmentDuration = const Duration(seconds: 2),
    int playlistSize = 4,
    bool copyStreams = true,
    String? videoCodec,
    String? audioCodec,
    Duration startupTimeout = const Duration(seconds: 12),
  }) async {
    final directory = await Directory.systemTemp.createTemp('media_core_ingest_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final playlistPath = '${directory.path}${Platform.pathSeparator}$ingestPlaylistName';
    IngestFfmpegProcess? execution;
    try {
      execution = await startFfmpeg(
        buildIngestArguments(
          source: source,
          headers: headers,
          outputDirectory: directory.path,
          segmentDuration: segmentDuration,
          playlistSize: playlistSize,
          copyStreams: copyStreams,
          videoCodec: videoCodec,
          audioCodec: audioCodec,
        ),
      );
      final relay = FfmpegIngestRelay._(server: server, directory: directory, execution: execution, source: source);
      // One subscription records the exit; `exitCode` is only readable once.
      unawaited(
        execution.exitCode.then((code) {
          relay
            .._exited = true
            .._exitCode = code;
        }),
      );
      server.listen(relay._handle, onError: (Object _) {}, cancelOnError: false);
      await relay._awaitPlaylist(File(playlistPath), startupTimeout);
      return relay;
    } catch (_) {
      await execution?.stop();
      await server.close(force: true);
      await _deleteQuietly(directory);
      rethrow;
    }
  }

  /// Name FFmpeg writes and the player reads.
  static const String ingestPlaylistName = 'index.m3u8';

  /// Starts a DASH merge pipeline: two separate essence URLs (video m4s +
  /// audio m4s) are muxed by FFmpeg into one rolling loopback HLS tree.
  ///
  /// The player only ever sees [inputUri]; the merge is transparent. Both
  /// inputs share [headers] (bilibili DASH gives one Referer for the pair),
  /// but [audioHeaders] overrides for the audio leg when the CDN differs.
  static Future<FfmpegIngestRelay> startDashMerge({
    required Uri videoSource,
    required Uri audioSource,
    required IngestFfmpegStarter startFfmpeg,
    Map<String, String> headers = const <String, String>{},
    Map<String, String>? audioHeaders,
    Duration segmentDuration = const Duration(seconds: 2),
    int playlistSize = 4,
    Duration startupTimeout = const Duration(seconds: 12),
  }) async {
    final directory = await Directory.systemTemp.createTemp('media_core_dash_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final playlistPath = '${directory.path}${Platform.pathSeparator}$ingestPlaylistName';
    IngestFfmpegProcess? execution;
    try {
      execution = await startFfmpeg(
        buildDashMergeArguments(
          videoSource: videoSource,
          audioSource: audioSource,
          headers: headers,
          audioHeaders: audioHeaders,
          outputDirectory: directory.path,
          segmentDuration: segmentDuration,
          playlistSize: playlistSize,
        ),
      );
      final relay = FfmpegIngestRelay._(
        server: server,
        directory: directory,
        execution: execution,
        source: videoSource,
      );
      unawaited(
        execution.exitCode.then((code) {
          relay
            .._exited = true
            .._exitCode = code;
        }),
      );
      server.listen(relay._handle, onError: (Object _) {}, cancelOnError: false);
      await relay._awaitPlaylist(File(playlistPath), startupTimeout);
      return relay;
    } catch (_) {
      await execution?.stop();
      await server.close(force: true);
      await _deleteQuietly(directory);
      rethrow;
    }
  }

  /// Stable argument list, exposed for tests and for hosts that log it.
  static List<String> buildIngestArguments({
    required Uri source,
    required String outputDirectory,
    Map<String, String> headers = const <String, String>{},
    Duration segmentDuration = const Duration(seconds: 2),
    int playlistSize = 4,
    bool copyStreams = true,
    String? videoCodec,
    String? audioCodec,
  }) {
    final separator = Platform.pathSeparator;
    final arguments = <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      if (headers.isNotEmpty) ...<String>[
        '-headers',
        headers.entries.map((entry) => '${entry.key}: ${entry.value}\r\n').join(),
      ],
      '-i',
      source.toString(),
      if (copyStreams) ...<String>['-c', 'copy'] else ...<String>[
        '-c:v',
        videoCodec ?? 'libx264',
        '-preset',
        'veryfast',
        '-tune',
        'zerolatency',
        '-c:a',
        audioCodec ?? 'aac',
      ],
      // A live rolling window: the player seeks inside it, FFmpeg drops what it
      // has already published.
      '-f',
      'hls',
      '-hls_time',
      (segmentDuration.inMilliseconds / 1000).toStringAsFixed(3),
      '-hls_list_size',
      playlistSize.toString(),
      '-hls_flags',
      'delete_segments+append_list+omit_endlist',
      '-hls_segment_filename',
      '$outputDirectory${separator}segment%05d.ts',
      '$outputDirectory$separator$ingestPlaylistName',
    ];
    return arguments;
  }

  /// DASH merge argument list: two inputs (video m4s + audio m4s), stream-copy
  /// into one rolling HLS tree. Exposed for tests and host logging.
  ///
  /// FFmpeg's `-headers` binds to the *next* `-i`, so each input carries its
  /// own header block. `-map 0:v:0 -map 1:a:0` pins the first video stream
  /// from input 0 and the first audio stream from input 1 — a DASH manifest
  /// can list alternates, and an unmapped merge would silently pick whichever
  /// FFmpeg likes best.
  static List<String> buildDashMergeArguments({
    required Uri videoSource,
    required Uri audioSource,
    required String outputDirectory,
    Map<String, String> headers = const <String, String>{},
    Map<String, String>? audioHeaders,
    Duration segmentDuration = const Duration(seconds: 2),
    int playlistSize = 4,
  }) {
    final separator = Platform.pathSeparator;
    final effectiveAudioHeaders = audioHeaders ?? headers;
    return <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      if (headers.isNotEmpty) ...<String>['-headers', headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()],
      '-i',
      videoSource.toString(),
      if (effectiveAudioHeaders.isNotEmpty) ...<String>[
        '-headers',
        effectiveAudioHeaders.entries.map((e) => '${e.key}: ${e.value}\r\n').join(),
      ],
      '-i',
      audioSource.toString(),
      '-c',
      'copy',
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-f',
      'hls',
      '-hls_time',
      (segmentDuration.inMilliseconds / 1000).toStringAsFixed(3),
      '-hls_list_size',
      playlistSize.toString(),
      '-hls_flags',
      'delete_segments+append_list+omit_endlist',
      '-hls_segment_filename',
      '$outputDirectory${separator}segment%05d.ts',
      '$outputDirectory$separator$ingestPlaylistName',
    ];
  }

  final HttpServer _server;
  final Directory _directory;
  final IngestFfmpegProcess _execution;

  /// The upstream this pipeline was started for.
  final Uri source;
  bool _closed = false;
  bool _exited = false;
  int? _exitCode;

  /// The URL the player opens.
  Uri get inputUri =>
      Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: _server.port, path: '/$ingestPlaylistName');

  /// Whether FFmpeg has stopped, and with which code.
  bool get hasExited => _exited;

  /// FFmpeg's exit code once it has stopped, or `null` while it runs.
  int? get exitCode => _exitCode;

  Future<void> _awaitPlaylist(File playlist, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (playlist.existsSync()) return;
      if (_exited) {
        throw FormatException('FFmpeg ingest stopped (exit $_exitCode) before publishing a playlist');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('FFmpeg ingest published no playlist in ${timeout.inSeconds}s', timeout);
  }

  Future<void> _handle(HttpRequest request) async {
    final name = request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.last;
    // The playlist is the only dynamic name; everything else must be one of the
    // segments FFmpeg wrote, so a request can never walk out of the directory.
    if (name.isEmpty || name.contains('..') || name.contains('/') || name.contains(r'\')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final file = File('${_directory.path}${Platform.pathSeparator}$name');
    if (!file.existsSync()) {
      // The player retries; a missing segment is not an error worth closing on.
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = name.endsWith('.m3u8')
        ? ContentType('application', 'vnd.apple.mpegurl')
        : ContentType('video', 'mp2t');
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  /// Stops FFmpeg, the port and the staging directory.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _execution.stop();
    await _server.close(force: true);
    await _deleteQuietly(_directory);
  }

  static Future<void> _deleteQuietly(Directory directory) async {
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
    } on Object catch (_) {
      // Staging cleanup is best-effort: the OS temp sweeper is the backstop.
    }
  }
}
