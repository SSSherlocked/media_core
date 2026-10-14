import 'package:media_core/media_core.dart';
import 'package:media_core_audio/media_core_audio.dart' show AudioPlaybackController, MusicSource;

import 'package:media_core_audio/src/track/music_quality.dart';

/// A resolved, immediately playable URL for one track.
///
/// This is the boundary between "music" and "player": [MusicSource] produces
/// it, [AudioPlaybackController] turns it into a [PlayerSource] and hands that
/// to the kernel. Everything a signed URL needs to stay usable travels here —
/// headers, the container hint and, crucially, [expiresAt]:
///
/// Music platforms sign playback URLs with a short TTL (a few minutes). A URL
/// that is still cached when the user reaches that track has to be refreshed
/// instead of replayed, or the play attempt fails on an expired signature —
/// the same failure mode the live module handles for its lines.
final class TrackSource {
  /// Creates a resolved source.
  const TrackSource({
    required this.uri,
    this.headers = const <String, String>{},
    this.quality,
    this.format,
    this.duration,
    this.expiresAt,
    this.fileSize,
    this.isLocal = false,
  });

  /// Playable location.
  final Uri uri;

  /// HTTP headers the platform requires (referer, cookie, …).
  final Map<String, String> headers;

  /// Quality actually served — a source may downgrade a request.
  final MusicQuality? quality;

  /// Container hint, when the resolution knows it.
  final SourceFormat? format;

  /// Duration the platform reported for this rendition.
  final Duration? duration;

  /// Instant after which [uri] must not be used to start a new connection.
  ///
  /// Null means "no known expiry" (local files, unsigned CDNs).
  final DateTime? expiresAt;

  /// Output size in bytes, when known (drives the downloader's progress).
  final int? fileSize;

  /// Whether this points at a local file rather than a network resource.
  final bool isLocal;

  /// Whether the signed URL is past its usable lifetime.
  bool isExpired({DateTime? now}) {
    final deadline = expiresAt;

    return deadline != null && !(now ?? DateTime.now()).isBefore(deadline);
  }

  /// Time left before [expiresAt], or null when there is no deadline.
  Duration? remainingLifetime({DateTime? now}) {
    final deadline = expiresAt;

    return deadline?.difference(now ?? DateTime.now());
  }

  /// Adapts this resolution into the kernel's source type.
  ///
  /// [trackId] only names the source for diagnostics/events; the playback
  /// identity of a track is the track itself.
  PlayerSource toPlayerSource({String? trackId, String? title}) {
    return PlayerSource(
      id: SourceId('music_${trackId ?? uri.pathSegments.join('_')}_${uri.path.hashCode}'),
      uri: uri,
      type: isLocal ? SourceType.file : SourceType.remote,
      protocol: SourceProtocol.fromScheme(uri.scheme),
      mediaType: SourceMediaType.audio,
      format: format ?? SourceFormat.fromUri(uri),
      headers: headers.isEmpty ? null : SourceHeaders(headers),
      title: title,
      metadata: <String, Object?>{
        if (quality != null) 'quality': quality!.id,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      },
    );
  }

  @override
  String toString() => 'TrackSource(${quality?.id ?? 'auto'}, $uri${isExpired() ? ', expired' : ''})';
}
