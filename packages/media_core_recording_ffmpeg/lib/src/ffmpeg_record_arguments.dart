import 'package:media_core/media_core.dart' show HttpHeaderSanitizer, UriUtils;

import 'package:media_core_recording_ffmpeg/src/ffmpeg_record_config.dart';
import 'package:media_core_recording_ffmpeg/src/ffmpeg_record_container.dart';
import 'package:media_core_recording_ffmpeg/src/output_path.dart';

/// Builds the FFmpeg argument lists a recording uses.
///
/// Ported from the reference implementation, where every option below was added
/// because a real stream failed without it. The comments are kept because they
/// say *which* failure each flag prevents — the flags alone look arbitrary.
///
/// Two shapes are built:
///
/// - [recordArguments]: segmented MPEG-TS capture straight to files, with a CSV
///   journal that lets the segments be joined later.
/// - [audioRelayArguments]: an audio-only MPEG-TS relay on localhost, for hosts
///   that need a single audio stream they can subscribe to (for example to feed
///   a media player's audio pipeline from the same input).
///
/// Arguments are returned as a list, never as a shell string: FFmpegKit takes an
/// argument list directly, and formatting one into a command line would
/// re-introduce quoting bugs for URLs, headers and paths containing spaces.
/// [formatArguments] exists for logs and tests only.
final class FfmpegRecordArguments {
  /// Builds the arguments a recording made under [config] needs.
  const FfmpegRecordArguments({this.config = FfmpegRecordConfig.defaults});

  /// Tunables.
  final FfmpegRecordConfig config;

  /// Protocols FFmpeg is allowed to open.
  ///
  /// Explicit rather than "whatever the build supports", so a protocol this
  /// package has not reasoned about cannot be reached by accident.
  ///
  /// It is **not** a defence against a hostile input URL: `file` has to stay
  /// listed because FFmpeg needs it to write the local segment output, and
  /// the whitelist applies to the IO layer as a whole rather than to inputs
  /// alone. Deciding that a URL is a network address and not a local path
  /// belongs to whoever knows where the URL came from — this builder only
  /// formats arguments.
  static const String protocolWhitelist = 'httpproxy,udp,rtp,rtsp,rtmp,rtmps,srt,tcp,tls,data,file,http,https,crypto';

  /// Segmented recording arguments.
  ///
  /// [segmentPattern] and [journalPath] come from the caller so the naming and
  /// the journal location stay the host's decision, and [outputDirectory] is
  /// where the pattern is resolved.
  List<String> recordArguments({
    required String url,
    required String outputDirectory,
    required String segmentPattern,
    required String journalPath,
    Map<String, String>? headers,
    String? filePrefix,
  }) {
    final normalizedHeaders = normalizeHeaders(headers);
    final userAgent = normalizedHeaders.remove('user-agent');
    final headerString = buildHeader(normalizedHeaders);
    final prefix = safeFilePrefix(filePrefix ?? config.filePrefix ?? generatedPrefix(config, DateTime.now()));

    final arguments = <String>[
      // Keep no-overwrite intent: segment muxers open child outputs separately,
      // so `-n` is what stops a restart from silently appending to an old file.
      '-n',
      '-hide_banner',
      '-loglevel',
      'info',
      // Recording favours complete stream discovery over playback latency.
      '-analyzeduration',
      '5000000',
      '-probesize',
      '5000000',
      '-fflags',
      '+genpts+discardcorrupt',
      '-protocol_whitelist',
      protocolWhitelist,
      ...inputProtocolOptions(url),
      '-thread_queue_size',
      config.threadQueueSize.clamp(64, 65536).toString(),
      if (userAgent != null && userAgent.isNotEmpty) ...['-user_agent', userAgent],
      if (headerString.isNotEmpty) ...['-headers', headerString],
      // Preserve the source cadence while correcting only discontinuities.
      // `use_wallclock_as_timestamps` is deliberately avoided: HLS/HTTP
      // downloads packets in bursts, so arrival time collapses many frames into
      // near-identical timestamps and produces visibly uneven playback.
      // FFmpeg applies dts_delta_threshold to discontinuity-aware inputs such
      // as HLS/MPEG-TS and dts_error_threshold to formats such as live FLV;
      // together with +genpts this removes a CDN timestamp jump without
      // replacing every valid source timestamp.
      if (usesNetworkInput(url)) ...['-dts_delta_threshold', '2', '-dts_error_threshold', '2'],
      '-i',
      url,
      // Optional mappings support audio-only rooms and temporarily missing
      // video tracks without selecting metadata or data streams.
      '-map',
      if (config.preferBestStream) '0:v:0?' else '0:v?',
      '-map',
      if (config.preferBestStream) '0:a:0?' else '0:a?',
      '-c',
      'copy',
      '-avoid_negative_ts',
      'make_non_negative',
      '-f',
      'segment',
      '-segment_format',
      config.container.segmentFormat,
      // Each container needs its own child-file options.
      //
      // MPEG-TS commits complete packets while running (flush_packets=1) rather than
      // leaving a partial 512 KiB AVIO prefix when cancellation prevents the trailer
      // from flushing. Only the outer muxer normalises the clock: a second per-child
      // shift breaks reconstruction from the journal's reference timestamps. Zero
      // child mux delay keeps each timestamped audio packet's anchor, and the 1.4 s
      // offset retains MPEG-TS's former preroll — without it, concat's inpoint 0
      // discards leading negative DTS in later segments.
      //
      // Fragmented MP4 cannot use any of that: it asks for one fragment per key frame
      // behind an empty movie header, so each child file describes itself and stays
      // readable up to its last complete fragment.
      '-segment_format_options',
      config.container.segmentFormatOptions,
      '-segment_list',
      journalPath,
      '-segment_list_type',
      'csv',
      '-segment_time',
      config.segmentTime.clamp(10, 86400).toString(),
      '-segment_start_number',
      '0',
      '-reset_timestamps',
      '1',
      joinOutputPath(outputDirectory, segmentPattern),
    ];

    // The prefix is part of the path the caller passed, so the recorded name is
    // authoritative here; it is validated to keep a hostile room title out of
    // the filesystem.
    assert(prefix.isNotEmpty, 'A recording needs a file name, and safeFilePrefix falls back to a timestamp.');

    return List<String>.unmodifiable(arguments);
  }

