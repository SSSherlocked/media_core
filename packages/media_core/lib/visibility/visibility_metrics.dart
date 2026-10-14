import 'package:equatable/equatable.dart';

/// Visibility statistics.
final class VisibilityMetrics extends Equatable {
  /// Creates visibility statistics from explicit totals.
  const VisibilityMetrics({
    this.visibleDuration = Duration.zero,

    this.hiddenDuration = Duration.zero,

    this.changeCount = 0,
  });

  /// Total visible time.
  final Duration visibleDuration;

  /// Total hidden time.
  final Duration hiddenDuration;

  /// Visibility changes.
  final int changeCount;

  /// Creates a copy with the supplied values replaced.
  VisibilityMetrics copyWith({Duration? visibleDuration, Duration? hiddenDuration, int? changeCount}) {
    return VisibilityMetrics(
      visibleDuration: visibleDuration ?? this.visibleDuration,

      hiddenDuration: hiddenDuration ?? this.hiddenDuration,

      changeCount: changeCount ?? this.changeCount,
    );
  }

  @override
  List<Object?> get props => [visibleDuration, hiddenDuration, changeCount];
}
