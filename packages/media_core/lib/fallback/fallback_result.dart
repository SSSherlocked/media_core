import 'package:equatable/equatable.dart';
import 'package:media_core/fallback/fallback_reason.dart';

/// Result of a fallback operation.
///
/// A successful result contains the target that should be used.
///
/// A failed result may contain a diagnostic message but does not contain a
/// target.
final class FallbackResult extends Equatable {
  const FallbackResult._({required this.successful, required this.reason, required this.target, required this.message});

  /// Creates a result describing a successful fallback to [target].
  const FallbackResult.success({required FallbackReason reason, required String target})
    : this._(successful: true, reason: reason, target: target, message: null);

  /// Creates a result describing a failed fallback, with an optional
  /// diagnostic [message] and no target.
  const FallbackResult.failure({required FallbackReason reason, String? message})
    : this._(successful: false, reason: reason, target: null, message: message);

  /// Whether the fallback succeeded.
  final bool successful;

  /// The reason that triggered the fallback.
  final FallbackReason reason;

  /// The target selected by a successful fallback, or `null` on failure.
  final String? target;

  /// The diagnostic message carried by a failed fallback, when provided.
  final String? message;

  /// Whether the fallback failed.
  bool get failed => !successful;

  /// Whether the result names a non-empty target.
  bool get hasTarget => target != null && target!.isNotEmpty;

  /// Whether the result carries a non-empty diagnostic message.
  bool get hasMessage => message != null && message!.isNotEmpty;

  /// Serializes the result for logging or persistence.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'successful': successful,
      'reason': reason.toString(),
      'target': target,
      'message': message,
    };
  }

  @override
  List<Object?> get props => <Object?>[successful, reason, target, message];

  @override
  String toString() {
    return 'FallbackResult('
        'successful: $successful, '
        'reason: $reason, '
        'target: $target, '
        'message: $message'
        ')';
  }
}
