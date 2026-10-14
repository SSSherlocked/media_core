import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/composition/composed_schedule.dart';
import 'package:media_core/composition/media_break.dart';
import 'package:media_core/composition/playback_schedule.dart';
import 'package:media_core/composition/schedule_clip.dart';
import 'package:media_core/composition/schedule_navigator.dart';
import 'package:media_core/composition/timeline_composer.dart';
import 'package:media_core/source/media_source.dart';

MediaSource _source(String url) => ProgressiveMediaSource.url(Uri.parse(url));

ScheduleClip content(String url, int seconds) => ScheduleClip(
  source: _source(url),
  duration: Duration(seconds: seconds),
);

ScheduleClip ad(String url, int seconds, {Duration? skipAfter}) => ScheduleClip(
  source: _source(url),
  duration: Duration(seconds: seconds),
  kind: ClipKind.advertisement,
  skipAfter: skipAfter,
);

ScheduleClip filler(String url, int seconds) => ScheduleClip(
  source: _source(url),
  duration: Duration(seconds: seconds),
  kind: ClipKind.filler,
);

MediaBreak pod(BreakPosition position, List<ScheduleClip> clips) => MediaBreak(position: position, clips: clips);

void main() {
  group('TimelineComposer placement', () {
    test('no breaks: the program is the whole timeline', () {
      final composed = const TimelineComposer().compose(PlaybackSchedule(program: content('https://e.com/p.mp4', 100)));

      expect(composed.segments, hasLength(1));
      expect(composed.totalDuration, const Duration(seconds: 100));
      expect(composed.segments.single.programTime, Duration.zero);
    });

    test('pre-roll lands before the program and content keeps program time', () {
      final composed = const TimelineComposer().compose(
        PlaybackSchedule(
          program: content('https://e.com/p.mp4', 100),
          breaks: [
            pod(const PreRoll(), [ad('https://e.com/a1.mp4', 15)]),
          ],
        ),
      );

      expect(composed.totalDuration, const Duration(seconds: 115));
      expect(composed.segments[0].clip.kind, ClipKind.advertisement);
      expect(composed.segments[0].start, Duration.zero);
      // Content resumes at program zero even though combined time is 15s.
      expect(composed.segments[1].clip.kind, ClipKind.content);
      expect(composed.segments[1].start, const Duration(seconds: 15));
      expect(composed.segments[1].programTime, Duration.zero);
    });

    test('mid-roll splits content into two pieces with exact program times', () {
      final composed = const TimelineComposer().compose(
        PlaybackSchedule(
          program: content('https://e.com/p.mp4', 100),
          breaks: [
            pod(AtProgramOffset(const Duration(seconds: 40)), [
              ad('https://e.com/a1.mp4', 10),
              ad('https://e.com/a2.mp4', 5),
            ]),
          ],
        ),
      );

      expect(composed.totalDuration, const Duration(seconds: 115));
      expect(composed.segments[0].programTime, Duration.zero);
      expect(composed.segments[0].end, const Duration(seconds: 40));
      // Pod clips carry no program time — they are not the program.
      expect(composed.segments[1].programTime, isNull);
      expect(composed.segments[3].clip.kind, ClipKind.content);
      expect(composed.segments[3].start, const Duration(seconds: 55));
      // The tail content segment knows exactly where the program resumes.
      expect(composed.segments[3].programTime, const Duration(seconds: 40));
    });

    test('post-roll follows the program tail, pre-roll precedes it', () {
      final composed = const TimelineComposer().compose(
        PlaybackSchedule(
          program: content('https://e.com/p.mp4', 100),
          breaks: [
            pod(AtProgramOffset(const Duration(seconds: 60)), [ad('mid', 5)]),
            pod(PostRoll(const Duration(seconds: 100)), [ad('post', 10)]),
            pod(const PreRoll(), [ad('pre', 15)]),
          ],
        ),
      );

      final kinds = composed.segments.map((s) => s.clip.kind.name).toList();
      expect(kinds, ['advertisement', 'content', 'advertisement', 'content', 'advertisement']);
      // pre(15) + content 0..60 + mid(5) + content 60..100 + post(10) = 130
      expect(composed.totalDuration, const Duration(seconds: 130));

      expect(composed.segments[2].start, const Duration(seconds: 75));
      expect(composed.segments[4].start, const Duration(seconds: 120));
    });

    test('a zero-duration clip is dropped, not placed', () {
      final composed = const TimelineComposer().compose(
        PlaybackSchedule(
          program: content('https://e.com/p.mp4', 100),
          breaks: [
            pod(const PreRoll(), [ad('https://e.com/zero.mp4', 0)]),
          ],
        ),
      );

      expect(composed.segments, hasLength(1));
      expect(composed.totalDuration, const Duration(seconds: 100));
    });

    test('programTimeAt maps combined time back to the program', () {
      final composed = const TimelineComposer().compose(
        PlaybackSchedule(
          program: content('https://e.com/p.mp4', 100),
          breaks: [
            pod(const PreRoll(), [ad('https://e.com/a1.mp4', 15)]),
          ],
        ),
      );

      final tail = composed.segments[1];
      expect(tail.programTimeAt(const Duration(seconds: 20)), const Duration(seconds: 5));
      // Outside the segment: no answer rather than a wrong one.
      expect(tail.programTimeAt(const Duration(seconds: 5)), isNull);
    });
  });

  group('PlaybackSchedule validation', () {
    test('a mid-roll past the program end is rejected at construction', () {
      expect(
        () => PlaybackSchedule(
          program: content('https://e.com/p.mp4', 30),
          breaks: [
            pod(AtProgramOffset(const Duration(seconds: 45)), [ad('late', 5)]),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('content clips cannot be scheduled inside a break', () {
      expect(
        () => PlaybackSchedule(
          program: content('https://e.com/p.mp4', 100),
          breaks: [
            pod(const PreRoll(), [content('other', 10)]),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ScheduleNavigator', () {
    ComposedSchedule composed() => const TimelineComposer().compose(
      PlaybackSchedule(
        program: content('https://e.com/p.mp4', 100),
        breaks: [
          pod(const PreRoll(), [ad('https://e.com/a1.mp4', 15, skipAfter: const Duration(seconds: 5))]),
          pod(AtProgramOffset(const Duration(seconds: 40)), [ad('https://e.com/a2.mp4', 10)]),
        ],
      ),
    );

    test('crossing into an ad opens it with no seek', () {
      final navigator = ScheduleNavigator(composed());

      final first = navigator.observe(Duration.zero);
      expect(first.actions, hasLength(1));
      expect((first.actions.single as OpenClip).clip.kind, ClipKind.advertisement);

      // Still inside the ad: no new action.
      expect(navigator.observe(const Duration(seconds: 3)).actions, isEmpty);

      // Crossing back to content re-opens the program at its resume point.
      final resume = navigator.observe(const Duration(seconds: 15));
      final action = resume.actions.single as OpenClip;
      expect(action.clip.kind, ClipKind.content);
      expect(action.seekTo, Duration.zero);
    });

    test('skippable surfaces exactly at the skip point', () {
      final navigator = ScheduleNavigator(composed());

      expect(navigator.observe(Duration.zero).skipAvailable, isFalse);
      expect(navigator.observe(const Duration(seconds: 5)).skipAvailable, isTrue);
      expect(navigator.observe(const Duration(seconds: 14)).skipAvailable, isTrue);
    });

    test('a user seek across a break re-opens with the right program time', () {
      final navigator = ScheduleNavigator(composed())
        ..observe(Duration.zero) // pre-roll open
        ..observe(const Duration(seconds: 20)); // content at program 5s

      // Seek forward across the 40s mid-roll cut: combined 60s = program 45s.
      final jumped = navigator.observe(const Duration(seconds: 60));
      expect(jumped.actions, hasLength(1));
      final open = jumped.actions.single as OpenClip;
      expect(open.clip.kind, ClipKind.advertisement);

      final back = navigator.observe(const Duration(seconds: 70));
      final resumed = back.actions.single as OpenClip;
      expect(resumed.clip.kind, ClipKind.content);
      expect(resumed.seekTo, const Duration(seconds: 45));
    });

    test('completion fires once past the end and clears the open clip', () {
      final navigator = ScheduleNavigator(composed())..observe(Duration.zero);

      final done = navigator.observe(const Duration(seconds: 130));
      expect(done.actions, contains(const ScheduleComplete()));
      expect(navigator.openedSegment, isNull);
    });

    test('an empty schedule completes immediately', () {
      final navigator = ScheduleNavigator(ComposedSchedule.empty);

      final observation = navigator.observe(Duration.zero);

      expect(observation.position, isNull);
      expect(observation.actions, const [ScheduleComplete()]);
    });
  });
}
