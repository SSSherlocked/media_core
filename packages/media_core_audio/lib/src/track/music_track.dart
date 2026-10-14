import 'package:flutter/foundation.dart' show immutable;
import 'package:media_core_audio/media_core_audio.dart' show MusicSource, TrackSource;
import 'package:media_core_audio/src/track/music_quality.dart';

/// One playable piece of music, independent of where it came from.
///
/// Identity is `(sourceId, id)`: two platforms may hand out the same numeric
/// id for different songs, and the same song reachable through two sources is
/// two tracks (that is what lx-music's "换源" is: re-resolving the *same*
/// logical song against another [MusicSource]).
///
/// The model deliberately carries no playback URL: a URL is short-lived and
/// belongs to [TrackSource], resolved per playback attempt. Keeping them apart
/// is what lets a queue survive a signed URL expiring.
@immutable
final class MusicTrack {
  /// Creates a track.
  const MusicTrack({
    required this.id,
    required this.title,
    this.sourceId = '',
    this.artist = '',
    this.album = '',
    this.albumId,
    this.duration,
    this.coverUri,
    this.qualities = const <MusicQuality>[],
    this.localPath,
    this.metadata = const <String, Object?>{},
  });

  /// Creates a track backed by a local file.
  factory MusicTrack.local({required String path, required String title, String artist = '', Duration? duration}) {
    return MusicTrack(
      id: path,
      title: title,
      artist: artist,
      duration: duration,
      localPath: path,
      sourceId: localSourceId,
    );
  }

  /// [sourceId] of tracks that live on disk.
  static const String localSourceId = 'local';

  /// Source-scoped identifier (platform id, file path, …).
  final String id;

  /// Display title.
  final String title;

  /// Identifier of the [MusicSource] that produced this track.
  final String sourceId;

  /// Performing artist(s), as one display string.
  final String artist;

  /// Album name.
  final String album;

  /// Source-scoped album identifier, when the platform has one.
  final String? albumId;

  /// Duration, when known before playback.
  final Duration? duration;

  /// Cover art.
  final Uri? coverUri;

  /// Tiers this source advertises for the track; may be empty until
  /// [MusicSource.qualities] is called.
  final List<MusicQuality> qualities;

  /// Absolute path for a local track.
  final String? localPath;

  /// Source-specific extras (platform ids, lyric ids, …).
  final Map<String, Object?> metadata;

  /// Whether the track plays from disk.
  bool get isLocal => localPath != null || sourceId == localSourceId;

  /// `artist - title`, the conventional list label.
  String get displayName => artist.trim().isEmpty ? title : '$artist - $title';

  /// Reads one metadata entry.
  T? metadataValue<T>(String key) {
    final value = metadata[key];

    return value is T ? value : null;
  }

  /// Creates a copy with selected fields replaced.
  MusicTrack copyWith({
    String? id,
    String? title,
    String? sourceId,
    String? artist,
    String? album,
    String? albumId,
    Duration? duration,
    Uri? coverUri,
    List<MusicQuality>? qualities,
    String? localPath,
    Map<String, Object?>? metadata,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceId: sourceId ?? this.sourceId,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      duration: duration ?? this.duration,
      coverUri: coverUri ?? this.coverUri,
      qualities: qualities ?? this.qualities,
      localPath: localPath ?? this.localPath,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) => other is MusicTrack && other.id == id && other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(sourceId, id);

  @override
  String toString() => 'MusicTrack($displayName${isLocal ? ', local' : ' @$sourceId'})';
}

/// One page of a paged music query.
final class MusicSourcePage<T> {
  /// Creates a page.
  const MusicSourcePage({required this.items, this.page = 1, this.hasMore = false, this.total});

  /// An empty page.
  const MusicSourcePage.empty() : this(items: const <Never>[]);

  /// Page items.
  final List<T> items;

  /// 1-based page number.
  final int page;

  /// Whether another page follows.
  final bool hasMore;

  /// Total result count, when the platform reports one.
  final int? total;
}
