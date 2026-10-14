import 'dart:io';

import 'package:media_core_audio/src/source/music_source.dart';
import 'package:media_core_audio/src/track/music_quality.dart';
import 'package:media_core_audio/src/track/music_track.dart';
import 'package:media_core_audio/src/track/track_source.dart';

/// A [MusicSource] over the device's own files.
///
/// Local music is not a special case in the queue — it is just a source whose
/// resolution is a `file:` URI and whose "search" walks directories. Keeping
/// it in the same contract is what lets a playlist mix streamed and downloaded
/// tracks (lx-music's local library behaves the same way).
final class LocalMusicSource extends MusicSource {
  /// Creates a local source over [roots].
  ///
  /// [extensions] is matched case-insensitively against the file suffix.
  LocalMusicSource({
    required this.roots,
    this.id = MusicTrack.localSourceId,
    this.name = '本地音乐',
    this.extensions = defaultExtensions,
    this.maxFilesPerScan = 5000,
  });

  /// Audio containers this source accepts, without the leading dot.
  static const List<String> defaultExtensions = <String>[
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
    'ape',
    'wma',
    'dsf',
  ];

  @override
  final String id;

  @override
  final String name;

  /// Directories to scan.
  final List<String> roots;

  /// Accepted file suffixes.
  final List<String> extensions;

  /// Safety cap so a mis-pointed root cannot hang the app.
  final int maxFilesPerScan;

  /// Lists the audio files under [roots].
  ///
  /// Title falls back to the file name without its extension, artist stays
  /// empty: a bare file has no tags here — hosts that want tags should enrich
  /// the returned tracks through [trackDetail].
  @override
  Future<MusicSourcePage<MusicTrack>> search(String keyword, {int page = 1, int pageSize = 30}) async {
    final all = await listTracks();
    final needle = keyword.trim().toLowerCase();

    final matched = needle.isEmpty
        ? all
        : all
              .where(
                (track) => track.title.toLowerCase().contains(needle) || track.artist.toLowerCase().contains(needle),
              )
              .toList(growable: false);

    final start = ((page - 1) * pageSize).clamp(0, matched.length);
    final end = (start + pageSize).clamp(0, matched.length);

    return MusicSourcePage<MusicTrack>(
      items: matched.sublist(start, end),
      page: page,
      hasMore: end < matched.length,
      total: matched.length,
    );
  }

  /// Scans [roots] for playable files.
  Future<List<MusicTrack>> listTracks() async {
    final tracks = <MusicTrack>[];

    for (final root in roots) {
      final directory = Directory(root);

      if (!directory.existsSync()) {
        continue;
      }

      try {
        await for (final entity in directory.list(recursive: true, followLinks: false)) {
          if (entity is! File || !_isAudio(entity.path)) {
            continue;
          }

          tracks.add(MusicTrack.local(path: entity.path, title: _titleOf(entity.path)));

          if (tracks.length >= maxFilesPerScan) {
            return tracks;
          }
        }
      } on FileSystemException {
        // An unreadable root contributes nothing; the rest of the library
        // still loads.
      }
    }

    tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return tracks;
  }

  /// Resolves a local track to its file URI.
  @override
  Future<TrackSource> resolveTrackSource(MusicTrack track, {MusicQuality? quality}) async {
    final path = track.localPath ?? track.id;
    final file = File(path);

    if (!file.existsSync()) {
      throw StateError('Local track not found: $path');
    }

    return TrackSource(
      uri: file.uri,
      isLocal: true,
      quality: const MusicQuality(id: 'local', label: '本地', sort: 99),
      fileSize: file.lengthSync(),
    );
  }

  /// Reads a sidecar `.lrc` next to the audio file.
  @override
  Future<MusicLyricPayload?> resolveLyric(MusicTrack track) async {
    final path = track.localPath ?? track.id;
    final dot = path.lastIndexOf('.');

    if (dot <= 0) {
      return null;
    }

    final lyricFile = File('${path.substring(0, dot)}.lrc');

    if (!lyricFile.existsSync()) {
      return null;
    }

    try {
      return MusicLyricPayload(lyric: await lyricFile.readAsString());
    } on FileSystemException {
      return null;
    }
  }

  bool _isAudio(String path) {
    final dot = path.lastIndexOf('.');

    if (dot <= 0 || dot == path.length - 1) {
      return false;
    }

    final suffix = path.substring(dot + 1).toLowerCase();

    return extensions.contains(suffix);
  }

  String _titleOf(String path) {
    final separator = path.lastIndexOf(RegExp(r'[\\/]'));
    final fileName = separator >= 0 ? path.substring(separator + 1) : path;
    final dot = fileName.lastIndexOf('.');

    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}
