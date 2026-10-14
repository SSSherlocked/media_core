import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/media_core.dart';
import 'package:media_core/testing/fake_player_adapter.dart';

import 'package:media_core_live/media_core_live.dart';

/// Hands out one specific fake per engine id so a test can read back what
/// that engine was asked to do.
final class _EngineFactory implements PlayerAdapterFactory {
  _EngineFactory(this.adapters);

  final Map<String, FakePlayerAdapter> adapters;

  @override
  PlayerAdapter create(String id) => adapters[id] ?? (throw StateError('no fake for $id'));

  @override
  bool supports(String id) => adapters.containsKey(id);
}

FakePlayerAdapter _fake(String id, {Set<String> failOn = const {}}) {
  return FakePlayerAdapter(
    id: id,
    behavior: FakePlayerAdapterBehavior(failOn: failOn),
  );
}

PlayerKernel _kernel(Map<String, FakePlayerAdapter> adapters) {
  final kernel = PlayerKernel();
  for (final entry in adapters.entries) {
    kernel.registerBackend(
      PlayerAdapterRegistration(
        id: entry.key,
        factory: _EngineFactory(adapters),
        capabilities: FakePlayerAdapterBehavior.defaultCapabilities,
        priority: 10,
      ),
    );
  }
  return kernel;
}

PlayerSource _line(String url, {String? title}) {
  final uri = Uri.parse(url);
  return PlayerSource(
    id: SourceId(url),
    uri: uri,
    type: SourceType.live,
    protocol: SourceProtocol.fromScheme(uri.scheme),
    mediaType: SourceMediaType.video,
    format: SourceFormat.fromUri(uri),
    title: title,
  );
}

LiveSourceRequest _request(List<String> urls, {bool? allowEngineFallback}) {
  return LiveSourceRequest(sources: urls.map(_line).toList(growable: false), allowEngineFallback: allowEngineFallback);
}

/// Watchdogs off: these tests drive the sweep, and a stall detector firing in
/// the middle of one would make the assertion about the wrong decision.
///
/// [sourceReadyTimeout] is also the sweep's verification deadline, so tests
/// that sit out a refusal shrink it instead of paying the production 18s.
LivePlaybackController _controller(
  PlayerKernel kernel, {
  Duration sourceReadyTimeout = const Duration(seconds: 18),
  RecoverySourceResolver? onRecoverySources,
}) {
  return LivePlaybackController(
    kernel,
    watchdogs: LiveWatchdogs(enabled: false, sourceReadyTimeout: sourceReadyTimeout),
    onRecoverySources: onRecoverySources,
  );
}

