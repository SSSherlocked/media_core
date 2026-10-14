import 'dart:async';

/// Dispose related utilities.
abstract final class DisposeUtils {
  DisposeUtils._();

  /// Safely cancels a stream subscription.
  static Future<void> cancel(StreamSubscription<dynamic>? subscription) async {
    if (subscription == null) {
      return;
    }

    await subscription.cancel();
  }

  /// Safely closes a stream controller.
  static Future<void> close(StreamController<dynamic>? controller) async {
    if (controller == null) {
      return;
    }

    if (!controller.isClosed) {
      await controller.close();
    }
  }

  /// Safely closes a sink.
  static Future<void> closeSink(StreamSink<dynamic>? sink) async {
    if (sink == null) {
      return;
    }

    await sink.close();
  }

  /// Safely cancels a timer.
  static void cancelTimer(Timer? timer) {
    timer?.cancel();
  }

  /// Disposes multiple subscriptions.
  static Future<void> cancelAll(Iterable<StreamSubscription<dynamic>?> subscriptions) async {
    for (final subscription in subscriptions) {
      await cancel(subscription);
    }
  }

  /// Disposes multiple timers.
  static void cancelTimers(Iterable<Timer?> timers) {
    timers.forEach(cancelTimer);
  }

  /// Runs dispose callback safely.
  static Future<void> dispose(FutureOr<void> Function()? callback) async {
    if (callback == null) {
      return;
    }

    await callback();
  }

  /// Executes cleanup actions in order.
  static Future<void> disposeAll(Iterable<FutureOr<void> Function()> actions) async {
    for (final action in actions) {
      await action();
    }
  }

  /// Creates a disposable callback holder.
  static Disposable create() {
    return Disposable();
  }
}

/// Simple disposable container.
///
/// Example:
/// ```dart
/// final disposable = Disposable();
///
/// disposable.add(
///   () => subscription.cancel(),
/// );
///
/// await disposable.dispose();
/// ```
final class Disposable {
  final List<FutureOr<void> Function()> _actions = [];

  bool _disposed = false;

  /// Whether already disposed.
  bool get isDisposed => _disposed;

  /// Adds a dispose action.
  void add(FutureOr<void> Function() action) {
    if (_disposed) {
      // `add` is a synchronous API, so the caller cannot await an action that
      // runs on the already-disposed path; let the future complete on its own.
      final result = action();
      if (result is Future<void>) unawaited(result);
      return;
    }

    _actions.add(action);
  }

  /// Disposes all resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    for (final action in _actions.reversed) {
      await action();
    }

    _actions.clear();
  }
}
