import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_audio/src/track/track_source.dart';

/// Output container for a music download.
enum MusicDownloadFormat {
  /// Keep the source codec/container untouched (`-c:a copy`).
  ///
  /// The right choice whenever the source already is a finished file: it is
  /// lossless, instant, and avoids a re-encode of a lossy source.
  copy,

  /// MP3 (universally playable, small).
  mp3,

  /// AAC in MP4/M4A.
  m4a,

  /// FLAC (lossless).
  flac,

  /// Vorbis in Ogg.
  ogg,

  /// Uncompressed PCM.
  wav,
}

/// Everything one download needs.
///
/// The URL is a [TrackSource] at the moment the request is built, not a
/// resolved-at-run-time thing: music URLs expire, so the caller resolves and
/// hands over a URL that is valid *now* — and can rebuild the request from a
/// fresh resolution when the download is retried later.
final class MusicDownloadRequest {
  /// Creates a request.
  const MusicDownloadRequest({
    required this.url,
    required this.outputPath,
    this.headers = const <String, String>{},
    this.userAgent,
    this.format = MusicDownloadFormat.copy,
    this.bitrateKbps = 320,
    this.expectedDuration,
    this.title,
    this.artist,
    this.album,
    this.extraArguments = const <String>[],
  });

  /// Builds a request for [track] resolved by [source].
  ///
  /// [directory] is the target folder; [pattern] names the file and may use
  /// `{title}`, `{artist}`, `{album}` and `{index}` (a running number the
  /// queue substitutes). The pattern is sanitized for the platform's file
  /// system — music titles contain `/`, `:` and `?` routinely.
  factory MusicDownloadRequest.forTrack({
    required MusicTrack track,
    required TrackSource source,
    required String directory,
    String pattern = '{artist} - {title}',
    MusicDownloadFormat? format,
    int bitrateKbps = 320,
  }) {
    final plan = planFor(source, format: format);
    final separator = directory.endsWith('/') || directory.endsWith(r'\') ? '' : _separatorFor(directory);
    final name = sanitizeFileName(
      pattern
          .replaceAll('{title}', track.title)
          .replaceAll('{artist}', track.artist)
          .replaceAll('{album}', track.album)
          .replaceAll('{index}', ''),
    );

    return MusicDownloadRequest(
      url: source.uri.toString(),
      outputPath: '$directory$separator${name.isEmpty ? track.id : name}.${plan.extension}',
      headers: source.headers,
      format: plan.format,
      bitrateKbps: bitrateKbps,
      expectedDuration: source.duration ?? track.duration,
      title: track.title,
      artist: track.artist,
      album: track.album,
    );
  }

  /// Source URL.
  final String url;

  /// Absolute output path, including the extension.
  final String outputPath;

  /// Request headers (referer, cookie, …).
  final Map<String, String> headers;

  /// User agent, when the source requires one.
  final String? userAgent;

  /// Output container.
  final MusicDownloadFormat format;

  /// Target bitrate for the transcoding formats.
  final int bitrateKbps;

  /// Expected duration, used to turn ffmpeg's progress into a percentage.
  final Duration? expectedDuration;

  /// Track title, written into the file's tags.
  final String? title;

  /// Track artist, written into the file's tags.
  final String? artist;

  /// Album, written into the file's tags.
  final String? album;

  /// Extra ffmpeg arguments appended before the output path.
  final List<String> extraArguments;

  /// Whether this is a stream copy.
  bool get isCopy => format == MusicDownloadFormat.copy;

  /// File extension of [format].
  static String extensionFor(MusicDownloadFormat format) {
    return switch (format) {
      MusicDownloadFormat.copy => 'm4a',
      MusicDownloadFormat.mp3 => 'mp3',
      MusicDownloadFormat.m4a => 'm4a',
      MusicDownloadFormat.flac => 'flac',
      MusicDownloadFormat.ogg => 'ogg',
      MusicDownloadFormat.wav => 'wav',
    };
  }

  /// Decides how a resolved source should be saved.
  ///
  /// Copying is preferred — the platform already encoded the audio once and a
  /// re-encode only loses quality — but a copy is only sound when the source
  /// already *is* a file in a container we can name. A stream URL (`m3u8`,
  /// `ts`, `m4s`, `flv`) is a byte stream whose codec cannot be inferred from
  /// the URL, and writing those bytes into `.m4a` produces a file that does
  /// not play: those are transcoded instead.
  static ({MusicDownloadFormat format, String extension}) planFor(TrackSource source, {MusicDownloadFormat? format}) {
    final sourceExtension = _extensionOf(source.uri);
    final copyable = sourceExtension != null && copyableExtensions.contains(sourceExtension);

    if (format != null && format != MusicDownloadFormat.copy) {
      return (format: format, extension: extensionFor(format));
    }

    if (copyable) {
      return (format: MusicDownloadFormat.copy, extension: sourceExtension);
    }

    // No copyable container: MP3 is what plays everywhere, which is what a
    // downloaded file is for.
    return (format: MusicDownloadFormat.mp3, extension: extensionFor(MusicDownloadFormat.mp3));
  }

  /// Extensions whose bytes can be copied verbatim into the same container.
  static const Set<String> copyableExtensions = <String>{'mp3', 'm4a', 'mp4', 'aac', 'flac', 'ogg', 'opus', 'wav'};

  static String? _extensionOf(Uri uri) {
    final segments = uri.pathSegments;

    if (segments.isEmpty) {
      return null;
    }

    final dot = segments.last.lastIndexOf('.');

    return dot > 0 ? segments.last.substring(dot + 1).toLowerCase() : null;
  }

  /// Removes characters a file name cannot contain or that confuse tooling.
  static String sanitizeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();

    // Trailing dots and spaces are rejected by Windows.
    final trimmed = cleaned.replaceAll(RegExp(r'[. ]+$'), '');

    return trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120).trim();
  }

  static String _separatorFor(String directory) => directory.contains(r'\') ? r'\' : '/';

  @override
  String toString() => 'MusicDownloadRequest($url -> $outputPath, ${format.name})';
}
