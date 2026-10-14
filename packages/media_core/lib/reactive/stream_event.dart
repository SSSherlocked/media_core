/// Base type for events emitted through a stream.
///
/// Events are intentionally immutable so they can safely travel through
/// RxDart pipelines.
sealed class StreamEvent {
  const StreamEvent();
}

/// A value/state changed event.
final class StreamValueChanged<T> extends StreamEvent {
  /// Carries the new [value] and, when known, the [previous] value it replaced.
  const StreamValueChanged({required this.value, this.previous});

  /// The value the stream produced.
  final T value;

  /// The value immediately before this one, or `null` for the first emission.
  final T? previous;

  @override
  String toString() {
    return 'StreamValueChanged<$T>('
        'value: $value, '
        'previous: $previous'
        ')';
  }
}

/// A loading state event.
final class StreamLoading extends StreamEvent {
  /// Announces that work is in flight, optionally describing it with [message].
  const StreamLoading({this.message});

  /// Optional human readable description of what is being loaded.
  final String? message;

  @override
  String toString() {
    return 'StreamLoading(message: $message)';
  }
}

/// A loading operation completed successfully.
final class StreamLoaded<T> extends StreamEvent {
  /// Marks the end of a successful load and may carry the produced [value].
  const StreamLoaded({this.value});

  /// The loaded result, or `null` when the load only signals completion.
  final T? value;

  @override
  String toString() {
    return 'StreamLoaded<$T>(value: $value)';
  }
}

/// An error event.
final class StreamError extends StreamEvent {
  /// Reports [error], optionally with the [stackTrace] it was thrown with and
  /// a displayable [message].
  const StreamError(this.error, {this.stackTrace, this.message});

  /// The failure that ended the operation.
  final Object error;

  /// Where [error] was thrown, when the throwing site captured it.
  final StackTrace? stackTrace;

  /// Optional text shown instead of the raw error description.
  final String? message;

  @override
  String toString() {
    return 'StreamError('
        'error: $error, '
        'message: $message'
        ')';
  }
}

/// A stream operation completed.
final class StreamCompleted extends StreamEvent {
  /// Signals that the producer finished and will not emit again.
  const StreamCompleted();

  @override
  String toString() => 'StreamCompleted()';
}

/// A stream operation was cancelled.
final class StreamCancelled extends StreamEvent {
  /// Signals cancellation, optionally explaining it through [reason].
  const StreamCancelled({this.reason});

  /// Why the operation was cancelled, for logs and debugging.
  final String? reason;

  @override
  String toString() {
    return 'StreamCancelled(reason: $reason)';
  }
}

/// A stream operation was reset.
final class StreamReset extends StreamEvent {
  /// Signals that the producer dropped its state and starts over.
  const StreamReset();

  @override
  String toString() => 'StreamReset()';
}

/// A generic notification event.
///
/// Use this when the event does not carry a value but represents an action
/// or notification.
final class StreamNotification extends StreamEvent {
  /// Broadcasts a notification of [type], optionally with attached [data].
  const StreamNotification(this.type, {this.data});

  /// Discriminator consumers switch on, for example `refreshRequested`.
  final String type;

  /// Payload of the notification; consumers cast it per [type].
  final Object? data;

  @override
  String toString() {
    return 'StreamNotification('
        'type: $type, '
        'data: $data'
        ')';
  }
}

/// Utility extensions for [StreamEvent].
extension StreamEventX on StreamEvent {
  /// Whether the stream announced work in flight.
  bool get isLoading => this is StreamLoading;

  /// Whether the stream announced finished work.
  bool get isLoaded => this is StreamLoaded;

  /// Whether the stream announced a failure.
  bool get isError => this is StreamError;

  /// Whether the producer completed.
  bool get isCompleted => this is StreamCompleted;

  /// Whether the operation was cancelled.
  bool get isCancelled => this is StreamCancelled;

  /// Whether the producer reset its state.
  bool get isReset => this is StreamReset;

  /// Whether the event carries a new value.
  bool get isValueChanged => this is StreamValueChanged;

  /// Whether the event is a notification rather than state.
  bool get isNotification => this is StreamNotification;

  /// The failure carried by this event, or `null` when it is not an error.
  StreamError? get errorEvent {
    final event = this;

    if (event is StreamError) {
      return event;
    }

    return null;
  }

  /// Extracts the value of a [StreamValueChanged] or [StreamLoaded] carrying a
  /// [T]; returns `null` for any other event or a mismatching value type.
  T? valueOf<T>() {
    final event = this;

    if (event is StreamValueChanged<T>) {
      return event.value;
    }

    if (event is StreamLoaded<T>) {
      return event.value;
    }

    return null;
  }
}
