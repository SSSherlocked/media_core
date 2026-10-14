/// Transfer state of one task.
final class DownloadProgress {
  /// Creates a progress snapshot.
  const DownloadProgress({
    this.receivedBytes = 0,
    this.totalBytes = -1,
    this.speedBytesPerSecond = 0,
    this.attempt = 1,
    this.pendingWrites = 0,
  });

  /// Bytes on disk for this task, including a resumed prefix.
  final int receivedBytes;

  /// Report size of the remote file, or `-1` when unknown.
  ///
  /// Unknown is normal: a server may answer without a content length, and a
  /// progressive stream has no defined size. Progress is then reported as bytes
  /// only, and a host must not show a percentage.
  final int totalBytes;

  /// Recent transfer rate.
  final int speedBytesPerSecond;

  /// Which attempt this transfer is.
  final int attempt;

  /// Writes queued behind the disk.
  ///
  /// Surfaced because a download on a slow disk is not a slow network: a host
  /// that shows "slow" without this cannot tell the viewer which one to fix.
  final int pendingWrites;

  /// Whether the remote size is known.
  bool get hasTotal => totalBytes > 0;

  /// Completion in `0..1`, or `null` when the total is unknown.
  double? get fraction => hasTotal ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;

  /// Completion as a whole percentage, or `null` when the total is unknown.
  int? get percent => hasTotal ? ((fraction ?? 0) * 100).round() : null;

  /// Bytes still to transfer, or `null` when the total is unknown.
  int? get remainingBytes => hasTotal ? (totalBytes - receivedBytes).clamp(0, totalBytes) : null;

  /// Estimated time remaining, or `null` when it cannot be estimated.
  Duration? get remaining {
    final remainingBytes = this.remainingBytes;
    if (remainingBytes == null || speedBytesPerSecond <= 0) {
      return null;
    }
    return Duration(seconds: (remainingBytes / speedBytesPerSecond).ceil());
  }

  /// A copy with the given fields replaced; omitted ones keep their current value.
  DownloadProgress copyWith({
    int? receivedBytes,
    int? totalBytes,
    int? speedBytesPerSecond,
    int? attempt,
    int? pendingWrites,
  }) {
    return DownloadProgress(
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      attempt: attempt ?? this.attempt,
      pendingWrites: pendingWrites ?? this.pendingWrites,
    );
  }

  @override
  String toString() => 'DownloadProgress($receivedBytes/${hasTotal ? totalBytes : '?'}B, $speedBytesPerSecond B/s)';
}
