import 'dart:async';
import 'package:media_core/task/player_task.dart' show PlayerTask;

/// Cancellation token used to cooperatively cancel a [PlayerTask].
///
/// [TaskCancelToken] is intentionally mutable because it represents runtime
/// cancellation state rather than immutable task data.
///
/// Cancellation is cooperative:
///
/// ```text
/// TaskCancelToken
///       │
///       ├── cancel()
///       │
///       ├── onCancel
///       │
///       └── cancelled
/// ```
///
/// Cancelling the token does not forcibly interrupt running Dart code.
/// Task implementations must observe this token and stop their work when
/// cancellation is requested.
///
/// A token can transition only once:
///
/// ```text
/// active ──────► cancelled
///    │
///    └──────────► disposed
/// ```
final class TaskCancelToken {
  /// Creates a new active cancellation token.
  TaskCancelToken();

  /// Creates an already-cancelled token.
  factory TaskCancelToken.cancelled([Object? reason]) {
    final token = TaskCancelToken()..cancel(reason);
    return token;
  }

  bool _isCancelled = false;
  bool _isDisposed = false;

  Object? _reason;

  StreamController<Object?>? _controller;

  Completer<Object?>? _cancelledCompleter;

  StreamSubscription<Object?>? _parentSubscription;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// Whether cancellation has not been requested.
  bool get isNotCancelled => !_isCancelled;

  /// Whether this token has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether this token can still be cancelled.
  bool get canCancel => !_isCancelled && !_isDisposed;

  /// The cancellation reason, if supplied.
  Object? get reason => _reason;

  /// Whether a cancellation reason is available.
  bool get hasReason => _reason != null;

  /// A broadcast stream that emits exactly once when cancellation occurs.
  ///
  /// If the token has already been cancelled, the returned stream emits the
  /// cancellation reason asynchronously.
  Stream<Object?> get onCancel {
    if (_isCancelled) {
      return Stream<Object?>.value(_reason);
    }

    _controller ??= StreamController<Object?>.broadcast();

    return _controller!.stream;
  }

  /// A future that completes when cancellation occurs.
  ///
  /// If the token has already been cancelled, the returned future is already
  /// completed with the cancellation reason.
  Future<Object?> get cancelled {
    if (_isCancelled) {
      return Future<Object?>.value(_reason);
    }

    final completer = _cancelledCompleter ??= Completer<Object?>();

    return completer.future;
  }

  /// Requests cancellation.
  ///
  /// Returns `true` only when this call changes the token from
  /// not-cancelled to cancelled.
  ///
  /// Returns `false` when the token has already been cancelled or disposed.
  bool cancel([Object? reason]) {
    if (_isDisposed || _isCancelled) {
      return false;
    }

    _isCancelled = true;
    _reason = reason;

    final controller = _controller;

    if (controller != null && !controller.isClosed) {
      controller.add(reason);
    }

    final completer = _cancelledCompleter;

    if (completer != null && !completer.isCompleted) {
      completer.complete(reason);
    }

    return true;
  }

  /// Alias for [cancel].
  ///
  /// Kept for callers that prefer an explicit cancellation method name.
  bool cancelAndReturn([Object? reason]) {
    return cancel(reason);
  }

  /// Throws [TaskCancelledException] when cancellation was requested.
  ///
  /// Disposal by itself does not imply cancellation.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw TaskCancelledException(_reason);
    }
  }

  /// Checks whether cancellation was requested.
  ///
  /// Alias for [throwIfCancelled].
  void checkCancelled() {
    throwIfCancelled();
  }

  /// Returns the cancellation reason when it is of type [T].
  ///
  /// Otherwise returns [fallback].
  T reasonOr<T>(T fallback) {
    final value = _reason;

    if (value is T) {
      return value;
    }

    return fallback;
  }

  /// Waits until cancellation is requested.
  Future<Object?> waitForCancellation() {
    return cancelled;
  }

  /// Runs [action] while checking cancellation before and after execution.
  ///
  /// Cancellation does not interrupt [action] while it is already running.
  ///
  /// If cancellation happens while [action] is executing, its result is
  /// discarded and [TaskCancelledException] is thrown after the action
  /// completes.
  Future<T> run<T>(FutureOr<T> Function() action) async {
    throwIfCancelled();

    final result = await action();

    throwIfCancelled();

    return result;
  }

  /// Creates a child token whose cancellation follows this token.
  ///
  /// Cancelling the child does not cancel the parent.
  ///
  /// The child owns its own cancellation state and may be cancelled
  /// independently.
  TaskCancelToken child() {
    if (_isDisposed) {
      throw StateError('Cannot create a child from a disposed TaskCancelToken.');
    }

    final child = TaskCancelToken();

    if (_isCancelled) {
      child.cancel(_reason);
      return child;
    }

    late final StreamSubscription<Object?> subscription;

    subscription = onCancel.listen((reason) {
      child.cancel(reason);
      unawaited(subscription.cancel());
    });

    child._parentSubscription = subscription;

    return child;
  }

  /// Releases resources held by this token.
  ///
  /// Disposal does not request cancellation.
  ///
  /// If cancellation should be propagated to listeners, call [cancel] before
  /// [dispose].
  ///
  /// Disposal is idempotent.
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    final parentSubscription = _parentSubscription;
    _parentSubscription = null;

    if (parentSubscription != null) {
      unawaited(parentSubscription.cancel());
    }

    final controller = _controller;
    _controller = null;

    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }

    // Do not complete the cancellation future here.
    //
    // Disposal is intentionally different from cancellation.
  }

  @override
  String toString() {
    return 'TaskCancelToken('
        'isCancelled: $isCancelled, '
        'isDisposed: $isDisposed, '
        'reason: $reason'
        ')';
  }
}

/// Exception thrown when a task observes cancellation.
final class TaskCancelledException implements Exception {
  /// Creates a task cancellation exception.
  const TaskCancelledException([this.reason]);

  /// Optional cancellation reason.
  final Object? reason;

  /// Whether a cancellation reason is available.
  bool get hasReason => reason != null;

  @override
  String toString() {
    final value = reason;

    if (value == null) {
      return 'TaskCancelledException';
    }

    return 'TaskCancelledException: $value';
  }
}