void main() {
  group('LivePlaybackController.play', () {
    test('a stream that never advances is refused, not adopted', () async {
      // The whole point of the sweep: opening is not playing. A backend that
      // accepts the URL and then produces no position progress must be
      // abandoned, and the caller must hear about it exactly once.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel, sourceReadyTimeout: const Duration(milliseconds: 600));

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      await controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(failures, hasLength(1));
      expect(failures.single.code, PlayerErrorCode.noPlayableStream);
      expect(failures.single.message, contains('https://a.example/live.flv'));
      expect(adapters['engine-a']!.calls, contains('open'));

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an engine that cannot open is escalated to the next one', () async {
      final adapters = {
        'engine-a': _fake('engine-a', failOn: const {'open'}),
        'engine-b': _fake('engine-b'),
      };
      final kernel = _kernel(adapters);
      final controller = _controller(kernel);

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      final playing = controller.play(_request(['https://a.example/live.flv']));

      // Feed the second engine a progressing position so verification ends;
      // without it the sweep would sit out the whole window on every engine.
      await _pumpPosition(adapters.values);
      await playing;

      expect(adapters['engine-a']!.calls, contains('open'));
      expect(adapters['engine-b']!.calls, contains('open'));
      expect(controller.backendId, 'engine-b');
      expect(failures, isEmpty);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('refusing engine fallback stops at the first engine', () async {
      final adapters = {
        'engine-a': _fake('engine-a', failOn: const {'open'}),
        'engine-b': _fake('engine-b'),
      };
      final kernel = _kernel(adapters);
      final controller = _controller(kernel);

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      await controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(adapters['engine-a']!.calls, contains('open'));
      expect(
        adapters['engine-b']!.calls,
        isNot(contains('open')),
        reason:
            'the caller declined escalation, so the second engine must '
            'never be touched',
      );
      expect(failures, hasLength(1));
      expect(failures.single.code, PlayerErrorCode.noPlayableStream);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a line that plays is kept, and the alternatives are not tried', () async {
      // The sweep is a ladder, not a lottery: once a line proves it is
      // advancing, the remaining candidates must stay untouched, because
      // opening a second live line costs a second stream nobody watches.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel);

      final playing = controller.play(_request(['https://first.example/live.flv', 'https://second.example/live.flv']));
      await _pumpPosition(adapters.values);
      await playing;

      final opened = adapters['engine-a']!.openedSources;
      expect(opened, hasLength(1));
      expect(opened.single.uri.host, 'first.example');
      expect(controller.sourceIndex, 0);

      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('sweep verification deadline', () {
    test('the configured deadline gates a silent candidate, not a private one', () async {
      // Verification used to carry its own 8s constant while the watchdog
      // bundle declared 18s for the same question — so the tighter of the two
      // decided, and a caller tuning `sourceReadyTimeout` had no effect on the
      // gate that actually ran. A short deadline must now end the attempt.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel, sourceReadyTimeout: const Duration(milliseconds: 400));

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      final started = DateTime.now();
      await controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));
      final elapsed = DateTime.now().difference(started);

      expect(failures, hasLength(1));
      expect(failures.single.code, PlayerErrorCode.noPlayableStream);
      expect(
        elapsed,
        lessThan(const Duration(seconds: 4)),
        reason: 'the gate must use the configured 400ms, not a constant of its own',
      );

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a source that only starts advancing late is adopted, not refused', () async {
      // The shape of a multi-variant HLS master: the demuxer opens every
      // rendition before a clock exists, so position stays at zero for a while
      // even though the engine is working. Nothing reports "still probing", so
      // the deadline is the only thing that may judge it.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel, sourceReadyTimeout: const Duration(seconds: 3));

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      final playing = controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      adapters['engine-a']!.updatePosition(const Duration(seconds: 1));
      await playing;

      expect(failures, isEmpty);
      expect(controller.handle, isNotNull);
      expect(controller.sourceIndex, 0);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an engine error during a staged attempt ends verification with the real reason', () async {
      // The first open of a session is always staged — there is no player to
      // replace — and a staged attempt had no adapter subscription until it
      // committed. A playlist that 404s therefore looked like a frozen
      // position for the whole window, and the reason the engine had already
      // stated never reached the report.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel, sourceReadyTimeout: const Duration(seconds: 12));

      final previousLevel = MediaCoreLog.level;
      final sink = MediaCoreLog.attachMemorySink();
      MediaCoreLog.level = LogLevel.warning;
      addTearDown(() {
        MediaCoreLog.removeSink(sink.call);
        MediaCoreLog.level = previousLevel;
      });

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      final started = DateTime.now();
      final playing = controller.play(_request(['https://a.example/live.m3u8'], allowEngineFallback: false));

      await _untilPlayRequested(adapters['engine-a']!);
      adapters['engine-a']!.emitError('Failed to open https://a.example/live.m3u8.');
      await playing;
      final elapsed = DateTime.now().difference(started);

      expect(
        elapsed,
        lessThan(const Duration(seconds: 6)),
        reason: 'the engine had already said why; verification must not sit out its 12s window',
      );
      expect(failures, hasLength(1));
      expect(failures.single.code, PlayerErrorCode.noPlayableStream);

      final candidateFailures = sink
          .forCategory(LogCategory.recovery)
          .where((record) => record.message.startsWith('candidate failed'))
          .toList(growable: false);
      expect(candidateFailures, isNotEmpty);
      expect(
        candidateFailures.first.error.toString(),
        contains('Failed to open'),
        reason: 'the reported cause must be the engine error, not "position frozen at 0ms"',
      );

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a zero deadline turns verification off with the watchdog', () async {
      // `sourceReadyTimeout: 0` already means "no opened-but-not-playing
      // watchdog"; verification is that deadline, so it must stand down too
      // rather than refuse every candidate on the spot.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel, sourceReadyTimeout: Duration.zero);

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      await controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(failures, isEmpty);
      expect(controller.handle, isNotNull);
      expect(adapters['engine-a']!.calls, contains('play'));

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('recovery source refresh', () {
    test('a recovery opens the fresh lines instead of retrying the dead one', () async {
      // The shape of an expired signed URL: the platform rejects the address
      // the player is holding, so re-opening it can only fail again. What the
      // caller can do — and the sweep cannot — is ask the platform once more.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final askedWith = <List<String>>[];
      final controller = _controller(
        kernel,
        onRecoverySources: (current) async {
          askedWith.add(current.map((source) => source.uri.host).toList(growable: false));
          return <PlayerSource>[
            _line('https://fresh.example/live.flv'),
            _line('https://fresh-backup.example/live.flv'),
          ];
        },
      );

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      final playing = controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));
      await _pumpPosition(adapters.values);
      await playing;

      expect(adapters['engine-a']!.openedSources.single.uri.host, 'a.example');

      adapters['engine-a']!.emitError('Server returned 403 Forbidden');
      await _pumpPosition(adapters.values);

      expect(askedWith, [
        ['a.example'],
      ], reason: 'the refresh must be offered the lines that just died');
      expect(controller.sources.map((source) => source.uri.host), ['fresh.example', 'fresh-backup.example']);
      expect(controller.sourceIndex, 0);
      expect(adapters['engine-a']!.openedSources.last.uri.host, 'fresh.example');
      expect(failures, isEmpty);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an answer that lands after a newer play is discarded', () async {
      // The refresh is the recovery's only await that a user command can
      // overtake. Adopting a late answer would swap the lines out from under
      // the playback the user actually asked for.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final gate = Completer<List<PlayerSource>>();
      final controller = _controller(kernel, onRecoverySources: (_) => gate.future);

      final playing = controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));
      await _pumpPosition(adapters.values);
      await playing;

      // The recovery starts and blocks in the refresh; `play` bumps the
      // generation synchronously and queues its own task behind it.
      adapters['engine-a']!.emitError('Server returned 403 Forbidden');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final next = controller.play(_request(['https://b.example/live.flv'], allowEngineFallback: false));
      gate.complete(<PlayerSource>[_line('https://stale.example/live.flv')]);

      await _pumpPosition(adapters.values);
      await next;

      expect(controller.sources.map((source) => source.uri.host), ['b.example']);
      expect(
        adapters['engine-a']!.openedSources.map((source) => source.uri.host),
        isNot(contains('stale.example')),
        reason: 'a superseded refresh must never reach an engine',
      );

      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a refresh that throws leaves the sweep on the line it had', () async {
      // Recovery answers to a stall. A platform that cannot be reached for
      // fresh lines is not a second failure — the sweep still owes its attempt
      // on the sources it holds.
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(
        kernel,
        onRecoverySources: (_) async => throw StateError('the platform is unreachable'),
      );

      final failures = <PlayerFailure>[];
      final subscription = controller.onError.listen(failures.add);

      final playing = controller.play(_request(['https://a.example/live.flv'], allowEngineFallback: false));
      await _pumpPosition(adapters.values);
      await playing;

      adapters['engine-a']!.emitError('Server returned 403 Forbidden');
      await _pumpPosition(adapters.values);

      expect(controller.sources.map((source) => source.uri.host), ['a.example']);
      expect(
        adapters['engine-a']!.openedSources,
        hasLength(2),
        reason: 'the sweep must still run: a dead refresh is not a dead recovery',
      );
      expect(adapters['engine-a']!.openedSources.last.uri.host, 'a.example');
      expect(failures, isEmpty);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('LivePlaybackController lifecycle', () {
    test('close releases the handle and returns the session to idle', () async {
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel);

      final states = <PlayerCoreState>[];
      final subscription = controller.onStateChanged.listen(states.add);

      final playing = controller.play(_request(['https://a.example/live.flv']));
      await _pumpPosition(adapters.values);
      await playing;

      expect(controller.handle, isNotNull);

      await controller.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.handle, isNull);
      expect(states.last, PlayerCoreState.idle);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('a disposed controller never starts playback again', () async {
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel);

      await controller.dispose();

      // Whether this refuses quietly or throws is the controller's choice;
      // the invariant a caller depends on is that no engine is opened and no
      // handle comes back.
      Object? thrown;
      try {
        await controller.play(_request(['https://a.example/live.flv']));
      } on Object catch (error) {
        thrown = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(adapters['engine-a']!.calls, isNot(contains('open')));
      expect(controller.handle, isNull);
      expect(
        thrown,
        anyOf(isNull, isA<StateError>()),
        reason: 'refusal must be quiet or explicit, not a half-started session',
      );

      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('state changes are published for the caller to render', () async {
      final adapters = {'engine-a': _fake('engine-a')};
      final kernel = _kernel(adapters);
      final controller = _controller(kernel);

      final states = <PlayerCoreState>[];
      final subscription = controller.onStateChanged.listen(states.add);

      final playing = controller.play(_request(['https://a.example/live.flv']));
      await _pumpPosition(adapters.values);
      await playing;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, isNotEmpty);

      await subscription.cancel();
      await controller.dispose();
      await kernel.dispose();
    }, timeout: const Timeout(Duration(seconds: 40)));
  });
}

/// Waits until the sweep has opened the source and asked for playback — the
/// moment verification starts polling, and therefore the only point from which
/// an injected adapter error is a fair test of the fast-fail path.
Future<void> _untilPlayRequested(FakePlayerAdapter adapter) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));

  while (DateTime.now().isBefore(deadline)) {
    if (adapter.calls.contains('play')) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('the engine was never asked to play');
}

/// Drives the mirror's position forward while a sweep is verifying.
///
/// The fake adapter only reports a position when it is asked to seek, so this
/// stands in for a stream that is actually advancing. It seeks the adapters
/// rather than `controller.handle`, because the handle is only published once
/// verification has already passed — during the sweep it is still staged.
/// Verification polls every 250 ms inside its deadline, which this covers.
Future<void> _pumpPosition(Iterable<FakePlayerAdapter> adapters, {Duration window = const Duration(seconds: 4)}) async {
  final deadline = DateTime.now().add(window);
  var position = const Duration(seconds: 1);

  while (DateTime.now().isBefore(deadline)) {
    for (final adapter in adapters) {
      try {
        await adapter.seek(position);
      } on Object catch (_) {
        // An adapter that failed to open has nothing to seek; the sweep is
        // about to move past it anyway.
      }
    }
    position += const Duration(seconds: 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
