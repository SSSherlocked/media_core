import 'package:media_core/source/source_protocol.dart' show SourceProtocol;

/// Describes the container or media file format of a source.
///
/// [SourceFormat] describes the format of the media resource itself.
/// Transport protocols such as HTTP, HLS, RTSP, and DASH belong to
/// [SourceProtocol] instead.
enum SourceFormat {
  /// Unknown or not yet determined.
  unknown,

  /// MPEG-4 container.
  mp4,

  /// MPEG-TS container.
  mpegTs,

  /// Matroska container.
  mkv,

  /// WebM container.
  webm,

  /// AVI container.
  avi,

  /// QuickTime / MOV container.
  mov,

  /// Flash Video container.
  flv,

  /// Ogg container.
  ogg,

  /// WebVTT subtitle format.
  webVtt,

  /// SubRip subtitle format.
  srt,

  /// Advanced SubStation Alpha subtitle format.
  ass,

  /// MPEG-DASH manifest.
  mpd,

  /// HTTP Live Streaming manifest.
  m3u8,

  /// Audio-only MPEG format.
  mp3,

  /// AAC audio format.
  aac,

  /// FLAC audio format.
  flac,

  /// WAV audio format.
  wav,

  /// Opus audio format.
  opus,

  /// Application-defined custom format.
  custom;

  /// Infers a format from a file extension (with or without the dot).
  ///
  /// Returns [SourceFormat.unknown] when the extension says nothing, which
  /// is the honest answer: a wrong guess would silently change which
  /// backend the selector picks.
  static SourceFormat fromExtension(String? extension) {
    var normalized = extension?.trim().toLowerCase() ?? '';

    if (normalized.startsWith('.')) {
      normalized = normalized.substring(1);
    }

    switch (normalized) {
      case 'mp4':
      case 'm4v':
        return SourceFormat.mp4;

      case 'ts':
      case 'm2ts':
      case 'mts':
        return SourceFormat.mpegTs;

      case 'mkv':
        return SourceFormat.mkv;

      case 'webm':
        return SourceFormat.webm;

      case 'avi':
        return SourceFormat.avi;

      case 'mov':
        return SourceFormat.mov;

      case 'flv':
        return SourceFormat.flv;

      case 'ogv':
      case 'oga':
      case 'ogg':
        return SourceFormat.ogg;

      case 'vtt':
        return SourceFormat.webVtt;

      case 'srt':
        return SourceFormat.srt;

      case 'ass':
      case 'ssa':
        return SourceFormat.ass;

      case 'mpd':
        return SourceFormat.mpd;

      case 'm3u':
      case 'm3u8':
        return SourceFormat.m3u8;

      case 'mp3':
        return SourceFormat.mp3;

      case 'aac':
      case 'm4a':
        return SourceFormat.aac;

      case 'flac':
        return SourceFormat.flac;

      case 'wav':
        return SourceFormat.wav;

      case 'opus':
        return SourceFormat.opus;

      default:
        return SourceFormat.unknown;
    }
  }

  /// Returns the file extension of a URI's path, lowercased and without
  /// the dot, or `null` when the path carries none.
  ///
  /// The raw extension rather than a [SourceFormat] value, because the
  /// enum models a subset of what a URI can name: `.rmvb`, `.ape`, `.nut`
  /// and friends have no enum value, and a capability declaration that
  /// lists them can only ever be matched against the extension itself.
  ///
  /// A URI with no usable extension — a bare host, a query-only stream
  /// URL, `.../live/stream` — yields `null`.
  static String? extensionOf(Uri uri) {
    final segments = uri.pathSegments;

    if (segments.isEmpty) {
      return null;
    }

    final last = segments.last;
    final dot = last.lastIndexOf('.');

    if (dot < 0 || dot == last.length - 1) {
      return null;
    }

    return last.substring(dot + 1).toLowerCase();
  }

  /// Infers a format from a URI's path.
  ///
  /// Yields [SourceFormat.unknown] when the path has no extension or names
  /// a container [SourceFormat] does not model.
  static SourceFormat fromUri(Uri uri) {
    return fromExtension(extensionOf(uri));
  }
}