  /// Audio-only relay arguments: reads [url] and serves MPEG-TS on [port].
  List<String> audioRelayArguments({
    required String url,
    required int port,
    int? rwTimeout,
    Map<String, String>? headers,
  }) {
    final normalizedHeaders = normalizeHeaders(headers);
    final userAgent = normalizedHeaders.remove('user-agent');
    final headerString = buildHeader(normalizedHeaders);

    final arguments = <String>[
      '-hide_banner',
      '-loglevel',
      'info',
      '-protocol_whitelist',
      protocolWhitelist,
      ...inputProtocolOptions(url, rwTimeout: rwTimeout),
      if (userAgent != null && userAgent.isNotEmpty) ...['-user_agent', userAgent],
      if (headerString.isNotEmpty) ...['-headers', headerString],
      '-i',
      url,
      '-map',
      '0:a:0',
      '-vn',
      '-c:a',
      'copy',
      '-listen',
      '1',
      '-f',
      'mpegts',
      'http://127.0.0.1:$port/live.ts',
    ];

    return List<String>.unmodifiable(arguments);
  }

  /// Per-scheme input options.
  ///
  /// Reconnection is only armed for HTTP(S): a signed URL that expired cannot
  /// be fixed by retrying it, so only server-side failures are retried inside
  /// FFmpeg and everything else surfaces to the caller, which is the only one
  /// that can fetch a fresh URL.
  List<String> inputProtocolOptions(String rawUrl, {int? rwTimeout}) {
    // Scheme parsing and the network check come from the core's URI helpers, so
    // this package cannot drift from the framework's idea of what a network
    // input is.
    final scheme = UriUtils.scheme(rawUrl)?.toLowerCase() ?? '';
    final seconds = (rwTimeout ?? config.rwTimeout).clamp(1, 3600);
    final timeoutMicros = (seconds * 1000000).clamp(1, 2147483647).toString();
    final options = <String>[];

    if (scheme == 'http' || scheme == 'https') {
      options.addAll([
        '-reconnect',
        '1',
        '-reconnect_streamed',
        '1',
        '-reconnect_on_network_error',
        '1',
        '-reconnect_on_http_error',
        '5xx',
        '-reconnect_delay_max',
        '5',
        '-rw_timeout',
        timeoutMicros,
      ]);
    } else if (scheme == 'rtsp') {
      options.addAll(['-rtsp_transport', 'tcp', '-rw_timeout', timeoutMicros]);
    } else if (scheme == 'udp' || scheme == 'rtp') {
      options.addAll(['-fifo_size', '5000000', '-overrun_nonfatal', '1']);
    } else if (scheme != 'file' && scheme.isNotEmpty) {
      options.addAll(['-rw_timeout', timeoutMicros]);
    }

    return options;
  }

