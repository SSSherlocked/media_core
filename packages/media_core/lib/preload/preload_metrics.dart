import 'package:equatable/equatable.dart';

/// Preload statistics.
final class PreloadMetrics extends Equatable {
  /// Creates a metrics record with the given counters.
  const PreloadMetrics({this.total = 0, this.completed = 0, this.failed = 0, this.cancelled = 0});

  /// Total number of preload operations started.
  final int total;

  /// Number of preload operations that finished successfully.
  final int completed;

  /// Number of preload operations that failed.
  final int failed;

  /// Number of preload operations cancelled before completion.
  final int cancelled;

  /// Fraction of [total] operations that completed successfully, or `0`
  /// when nothing has run yet.
  double get successRate {
    if (total == 0) {
      return 0;
    }

    return completed / total;
  }

  /// Returns a copy with the given counters replaced.
  PreloadMetrics copyWith({int? total, int? completed, int? failed, int? cancelled}) {
    return PreloadMetrics(
      total: total ?? this.total,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      cancelled: cancelled ?? this.cancelled,
    );
  }

  @override
  List<Object?> get props => [total, completed, failed, cancelled];
}