/// Extensions for [SourceFormat].
extension SourceFormatX on SourceFormat {
  /// Whether this format is unknown.
  bool get isUnknown => this == SourceFormat.unknown;

  /// Whether this format is known.
  bool get isKnown => this != SourceFormat.unknown;

  /// Whether this is a video container format.
  bool get isVideo {
    switch (this) {
      case SourceFormat.mp4:
      case SourceFormat.mpegTs:
      case SourceFormat.mkv:
      case SourceFormat.webm:
      case SourceFormat.avi:
      case SourceFormat.mov:
      case SourceFormat.flv:
        return true;

      case SourceFormat.unknown:
      case SourceFormat.webVtt:
      case SourceFormat.srt:
      case SourceFormat.ass:
      case SourceFormat.mpd:
      case SourceFormat.m3u8:
      case SourceFormat.mp3:
      case SourceFormat.aac:
      case SourceFormat.flac:
      case SourceFormat.wav:
      case SourceFormat.opus:
      case SourceFormat.ogg:
      case SourceFormat.custom:
        return false;
    }
  }

  /// Whether this is an audio format.
  bool get isAudio {
    switch (this) {
      case SourceFormat.mp3:
      case SourceFormat.aac:
      case SourceFormat.flac:
      case SourceFormat.wav:
      case SourceFormat.opus:
      case SourceFormat.ogg:
        return true;

      case SourceFormat.unknown:
      case SourceFormat.mp4:
      case SourceFormat.mpegTs:
      case SourceFormat.mkv:
      case SourceFormat.webm:
      case SourceFormat.avi:
      case SourceFormat.mov:
      case SourceFormat.flv:
      case SourceFormat.webVtt:
      case SourceFormat.srt:
      case SourceFormat.ass:
      case SourceFormat.mpd:
      case SourceFormat.m3u8:
      case SourceFormat.custom:
        return false;
    }
  }

  /// Whether this is a subtitle format.
  bool get isSubtitle {
    switch (this) {
      case SourceFormat.webVtt:
      case SourceFormat.srt:
      case SourceFormat.ass:
        return true;

      case SourceFormat.unknown:
      case SourceFormat.mp4:
      case SourceFormat.mpegTs:
      case SourceFormat.mkv:
      case SourceFormat.webm:
      case SourceFormat.avi:
      case SourceFormat.mov:
      case SourceFormat.flv:
      case SourceFormat.mpd:
      case SourceFormat.m3u8:
      case SourceFormat.mp3:
      case SourceFormat.aac:
      case SourceFormat.flac:
      case SourceFormat.wav:
      case SourceFormat.opus:
      case SourceFormat.ogg:
      case SourceFormat.custom:
        return false;
    }
  }

  /// Whether this is a streaming manifest format.
  bool get isManifest {
    return this == SourceFormat.m3u8 || this == SourceFormat.mpd;
  }

  /// Returns the conventional file extension without the leading dot.
  String? get extension {
    switch (this) {
      case SourceFormat.mp4:
        return 'mp4';
      case SourceFormat.mpegTs:
        return 'ts';
      case SourceFormat.mkv:
        return 'mkv';
      case SourceFormat.webm:
        return 'webm';
      case SourceFormat.avi:
        return 'avi';
      case SourceFormat.mov:
        return 'mov';
      case SourceFormat.flv:
        return 'flv';
      case SourceFormat.ogg:
        return 'ogg';
      case SourceFormat.webVtt:
        return 'vtt';
      case SourceFormat.srt:
        return 'srt';
      case SourceFormat.ass:
        return 'ass';
      case SourceFormat.mpd:
        return 'mpd';
      case SourceFormat.m3u8:
        return 'm3u8';
      case SourceFormat.mp3:
        return 'mp3';
      case SourceFormat.aac:
        return 'aac';
      case SourceFormat.flac:
        return 'flac';
      case SourceFormat.wav:
        return 'wav';
      case SourceFormat.opus:
        return 'opus';
      case SourceFormat.unknown:
      case SourceFormat.custom:
        return null;
    }
  }

  /// Returns the stable string representation of this format.
  String get value => name;
}
