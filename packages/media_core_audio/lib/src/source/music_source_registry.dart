import 'dart:io';
import 'package:media_core_audio/src/source/local_music_source.dart' show LocalMusicSource;
import 'package:media_core_audio/src/source/music_source.dart';
import 'package:media_core_audio/src/track/music_quality.dart';
import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_audio/src/track/track_source.dart';

/// Raised when a track names a source that is not registered (or is disabled).
final class MusicSourceNotFoundException implements Exception {
  /// Creates the exception.
  const MusicSourceNotFoundException(this.sourceId);

  /// The source that could not be resolved.
  final String sourceId;

  @override
  String toString() => 'MusicSourceNotFoundException($sourceId)';
}

/// Registry of the music sources an app ships.
///
/// One registry instance usually lives for the whole app, mirroring how
/// lx-music keeps a fixed "音源" list: tracks reference a source by [MusicTrack.sourceId],
/// and [resolveTrackSource] is the only place that turns a track back into a
/// network request.
///
/// A source can be registered but disabled: the host's settings page toggles
/// it without the queue losing the tracks that came from it.
final class MusicSourceRegistry {
  /// Creates a registry.
  MusicSourceRegistry([Iterable<MusicSource> sources = const <MusicSource>[]]) {
    sources.forEach(register);
  }

  final Map<String, MusicSource> _sources = <String, MusicSource>{};
  final Set<String> _disabled = <String>{};

  /// Registered sources, in registration order.
  List<MusicSource> get sources => List<MusicSource>.unmodifiable(_sources.values);

  /// Identifiers of registered sources.
  List<String> get ids => List<String>.unmodifiable(_sources.keys);

  /// Whether the registry is empty.
  bool get isEmpty => _sources.isEmpty;

  /// Registers (or replaces) [source].
  void register(MusicSource source) {
    _sources[source.id] = source;
  }

  /// Removes a source.
  void unregister(String id) {
    _sources.remove(id);
    _disabled.remove(id);
  }

  /// Marks a source enabled or disabled.
  void setEnabled(String id, {required bool enabled}) {
    if (enabled) {
      _disabled.remove(id);
    } else {
      _disabled.add(id);
    }
  }

  /// Whether a source is registered and enabled.
  bool isEnabled(String id) => _sources.containsKey(id) && !_disabled.contains(id);

  /// Looks a source up, enabled or not.
  MusicSource? find(String id) => _sources[id];

  /// Looks a source up and throws when it is missing or disabled.
  MusicSource require(String id) {
    final source = _sources[id];

    if (source == null || _disabled.contains(id)) {
      throw MusicSourceNotFoundException(id);
    }

    return source;
  }

  /// Resolves [track] to a playable source through its own platform.
  ///
  /// The `quality` request is forwarded as-is; a source that cannot honour it
  /// reports what it actually served on the returned [TrackSource].
  ///
  /// A local track bypasses the registry: there is nothing to ask a platform
  /// for, and requiring a registered [LocalMusicSource] just to play a file
  /// would make the queue's behaviour depend on registration order. A missing
  /// file fails here, as a `FileSystemException`.
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) async {
    if (track.isLocal) {
      final file = File(track.localPath ?? track.id);

      if (!file.existsSync()) {
        throw FileSystemException('Local track not found', file.path);
      }

      return TrackSource(uri: file.uri, isLocal: true, fileSize: await file.length());
    }

    return await require(track.sourceId).resolveTrackSource(track, quality: quality);
  }

  /// Fetches the lyric for [track] through its own platform.
  Future<MusicLyricPayload?> resolveLyric(MusicTrack track) {
    final source = _sources[track.sourceId];

    if (source == null || _disabled.contains(track.sourceId)) {
      return Future<MusicLyricPayload?>.value();
    }

    return source.resolveLyric(track);
  }
}