  /// Whether [rawUrl] is a network input that needs discontinuity handling.
  static bool usesNetworkInput(String rawUrl) {
    if (UriUtils.isNetwork(rawUrl)) {
      return true;
    }
    final scheme = UriUtils.scheme(rawUrl)?.toLowerCase() ?? '';
    return const <String>{'rtmps', 'rtp', 'srt'}.contains(scheme);
  }

  /// Validates [headers] against the framework's single rule.
  ///
  /// Delegates to [HttpHeaderSanitizer]: a header that cannot be sent exactly
  /// as given is an error naming that header, not something to rewrite or drop
  /// quietly — the one that disappears is usually the credential, and what the
  /// caller sees next is an unexplained 403.
  static Map<String, String> normalizeHeaders(Map<String, String>? headers) {
    return HttpHeaderSanitizer.sanitize(headers);
  }

  /// Joins normalized headers into FFmpeg's `Name: value\r\n` block.
  static String buildHeader(Map<String, String> headers) {
    return HttpHeaderSanitizer.ffmpegBlock(headers);
  }

  /// Longest prefix a generated file name keeps.
  ///
  /// Room titles are long, the prefix repeats in every segment name, and a
  /// Windows path stops working past MAX_PATH — a recording that cannot create
  /// its fifth segment has lost the four before it for a name nobody can read.
  static const int maxFilePrefixLength = 64;

  /// Characters a file name may not contain.
  ///
  /// Letters and numbers of any script survive, because the names a user records
  /// are their own: an ASCII-only rule folded a Chinese room title to nothing, and
  /// nothing falls back to a timestamp, so the folder ended up full of files whose
  /// names said nothing about who had been in them. What is dropped is what a
  /// filesystem or a shell would act on — the path separators, the dot that makes
  /// `..`, the colon, the quotes, and control characters.
  static final RegExp _unsafeFileName = RegExp(r'[^\p{L}\p{N}_-]+', unicode: true);

  /// Makes [value] safe to use as a file name.
  ///
  /// Room titles reach this from the network, so the result is what a path may
  /// contain, never the title as it arrived.
  static String safeFilePrefix(String? value) {
    var normalized = (value ?? '')
        .replaceAll(_unsafeFileName, '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (normalized.runes.length > maxFilePrefixLength) {
      // Runes, not code units: cutting the middle of a surrogate pair leaves a name
      // that does not compare equal to itself.
      normalized = String.fromCharCodes(normalized.runes.take(maxFilePrefixLength));
      normalized = normalized.replaceAll(RegExp(r'_+$'), '');
    }

    return normalized.isEmpty ? timestampPrefix(DateTime.now()) : normalized;
  }

  /// The prefix a recording gets when its caller gave none.
  ///
  /// [FfmpegRecordConfig.includeTimestampPrefix] decides the shape: a timestamp
  /// (`20261013_182232_915`) is what a host that records several rooms into one
  /// directory needs to tell two takes apart, while a neutral name is what a host
  /// that gives each recording its own directory wants, because there the
  /// directory already says when.
  static String generatedPrefix(FfmpegRecordConfig config, DateTime time) {
    return config.includeTimestampPrefix ? timestampPrefix(time) : 'recording';
  }

  /// The file-name prefix [config] produces for a recording started at [now].
  ///
  /// The single place this rule is read: a recording and its re-opened attempts
  /// have to agree on the base name, and a backend that guessed it a second way
  /// would write the next attempt over the first one's files.
  static String filePrefixFor(FfmpegRecordConfig config, {DateTime? now}) {
    return safeFilePrefix(config.filePrefix ?? generatedPrefix(config, now ?? DateTime.now()));
  }

  /// Timestamp used when no usable prefix is supplied.
  static String timestampPrefix(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}_'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}_'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }

  /// Quotes one argument for display.
  static String quoteArgument(String value) {
    if (value.isEmpty) {
      return '""';
    }
    if (!value.contains(RegExp(r'''[\s"'\\$`]'''))) {
      return value;
    }
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }

  /// Human-readable command for logs and tests. Never passed to FFmpeg.
  static String formatArguments(Iterable<String> arguments) => arguments.map(quoteArgument).join(' ');
}
