import 'package:media_core/identity/source_id.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_format.dart';
import 'package:media_core/source/source_headers.dart';
import 'package:media_core/source/source_media_type.dart';
import 'package:media_core/source/source_protocol.dart';
import 'package:media_core/source/source_type.dart';

/// Bridges a [MediaSource] into the [PlayerSource] representation
/// that today's `PlayerAdapter.open` contract accepts.
///
/// The bridge is deliberately narrow: it flattens the source onto a
/// single primary URI plus merged request headers, and parks the
/// original [MediaSource] under [metadataKey] so an adapter that
/// declares composite support can read the extra tracks without
/// media_core having to break every existing
/// `PlayerAdapter.open(PlayerSource)` implementation.
///
/// Once every backend has migrated to consuming [MediaSource]
/// directly, the bridge disappears — it is the transition, not the
/// destination.
///
/// Responsibilities:
///
/// - project a [MediaSource] onto a [PlayerSource] for existing adapters
///
/// It does not:
///
/// - resolve or fetch any resource
/// - decide which backend plays the source
///
/// Those belong to:
///
/// - SourceService
/// - MediaSourcePlanner
extension MediaSourceBridge on MediaSource {
  /// Well-known [PlayerSource.metadata] key carrying the original
  /// [MediaSource] the bridge was called on.
  ///
  /// Adapters that support composite playback (Media3's
  /// `MergingMediaSource`, MPV's secondary audio channel) read this
  /// entry to recover the track lists the flat [PlayerSource] cannot
  /// express. Providers must not set this key themselves; the bridge
  /// owns it.
  static const String metadataKey = 'media_core.mediaSource';

  /// Converts this source into a [PlayerSource] for the current
  /// adapter contract.
  ///
  /// [id] lets the caller preserve a stable source identity across the
  /// bridge — without it a fresh id is generated per call. [title] is
  /// forwarded verbatim when given.
  PlayerSource toPlayerSource({SourceId? id, String? title}) {
    final primary = _primaryTrackFor(this);
    final mergedHeaders = _mergeHeaders(this);
    final metadata = <String, Object?>{...?primary?.metadata, metadataKey: this};

    return PlayerSource(
      id: id ?? _stableIdFor(primary),
      uri: primary?.uri ?? Uri(),
      type: _sourceTypeFor(this, primary),
      protocol: primary?.protocol ?? SourceProtocol.unknown,
      mediaType: _mediaTypeFor(this, primary),
      format: primary?.format ?? SourceFormat.unknown,
      headers: mergedHeaders,
      title: title,
      metadata: metadata,
    );
  }

  /// The [MediaSource] carried by a bridged [PlayerSource], if any.
  ///
  /// Reads [metadataKey] and returns null when the player source was
  /// not produced by [MediaSourceBridge.toPlayerSource] — a source
  /// that went through `SourceService.resolve` before reaching an
  /// adapter is one example.
  static MediaSource? fromPlayerSource(PlayerSource source) {
    final value = source.metadata[metadataKey];
    return value is MediaSource ? value : null;
  }

  /// The composite carried by a bridged [PlayerSource], if the source
  /// was a [CompositeMediaSource].
  static CompositeMediaSource? compositeFromPlayerSource(PlayerSource source) {
    final value = fromPlayerSource(source);
    return value is CompositeMediaSource ? value : null;
  }
}

MediaTrack? _primaryTrackFor(MediaSource source) {
  if (source case ProgressiveMediaSource(:final track)) {
    return track;
  }
  if (source case CompositeMediaSource()) {
    return source.primaryVideo ?? source.primaryAudio;
  }
  return null;
}

SourceHeaders? _mergeHeaders(MediaSource source) {
  SourceHeaders? result;
  for (final track in source.tracks) {
    final headers = track.headers;
    if (headers == null || headers.isEmpty) {
      continue;
    }
    result = result == null ? headers : result.merge(headers);
  }
  return result;
}

SourceMediaType _mediaTypeFor(MediaSource source, MediaTrack? primary) {
  if (source is CompositeMediaSource) {
    if (source.hasVideo && source.hasAudio) {
      return SourceMediaType.mixed;
    }
    if (source.hasVideo) {
      return SourceMediaType.video;
    }
    return SourceMediaType.audio;
  }
  return primary?.mediaType ?? SourceMediaType.unknown;
}

SourceType _sourceTypeFor(MediaSource source, MediaTrack? primary) {
  // [MediaSource.live] is declared by the provider, so it outranks the
  // protocol mapping below: an HLS event URL is `remote` by scheme and
  // live by declaration, and every downstream live guard (seek refusal,
  // rate refusal, recovery skipping the position restore) keys off
  // `PlayerSource.isLive`. Dropping the flag here turns those guards
  // off for exactly the streams that need them.
  if (source.live) {
    return SourceType.live;
  }
  if (primary == null) {
    return SourceType.unknown;
  }
  switch (primary.protocol) {
    case SourceProtocol.file:
      return SourceType.file;
    case SourceProtocol.asset:
      return SourceType.asset;
    case SourceProtocol.rtmp:
    case SourceProtocol.rtsp:
    case SourceProtocol.webrtc:
    case SourceProtocol.udp:
      return SourceType.live;
    case SourceProtocol.hls:
    case SourceProtocol.dash:
    case SourceProtocol.http:
    case SourceProtocol.https:
      return SourceType.remote;
    case SourceProtocol.custom:
      return SourceType.custom;
    case SourceProtocol.unknown:
      return SourceType.remote;
  }
}

/// A deterministic id derived from the primary track's URI.
///
/// `SourceId.generate()` would make every bridge call look like a new
/// source, so `PlayerHandle.open`'s "did the source change" test
/// would re-announce the same DASH pair on every replay and recovery
/// would see spurious identity churn. A URI-derived id is stable for
/// the same essence and changes exactly when the upstream URL
/// changes — which is precisely when it is a different source.
SourceId _stableIdFor(MediaTrack? primary) {
  final uri = primary?.uri;
  if (uri == null || uri.toString().trim().isEmpty) {
    return SourceId.generate();
  }
  return SourceId(uri.toString());
}
