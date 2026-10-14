import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';

/// The recovery retry delay: two `KernelOptions` fields documented a backoff that
/// nothing read, so a sweep ran its rungs back to back and an engine that had just
/// refused an open was asked again in the same millisecond.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final current = PlayerSource(
    id: SourceId('current'),
    uri: Uri.parse('https://example.com/current.mp4'),
    mediaType: SourceMediaType.video,
  );
  final lines = <PlayerSource>[
    PlayerSource(id: SourceId('line-a'), uri: Uri.parse('https://example.com/a.mp4')),
    PlayerSource(id: SourceId('line-b'), uri: Uri.parse('https://example.com/b.mp4')),
  ];
  final failure = RecoveryFailure.fromMessage(
    'the decoder stopped',
    error: StateError('decoder stopped'),
    source: RecoveryFailureSource.adapter,
  );

  _Refused refusedSteps({required bool reopen}) {
    return _Refused(RecoverySession(failure: failure, source: reopen ? current : null, sourceCandidates: lines));
  }

  Duration growing(int attempt) => Duration(milliseconds: 50 * (attempt - 1));

  group('the sweep waits between attempts', () {
    test('the first attempt runs immediately', () async {
      final steps = refusedSteps(reopen: true);
      final ladder = RecoveryLadder(target: steps, candidates: _Lines(lines), retryDelay: growing);

      expect(ladder.report(failure), isTrue);
      await ladder.settled;

      expect(steps.ranAt, isNotEmpty);
      expect(steps.ranAt.first, lessThan(40), reason: 'the failure itself already cost the viewer time');
    });

    test('every later attempt waits the delay its number asks for', () async {
      final steps = refusedSteps(reopen: true);
      final ladder = RecoveryLadder(target: steps, candidates: _Lines(lines), retryDelay: growing);

      expect(ladder.report(failure), isTrue);
      await ladder.settled;

      expect(steps.ranAt.length, greaterThanOrEqualTo(3), reason: 'reopen then two lines');
      expect(
        steps.gaps,
        hasLength(steps.ranAt.length - 1),
        reason: 'a sweep of N attempts pays N - 1 delays, so no attempt is uncounted',
      );

      for (final gap in steps.gaps) {
        expect(gap, greaterThanOrEqualTo(45), reason: 'the shortest delay this resolver gives is 50 ms');
      }

      expect(steps.gaps.last, greaterThan(steps.gaps.first), reason: 'the wait grows with the attempt');
      expect(ladder.status, RecoveryLadderStatus.exhausted);
    });

    test('a ladder with no resolver keeps the old immediate escalation', () async {
      final steps = refusedSteps(reopen: true);
      final ladder = RecoveryLadder(target: steps, candidates: _Lines(lines));

      expect(ladder.report(failure), isTrue);
      await ladder.settled;

      expect(steps.ranAt.length, greaterThan(1));

      for (final gap in steps.gaps) {
        expect(gap, lessThan(40), reason: 'nothing was asked to wait, so nothing may');
      }
    });

    test('a wait the viewer walked away during stops the sweep', () async {
      final steps = refusedSteps(reopen: true);
      final ladder = RecoveryLadder(target: steps, candidates: _Lines(lines), retryDelay: growing);
      final cancelled = <RecoveryLadderEvent>[];
      final subscription = ladder.events.listen(cancelled.add);
      addTearDown(subscription.cancel);

      expect(ladder.report(failure), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The second attempt is asleep in its delay when the lifecycle moves on.
      ladder.reset();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(steps.ranAt, hasLength(1), reason: 'a step for a playback that has been left must not reopen it');
      expect(ladder.status, RecoveryLadderStatus.idle);
      expect(cancelled.whereType<RecoveryLadderCancelled>(), hasLength(1));

      await ladder.settled;
    });
  });

  group('the kernel options reach the handle', () {
    test('the handle gives its ladder the documented backoff', () async {
      const options = KernelOptions(retryBaseDelay: Duration(milliseconds: 60), retryMaxDelay: Duration(seconds: 1));
      final kernel = PlayerKernel(options: options)
        ..registerBackend(
          PlayerAdapterRegistration(
            id: 'fake',
            factory: TestPlayerFactory.fakeAdapterFactory(),
            capabilities: const FakePlayerAdapterBehavior().capabilities,
          ),
        );
      addTearDown(kernel.dispose);

      final handle = await kernel.create(
        source: PlayerSource(
          id: SourceId('wired'),
          uri: Uri.parse('https://example.com/wired.mp4'),
          mediaType: SourceMediaType.video,
        ),
      );
      addTearDown(handle.dispose);

      final delayed = handle.recoveryLadder.retryDelay;
      expect(delayed, isNotNull, reason: 'a ladder built by a handle is never left without a delay');
      final resolver = delayed!;

      final delays = <Duration>[
        for (final attempt in <int>[1, 2, 3, 4, 5]) resolver.call(attempt),
      ];

      expect(delays.first, Duration.zero, reason: 'the attempt that opens a sweep is immediate');
      expect(delays[1], greaterThanOrEqualTo(options.retryBaseDelay));

      for (var index = 2; index < delays.length; index++) {
        expect(
          delays[index],
          greaterThanOrEqualTo(delays[index - 1]),
          reason: 'the wait does not shrink as the sweep escalates',
        );
      }

      expect(
        delays.last,
        lessThanOrEqualTo(options.retryMaxDelay * 2),
        reason: 'the ceiling holds, with the jitter that rides on top of it',
      );
    });
  });
}

/// A ladder run whose every step is refused, recording when each one ran.
///
/// The suite is about the gaps, so the clock is one stopwatch shared by the steps
/// rather than a wall-clock instant per attempt.
final class _Refused implements RecoveryTarget {
  _Refused(this.session);

  final RecoverySession session;
  final Stopwatch clock = Stopwatch()..start();
  final List<int> ranAt = <int>[];

  /// Milliseconds between one attempt and the next.
  List<int> get gaps => <int>[for (var index = 1; index < ranAt.length; index++) ranAt[index] - ranAt[index - 1]];

  @override
  bool get isRecoveryAvailable => true;

  @override
  Stream<RecoveryTargetEvent> get executionEvents => const Stream<RecoveryTargetEvent>.empty();

  @override
  RecoverySession buildRecoverySession(RecoveryFailure failure, RecoveryCandidates candidates) => session;

  @override
  Future<void> reopenForRecovery(RecoveryStep step, RecoverySession session) => _refused();

  @override
  Future<void> swapToForRecovery(RecoveryStep step, RecoverySession session) => _refused();

  Future<void> _refused() async {
    ranAt.add(clock.elapsedMilliseconds);

    throw StateError('the engine still refuses to open');
  }
}

/// The two spare lines a sweep escalates through.
final class _Lines implements RecoveryCandidateProvider {
  _Lines(this.sources);

  final List<PlayerSource> sources;

  @override
  RecoveryCandidates candidatesFor(RecoveryFailure failure) => RecoveryCandidates(sources: sources);
}
