import 'dart:async';

/// Exception thrown when an asynchronous operation is cancelled.
class StreamCancelledException implements Exception {
  /// Creates the cancellation failure with [message] for diagnostics.
  const StreamCancelledException([this.message = 'Operation was cancelled.']);

  /// Human readable reason reported to the caller that awaited the operation.
  final String message;

  @override
  String toString() {
    return 'StreamCancelledException: $message';
  }
}

/// A lightweight cancellation token.
///
/// Dart Futures cannot generally be forcibly cancelled. This token provides
/// cooperative cancellation: asynchronous code can check [isCancelled] or
/// call [throwIfCancelled].
class StreamCancellationToken {
  /// Creates a token in the active state; the owner of [StreamCancellationSource]
  /// requests cancellation through it.
  StreamCancellationToken();

  bool _cancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled;

  /// Whether the operation can continue.
  bool get isActive => !_cancelled;

  /// Cancel this token.
  void cancel() {
    _cancelled = true;
  }

  /// Throws [StreamCancelledException] if cancellation was requested.
  void throwIfCancelled([String message = 'Operation was cancelled.']) {
    if (_cancelled) {
      throw StreamCancelledException(message);
    }
  }

  /// Returns a Future that completes when [cancel] is called.
  Future<void> get whenCancelled {
    if (_cancelled) {
      return Future<void>.value();
    }

    final completer = Completer<void>();

    late final StreamCancellationSubscription subscription;

    subscription = StreamCancellationSubscription(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
      subscription.dispose();
    });

    _subscriptions.add(subscription);

    return completer.future;
  }

  final List<StreamCancellationSubscription> _subscriptions = <StreamCancellationSubscription>[];

  void _notifyCancelled() {
    for (final subscription in List<StreamCancellationSubscription>.from(_subscriptions)) {
      subscription.notify();
    }

    _subscriptions.clear();
  }
}

/// Internal cancellation listener.
class StreamCancellationSubscription {
  /// Wraps `onCancel`, the callback a cancellation owner invokes on cancel.
  StreamCancellationSubscription(this._onCancel);

  final void Function() _onCancel;

  bool _disposed = false;

  /// Invokes the cancellation callback unless already [dispose]d.
  void notify() {
    if (_disposed) {
      return;
    }

    _onCancel();
  }

  /// Stops the listener so a later cancellation does not resume the future.
  void dispose() {
    _disposed = true;
  }
}

/// A cancellation source that owns a [StreamCancellationToken].
///
/// Use the source to cancel an operation and pass the token to the operation.
class StreamCancellationSource {
  /// Creates a source with a fresh [token].
  StreamCancellationSource();

  /// The token handed to the operation that this source cancels.
  final StreamCancellationToken token = StreamCancellationToken();

  /// Whether [cancel] was already requested.
  bool get isCancelled => token.isCancelled;

  /// Cancel the associated operation.
  void cancel() {
    if (token._cancelled) {
      return;
    }

    token._cancelled = true;
    token._notifyCancelled();
  }
}

/// Runs an asynchronous operation with cooperative cancellation.
///
/// The operation itself must periodically check the token.
abstract final class StreamCancellable {
  /// Execute [action] with a cancellation token.
  static Future<T> run<T>(
    Future<T> Function(StreamCancellationToken token) action, {
    StreamCancellationToken? token,
  }) async {
    final cancellationToken = (token ?? StreamCancellationToken())..throwIfCancelled();

    final result = await action(cancellationToken);

    cancellationToken.throwIfCancelled();

    return result;
  }

  /// Wait for [duration], but return early when [token] is cancelled.
  static Future<bool> delay(Duration duration, StreamCancellationToken token) async {
    if (token.isCancelled) {
      return false;
    }

    final timerFuture = Future<void>.delayed(duration);

    try {
      await Future.any<void>([timerFuture, token.whenCancelled]);
    } on Object catch (_) {
      return false;
    }

    return !token.isCancelled;
  }
}

/// A group of cancellation tokens.
///
/// Cancelling the group cancels all registered tokens.
class StreamCancellationGroup {
  /// Creates an empty group that is not yet [dispose]d.
  StreamCancellationGroup();

  final Set<StreamCancellationSource> _sources = <StreamCancellationSource>{};

  bool _cancelled = false;

  /// Whether the group is closed; after [dispose] new sources arrive cancelled.
  bool get isCancelled => _cancelled;

  /// Number of sources still registered in the group.
  int get length => _sources.length;

  /// Create and register a new cancellation source.
  ///
  /// When the group is already disposed the returned source is cancelled so a
  /// late operation cannot start against a closed group.
  StreamCancellationSource create() {
    if (_cancelled) {
      final source = StreamCancellationSource()..cancel();
      return source;
    }

    final source = StreamCancellationSource();
    _sources.add(source);
    return source;
  }

  /// Register an existing source.
  void add(StreamCancellationSource source) {
    if (_cancelled) {
      source.cancel();
      return;
    }

    _sources.add(source);
  }

  /// Remove a source from the group.
  void remove(StreamCancellationSource source) {
    _sources.remove(source);
  }

  /// Cancel all sources.
  void cancelAll() {
    for (final source in List<StreamCancellationSource>.from(_sources)) {
      source.cancel();
    }

    _sources.clear();
  }

  /// Cancel the group permanently.
  void dispose() {
    if (_cancelled) {
      return;
    }

    _cancelled = true;
    cancelAll();
  }
}
