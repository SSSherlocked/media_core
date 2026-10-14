import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/composition/media_cue.dart';
import 'package:media_core/composition/media_segment.dart';
import 'package:media_core/composition/media_timeline.dart';
import 'package:media_core/composition/timeline_track.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';

MediaTrack _track(String url, MediaTrackType kind, {Duration? startOffset}) {
  return MediaTrack(uri: Uri.parse(url), kind: kind, startOffset: startOffset);
}

void main() {
  group('MediaTimeline.from', () {
    test('progressive source gets a one-track timeline at the origin', () {
      final source = ProgressiveMediaSource(track: _track('https://example.com/v.mp4', MediaTrackType.video));

      final timeline = MediaTimeline.from(source);

      expect(timeline.tracks, hasLength(1));
      expect(timeline.primary!.offset, Duration.zero);
      expect(timeline.originShift, Duration.zero);
      expect(timeline.primary!.isAtOrigin, isTrue);
    });

    test('composite startOffsets align onto one presentation clock', () {
      final source = CompositeMediaSource(
        videoTracks: [
          _track('https://example.com/v.m4s', MediaTrackType.video, startOffset: const Duration(milliseconds: 40)),
        ],
        audioTracks: [_track('https://example.com/a.m4s', MediaTrackType.audio)],
      );

      final timeline = MediaTimeline.from(source);

      final video = timeline[source.videoTracks.first]!;
      final audio = timeline[source.audioTracks.first]!;

      // The earliest track (audio, offset zero) anchors the clock;
      // the video trails it by its declared 40 ms.
      expect(audio.offset, Duration.zero);
      expect(video.offset, const Duration(milliseconds: 40));
      expect(timeline.originShift, Duration.zero);
    });

    test('a shared period base is normalized away as originShift', () {
      final source = CompositeMediaSource(
        videoTracks: [
          _track('https://example.com/v.m4s', MediaTrackType.video, startOffset: const Duration(seconds: 6)),
        ],
        audioTracks: [
          _track(
            'https://example.com/a.m4s',
            MediaTrackType.audio,
            startOffset: const Duration(seconds: 6, milliseconds: 20),
          ),
        ],
      );

      final timeline = MediaTimeline.from(source);

      // Both periods share a 6 s base; the presentation clock starts
      // at that base, not at wall-clock zero of the media files.
      expect(timeline.originShift, const Duration(seconds: 6));
      expect(timeline.primary!.offset, Duration.zero);
      expect(timeline[source.audioTracks.first]!.offset, const Duration(milliseconds: 20));
    });

    test('missing offsets are treated as zero, not failures', () {
      final source = CompositeMediaSource(
        videoTracks: [_track('https://example.com/v.m4s', MediaTrackType.video)],
        audioTracks: [
          _track('https://example.com/a.m4s', MediaTrackType.audio, startOffset: const Duration(milliseconds: 10)),
        ],
      );

      final timeline = MediaTimeline.from(source);

      expect(timeline[source.videoTracks.first]!.offset, Duration.zero);
      expect(timeline[source.audioTracks.first]!.offset, const Duration(milliseconds: 10));
    });

    test('primary prefers video, then audio, then any track', () {
      final videoFirst = CompositeMediaSource(
        videoTracks: [_track('https://example.com/v.m4s', MediaTrackType.video)],
        audioTracks: [_track('https://example.com/a.m4s', MediaTrackType.audio)],
      );
      final audioOnly = CompositeMediaSource(audioTracks: [_track('https://example.com/a.m4s', MediaTrackType.audio)]);

      expect(MediaTimeline.from(videoFirst).primary!.track.kind, MediaTrackType.video);
      expect(MediaTimeline.from(audioOnly).primary!.track.kind, MediaTrackType.audio);
    });

    test('time conversion round-trips per track', () {
      final source = CompositeMediaSource(
        videoTracks: [_track('https://example.com/v.m4s', MediaTrackType.video)],
        audioTracks: [
          _track('https://example.com/a.m4s', MediaTrackType.audio, startOffset: const Duration(milliseconds: 30)),
        ],
      );

      final timeline = MediaTimeline.from(source);
      final track = source.audioTracks.first;
      const mediaTime = Duration(seconds: 5);

      final presentation = timeline.presentationTimeFor(track, mediaTime);
      expect(presentation, const Duration(seconds: 5, milliseconds: 30));
      expect(timeline.mediaTimeFor(track, presentation), mediaTime);
    });

    test('an unmapped track passes time through unchanged', () {
      final timeline = MediaTimeline.from(
        ProgressiveMediaSource(track: _track('https://example.com/v.mp4', MediaTrackType.video)),
      );
      final stranger = _track('https://example.com/other.mp4', MediaTrackType.audio);

      expect(timeline.presentationTimeFor(stranger, const Duration(seconds: 1)), const Duration(seconds: 1));
    });
  });

  group('MediaSegment', () {
    test('covers is start-inclusive end-exclusive', () {
      final segment = MediaSegment(
        start: const Duration(seconds: 10),
        duration: const Duration(seconds: 5),
        label: 'chapter-2',
      );

      expect(segment.end, const Duration(seconds: 15));
      expect(segment.covers(const Duration(seconds: 10)), isTrue);
      expect(segment.covers(const Duration(seconds: 14, milliseconds: 999)), isTrue);
      expect(segment.covers(const Duration(seconds: 15)), isFalse);
    });

    test('intersects and shiftedBy compose ranges', () {
      final a = MediaSegment(start: Duration.zero, duration: const Duration(seconds: 4));
      final b = MediaSegment(start: const Duration(seconds: 3), duration: const Duration(seconds: 2));
      final c = a.shiftedBy(const Duration(seconds: 10));

      expect(a.intersects(b), isTrue);
      expect(a.intersects(c), isFalse);
      expect(c.start, const Duration(seconds: 10));
      expect(c.label, isNull);
    });

    test('timeline segmentAt finds the covering segment', () {
      final timeline = MediaTimeline(
        tracks: [TimelineTrack(track: _track('https://example.com/v.mp4', MediaTrackType.video))],
        segments: [
          MediaSegment(start: Duration.zero, duration: const Duration(seconds: 30)),
          MediaSegment(start: const Duration(seconds: 30), duration: const Duration(seconds: 30)),
        ],
      );

      expect(timeline.segmentAt(const Duration(seconds: 45)), same(timeline.segments[1]));
      expect(timeline.segmentAt(const Duration(minutes: 5)), isNull);
    });
  });

  group('MediaCue', () {
    test('covers spans the cue window', () {
      final cue = MediaCue(start: const Duration(seconds: 2), end: const Duration(seconds: 5), text: 'hello');

      expect(cue.duration, const Duration(seconds: 3));
      expect(cue.covers(const Duration(seconds: 2)), isTrue);
      expect(cue.covers(const Duration(seconds: 5)), isFalse);
    });

    test('cuesAt returns every active cue', () {
      final timeline = MediaTimeline(
        tracks: [TimelineTrack(track: _track('https://example.com/v.mp4', MediaTrackType.video))],
        cues: [
          MediaCue(start: Duration.zero, end: const Duration(seconds: 3), text: 'a'),
          MediaCue(start: const Duration(seconds: 1), end: const Duration(seconds: 3), text: 'b'),
          MediaCue(start: const Duration(seconds: 4), end: const Duration(seconds: 6), text: 'c'),
        ],
      );

      final active = timeline.cuesAt(const Duration(seconds: 2));

      expect(active.map((c) => c.text), ['a', 'b']);
      expect(timeline.cuesAt(const Duration(seconds: 5)).map((c) => c.text), ['c']);
    });
  });
}
