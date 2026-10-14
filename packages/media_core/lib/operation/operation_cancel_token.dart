import 'dart:async';
import 'package:media_core/operation/library.dart' show Operation, OperationState;

/// Controls cancellation of a running or pending operation.
///
/// [OperationCancelToken] is a mutable runtime control object. It is
/// intentionally separate from [Operation] because cancellation is an
/// execution concern, while [Operation] is an immutable lifecycle model.
///
/// The token:
///
/// - records whether cancellation was requested;
/// - exposes a [Future] that completes when cancellation occurs;
/// - exposes a cancellation [Stream];
/// - stores an optional cancellation reason;
/// - can create child tokens;
/// - can be disposed safely.
///
/// The token does not change [OperationState] itself. The operation
/// coordinator/manager is responsible for applying the cancellation request
/// to the operation lifecycle.
final class OperationCancelToken {
  /// Creates a new active cancellation token.
  OperationCancelToken();

  final Completer<Object?> _cancelCompleter = Completer<Object?>();

  final StreamController<Object?> _cancelController = StreamController<Object?>.broadcast();

  bool _cancelled = false;
  bool _disposed = false;
  Object? _reason;

  StreamSubscription<Object?>? _parentSubscription;

  /// Whether cancellation has been requested.
  bool get cancelled => _cancelled;

  /// Alias for [cancelled].
  bool get isCancelled => _cancelled;

  /// Whether this token has been disposed.
  bool get isDisposed => _disposed;

  /// Whether this token is still active.
  bool get isActive => !_cancelled && !_disposed;

  /// The cancellation reason, if one was provided.
  Object? get reason => _reason;

  /// Whether a cancellation reason exists.
  bool get hasReason => _reason != null;

  /// Completes when cancellation is requested.
  ///
  /// The future completes with the cancellation reason when one exists.
  Future<Object?> get cancelledFuture => _cancelCompleter.future;

  /// Stream that emits the cancellation reason when cancellation occurs.
  ///
  /// The stream emits at most one event.
  Stream<Object?> get onCancel => _cancelController.stream;

  // ---------------------------------------------------------------------------
  // Cancellation
  // ---------------------------------------------------------------------------

  /// Requests cancellation.
  ///
  /// Returns `true` when this call actually changed the token from active to
  /// cancelled.
  ///
  /// Returns `false` when cancellation had already been requested or the token
  /// has already been disposed.
  bool cancel([Object? reason]) {
    if (_cancelled || _disposed) {
      return false;
    }

    _cancelled = true;
    _reason = reason;

    if (!_cancelCompleter.isCompleted) {
      _cancelCompleter.complete(reason);
    }

    if (!_cancelController.isClosed) {
      _cancelController.add(reason);
    }

    return true;
  }

  /// Requests cancellation and returns whether it was newly cancelled.
  bool cancelAndReturn([Object? reason]) {
    return cancel(reason);
  }

  // ---------------------------------------------------------------------------
  // Cancellation checks
  // ---------------------------------------------------------------------------

  /// Throws [OperationCancelledException] when cancellation was requested.
  void throwIfCancelled() {
    if (!_cancelled) {
      return;
    }

    throw OperationCancelledException(reason: _reason);
  }

  /// Checks cancellation without throwing.
  ///
  /// Returns `true` when cancellation was requested.
  bool checkCancelled() {
    return _cancelled;
  }

  /// Returns the cancellation reason, or [fallback] when none exists.
  T reasonOr<T>(T fallback) {
    final value = _reason;

    if (value is T) {
      return value;
    }

    return fallback;
  }

  /// Returns the cancellation reason when it has the requested type.
  T? reasonAs<T>() {
    final value = _reason;

    if (value is T) {
      return value;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Waiting
  // ---------------------------------------------------------------------------

  /// Waits until cancellation is requested.
  ///
  /// If cancellation has already occurred, the returned future completes
  /// immediately.
  Future<Object?> waitForCancellation() {
    return cancelledFuture;
  }

  /// Waits until cancellation and then throws
  /// [OperationCancelledException].
  Future<Never> waitAndThrow() async {
    await cancelledFuture;

    throw OperationCancelledException(reason: _reason);
  }

  // ---------------------------------------------------------------------------
  // Execution
  // ---------------------------------------------------------------------------

  /// Runs [action] only while this token remains active.
  ///
  /// Cancellation is checked before starting the action. Cancellation that
  /// occurs after the action starts does not forcibly interrupt the Dart
  /// future; the action itself must observe the token when appropriate.
  Future<T> run<T>(Future<T> Function() action) async {
    if (_disposed) {
      throw StateError(
        'Cannot run an operation with a disposed '
        'OperationCancelToken.',
      );
    }

    throwIfCancelled();

    return await action();
  }

  /// Runs [action] and checks cancellation before returning its result.
  ///
  /// This is useful when the underlying asynchronous operation cannot itself
  /// be interrupted but the result must not be accepted after cancellation.
  Future<T> runChecked<T>(Future<T> Function() action) async {
    if (_disposed) {
      throw StateError(
        'Cannot run an operation with a disposed '
        'OperationCancelToken.',
      );
    }

    throwIfCancelled();

    final result = await action();

    throwIfCancelled();

    return result;
  }

  // ---------------------------------------------------------------------------
  // Child tokens
  // ---------------------------------------------------------------------------

  /// Creates a child token linked to this token.
  ///
  /// When this token is cancelled, the child token is cancelled with the same
  /// reason.
  ///
  /// Cancelling the child does not cancel the parent.
  OperationCancelToken child() {
    if (_disposed) {
      throw StateError(
        'Cannot create a child from a disposed '
        'OperationCancelToken.',
      );
    }

    final child = OperationCancelToken();

    if (_cancelled) {
      child.cancel(_reason);
      return child;
    }

    child._parentSubscription = onCancel.listen(child.cancel);

    return child;
  }

  /// Creates a child token.
  ///
  /// This is equivalent to [child].
  OperationCancelToken fork() {
    return child();
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Disposes this token.
  ///
  /// Disposal does not itself mean cancellation.
  ///
  /// If cancellation is required, call [cancel] before [dispose].
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    unawaited(_parentSubscription?.cancel());
    _parentSubscription = null;

    unawaited(_cancelController.close());
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    final buffer = StringBuffer('OperationCancelToken(')
      ..write('cancelled: ')
      ..write(_cancelled)
      ..write(', disposed: ')
      ..write(_disposed);

    if (_reason != null) {
      buffer
        ..write(', reason: ')
        ..write(_reason);
    }

    buffer.write(')');

    return buffer.toString();
  }
}

/// Exception thrown when an operation observes a cancellation request.
final class OperationCancelledException implements Exception {
  /// Creates an operation cancellation exception.
  const OperationCancelledException({this.reason});

  /// The reason supplied when cancellation was requested.
  final Object? reason;

  /// Whether a cancellation reason exists.
  bool get hasReason => reason != null;

  @override
  String toString() {
    if (reason == null) {
      return 'OperationCancelledException';
    }

    return 'OperationCancelledException(reason: $reason)';
  }
}
