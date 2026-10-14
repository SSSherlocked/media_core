/// Tunables for the download queue.
final class DownloadConfig {
  /// Creates a configuration, using defaults for the unspecified tunables.
  const DownloadConfig({
    this.maxConcurrent = 3,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 20),
    this.maxRedirects = 2,
    this.forceResume = false,
    this.verifyTailBytes = 10,
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Safari/537.36',
  });

  /// Caller-accepted defaults.
  static const DownloadConfig defaults = DownloadConfig();

  /// How many transfers may run at once.
  ///
  /// Three by default: enough that a queue drains quickly, few enough that a
  /// phone on a slow link is not switching between streams. The viewer owns this
  /// number — it is the difference between "downloads finish overnight" and
  /// "nothing else can use the network".
  final int maxConcurrent;

  /// Attempts per task before it is marked failed.
  final int maxAttempts;

  /// Delay before a retry.
  final Duration retryDelay;

  /// Connect/read timeout for the transfer.
  final Duration timeout;

  /// Redirects followed before a transfer is treated as failed.
  final int maxRedirects;

  /// Whether resume is attempted even when the server did not advertise
  /// `accept-ranges`.
  ///
  /// Off by default in the reference implementation because a server that says
  /// it cannot resume may still ignore the header and answer with the whole
  /// file, which would corrupt the partial one. Kept here as an explicit opt-in
  /// for servers known to support it silently.
  final bool forceResume;

  /// How many trailing bytes of a partial file are re-read to verify it.
  ///
  /// This is the reference implementation's integrity check for resume: the
  /// last few bytes are fetched again and compared with what is already on
  /// disk. A file that does not match is not a prefix of the remote file — a
  /// different quality, a changed file, or a corrupt write — and resuming it
  /// would produce a file that plays until exactly that point.
  final int verifyTailBytes;

  /// User agent sent with every request.
  final String userAgent;

  /// A copy with the given tunables replaced; omitted ones keep their current value.
  DownloadConfig copyWith({
    int? maxConcurrent,
    int? maxAttempts,
    Duration? retryDelay,
    Duration? timeout,
    int? maxRedirects,
    bool? forceResume,
    int? verifyTailBytes,
    String? userAgent,
  }) {
    return DownloadConfig(
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      retryDelay: retryDelay ?? this.retryDelay,
      timeout: timeout ?? this.timeout,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      forceResume: forceResume ?? this.forceResume,
      verifyTailBytes: verifyTailBytes ?? this.verifyTailBytes,
      userAgent: userAgent ?? this.userAgent,
    );
  }
}
