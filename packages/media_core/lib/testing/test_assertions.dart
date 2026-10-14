import 'dart:async';

import 'package:media_core/adapter/player_adapter_event.dart';
import 'package:media_core/core/player_core_state.dart';

/// Common expectations shared by media_core tests.
///
/// These helpers are intentionally dependency free so they can
/// be used from both `package:test` and `flutter_test` suites.
final class TestAssertions {
  const TestAssertions._();

  /// Expects [disposer] to complete without throwing.
  static Future<void> disposesCleanly(Future<void> Function() disposer) async {
    try {
      await disposer();
    } catch (error) {
      throw StateError('dispose threw: $error');
    }
  }

  /// Expects [stream] to emit a value matching [test] and returns it.
  static Future<T> nextEvent<T>(Stream<T> stream, bool Function(T) test) async {
    final event = await stream.firstWhere(test);
    return event;
  }

  /// Expects [state] to be the idle state.
  static void isIdle(PlayerCoreState state) {
    if (!state.isIdle) {
      throw StateError('expected idle state, got $state');
    }
  }

  /// Expects [state] to report playing.
  static void isPlaying(PlayerCoreState state) {
    if (!state.playing) {
      throw StateError('expected playing state, got $state');
    }
  }

  /// Expects [state] to report paused.
  static void isPaused(PlayerCoreState state) {
    if (!state.paused) {
      throw StateError('expected paused state, got $state');
    }
  }

  /// Expects [state] to report buffering.
  static void isBuffering(PlayerCoreState state) {
    if (!state.buffering) {
      throw StateError('expected buffering state, got $state');
    }
  }

  /// Expects [state] to report completed.
  static void isCompleted(PlayerCoreState state) {
    if (!state.completed) {
      throw StateError('expected completed state, got $state');
    }
  }

  /// Expects [state] to report an error.
  static void hasError(PlayerCoreState state) {
    if (!state.hasError) {
      throw StateError('expected error state, got $state');
    }
  }

  /// Expects [state] to be disposed.
  static void isDisposed(PlayerCoreState state) {
    if (!state.disposed) {
      throw StateError('expected disposed state, got $state');
    }
  }

  /// Expects [events] to contain at least one error event.
  static void containsError(Iterable<PlayerAdapterEvent> events) {
    if (!events.any((event) => event.isError)) {
      throw StateError('expected at least one error event');
    }
  }

  /// Expects [future] to complete within [timeout].
  static Future<void> completesWithin(Future<void> future, Duration timeout) async {
    await future.timeout(
      timeout,
      onTimeout: () {
        throw StateError('Future did not complete within $timeout');
      },
    );
  }
}
