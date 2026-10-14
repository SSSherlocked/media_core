import 'package:equatable/equatable.dart';

/// Runtime context passed during state machine execution.
///
/// StateMachineContext provides shared execution information
/// required by transition guards and actions.
///
/// The context is intentionally lightweight.
///
/// It does not:
///
/// - store current state
/// - execute transitions
/// - manage queues
/// - own lifecycle
///
/// Domain modules may extend this class when additional
/// execution information is required.
class StateMachineContext extends Equatable {
  /// Creates a state machine context.
  ///
  /// Optional metadata can be used by diagnostics,
  /// guards, and transition actions.
  const StateMachineContext({this.metadata = const {}});

  /// Additional runtime metadata.
  ///
  /// Examples:
  ///
  /// - player identifier
  /// - session identifier
  /// - request information
  /// - debug flags
  final Map<String, Object?> metadata;

  /// Reads a metadata value.
  ///
  /// Returns `null` when the key does not exist.
  T? get<T>(String key) {
    final value = metadata[key];

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Creates a new context with additional metadata.
  StateMachineContext copyWithMetadata(Map<String, Object?> values) {
    return StateMachineContext(metadata: {...metadata, ...values});
  }

  /// Whether this context contains a key.
  bool contains(String key) {
    return metadata.containsKey(key);
  }

  @override
  List<Object?> get props => [metadata];

  @override
  String toString() {
    return 'StateMachineContext('
        'metadata=$metadata'
        ')';
  }
}
