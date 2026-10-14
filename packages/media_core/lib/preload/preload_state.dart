import 'package:equatable/equatable.dart';

/// Runtime preload state.
final class PreloadState extends Equatable {
  /// Creates a preload state from its individual phase flags.
  const PreloadState({
    this.pending = false,
    this.loading = false,
    this.completed = false,
    this.failed = false,
    this.cancelled = false,
  });

  /// Whether the task is queued and waiting to load.
  final bool pending;

  /// Whether the source is currently loading.
  final bool loading;

  /// Whether the preload finished successfully.
  final bool completed;

  /// Whether the preload failed.
  final bool failed;

  /// Whether the preload was cancelled.
  final bool cancelled;

  /// Whether no preload phase is active.
  bool get isIdle => !pending && !loading && !completed && !failed && !cancelled;

  /// Whether the source is actively loading.
  bool get isRunning => loading;

  /// Whether the preload reached a terminal state.
  bool get isFinished => completed || failed || cancelled;

  /// Returns a copy with the given phase flags replaced.
  PreloadState copyWith({bool? pending, bool? loading, bool? completed, bool? failed, bool? cancelled}) {
    return PreloadState(
      pending: pending ?? this.pending,
      loading: loading ?? this.loading,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      cancelled: cancelled ?? this.cancelled,
    );
  }

  /// Returns the queued state.
  PreloadState queued() {
    return const PreloadState(pending: true);
  }

  /// Returns the loading state.
  PreloadState start() {
    return const PreloadState(loading: true);
  }

  /// Returns the successfully completed state.
  PreloadState complete() {
    return const PreloadState(completed: true);
  }

  /// Returns the failed state.
  PreloadState fail() {
    return const PreloadState(failed: true);
  }

  /// Returns the cancelled state.
  PreloadState cancel() {
    return const PreloadState(cancelled: true);
  }

  @override
  List<Object?> get props => [pending, loading, completed, failed, cancelled];
}
