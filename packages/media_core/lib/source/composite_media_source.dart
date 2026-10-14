part of 'media_source.dart';

/// Several essence streams that must be presented together.
///
/// [CompositeMediaSource] models the shape DASH produces and, more
/// generally, any input where video, audio and subtitles arrive as
/// independent resources that share one timeline. Each list holds
/// zero or more candidate tracks; the primary one is the first in
/// the list, and downstream layers can rank alternatives by
/// [MediaTrack.bitrate] without reshaping the source.
///
/// The class is deliberately track-list-based rather than two fields
/// (`videoUrl` / `audioUrl`) because multi-audio (dubbing, director's
/// commentary) and multi-subtitle inputs would otherwise force a
/// second model.
///
/// Responsibilities:
///
/// - group parallel essence tracks under one playable input
/// - expose primary-track shortcuts for the common single-variant case
///
/// It does not:
///
/// - merge the essences it carries into one stream
/// - decide which backend plays it
///
/// Those belong to:
///
/// - PlayerAdapter, through `CompositeSupport.native` or
///   `CompositeSupport.externalAudio`
/// - MediaSourcePlanner
@immutable
final class CompositeMediaSource extends MediaSource {
  /// Creates a composite source.
  ///
  /// At least one of [videoTracks] or [audioTracks] must be non-empty.
  /// A source with only subtitles has nothing to time them against,
  /// so it is rejected here rather than left to fail inside an
  /// adapter.
  CompositeMediaSource({
    List<MediaTrack> videoTracks = const <MediaTrack>[],
    List<MediaTrack> audioTracks = const <MediaTrack>[],
    List<MediaTrack> subtitleTracks = const <MediaTrack>[],
    super.live,
  }) : assert(
         videoTracks.isNotEmpty || audioTracks.isNotEmpty,
         'CompositeMediaSource requires at least one video or audio track.',
       ),
       // Stored unmodifiable: a provider that keeps mutating the list
       // it passed in must not be able to change what a planner or
       // adapter sees after the source was handed over.
       videoTracks = List<MediaTrack>.unmodifiable(videoTracks),
       audioTracks = List<MediaTrack>.unmodifiable(audioTracks),
       subtitleTracks = List<MediaTrack>.unmodifiable(subtitleTracks);

  /// Candidate video tracks, ordered by preference.
  final List<MediaTrack> videoTracks;

  /// Candidate audio tracks, ordered by preference.
  final List<MediaTrack> audioTracks;

  /// Candidate subtitle tracks, ordered by preference.
  ///
  /// Subtitles do not affect the assert above: a composite source
  /// exists to combine essences, and a bare subtitle list does not
  /// describe a playable input on its own.
  final List<MediaTrack> subtitleTracks;

  @override
  MediaSourceType get type => MediaSourceType.composite;

  @override
  List<MediaTrack> get tracks {
    return <MediaTrack>[...videoTracks, ...audioTracks, ...subtitleTracks];
  }

  /// The preferred video track, if any.
  MediaTrack? get primaryVideo => videoTracks.isEmpty ? null : videoTracks.first;

  /// The preferred audio track, if any.
  MediaTrack? get primaryAudio => audioTracks.isEmpty ? null : audioTracks.first;

  /// The preferred subtitle track, if any.
  MediaTrack? get primarySubtitle => subtitleTracks.isEmpty ? null : subtitleTracks.first;

  /// Whether this composite has a video essence at all.
  ///
  /// Audio-only DASH inputs (podcast video off, music mode) report
  /// `false` here, which lets a planner short-circuit on the same
  /// signal an adapter uses for its [PlayerAdapterCapabilities.supportsAudioOnly]
  /// check.
  bool get hasVideo => videoTracks.isNotEmpty;

  /// Whether this composite has an audio essence at all.
  bool get hasAudio => audioTracks.isNotEmpty;

  /// Whether this composite carries any subtitles.
  bool get hasSubtitle => subtitleTracks.isNotEmpty;

  /// Creates a copy with modifications.
  ///
  /// Pass a list to replace that group wholesale; pass `null` to leave
  /// it unchanged. Clearing a group means supplying an empty list.
  CompositeMediaSource copyWith({
    List<MediaTrack>? videoTracks,
    List<MediaTrack>? audioTracks,
    List<MediaTrack>? subtitleTracks,
    bool? live,
  }) {
    return CompositeMediaSource(
      videoTracks: videoTracks ?? this.videoTracks,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      live: live ?? this.live,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompositeMediaSource &&
          _listEquals(other.videoTracks, videoTracks) &&
          _listEquals(other.audioTracks, audioTracks) &&
          _listEquals(other.subtitleTracks, subtitleTracks) &&
          other.live == live;

  @override
  int get hashCode => Object.hash(
    MediaSourceType.composite,
    Object.hashAll(videoTracks),
    Object.hashAll(audioTracks),
    Object.hashAll(subtitleTracks),
    live,
  );

  @override
  String toString() {
    return 'CompositeMediaSource(video: ${videoTracks.length}, '
        'audio: ${audioTracks.length}, '
        'subtitle: ${subtitleTracks.length})';
  }
}

bool _listEquals(List<MediaTrack> a, List<MediaTrack> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
