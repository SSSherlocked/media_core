import 'dart:async';

/// Decides which of mpv's error lines end the current source.
///
/// media_kit turns every error-level mpv log line with the prefix `file`,
/// `vd`, `ad`, `cplayer`, `stream` (and `ffmpeg` for `tcp:` lines) into an
/// error, and most of them are not fatal: a corrupt live packet is followed
/// by a good keyframe, a hardware decoder rejects a profile before mpv falls
/// back to software, a reconnect carries on the stream. Reporting each line
/// made the live sweep condemn healthy lines. So:
///
/// - [isTerminal] lines (the source cannot be opened, the codec is not
///   supported, the transport failed) are reported at once;
/// - any other line is held for [window]; progress of playback in that
///   window ([position] moving forward, or [progress]) drops it, otherwise
///   it is reported when the window ends;
/// - while one line is held, further non-terminal lines ride with it;
/// - the same text is reported once within [repeatWindow].
///
/// Pure Dart with no engine dependency, so it is unit-tested on its own.
/// Classification follows wzgrx's `NativeDiagnostic.classify` (pure_live
/// 4.x), with URLs removed from the text first: hosts, paths and queries
/// carry arbitrary words (`codec=264`) that must not decide anything.
final class MpvErrorGate {
  /// Creates a gate that reports confirmed failures to [onReport].
  MpvErrorGate({
    required this.onReport,
    this.onHeld,
    this.onDropped,
    this.window = const Duration(milliseconds: 1200),
    this.repeatWindow = const Duration(seconds: 2),
  });

  /// Receives the lines that end the current source.
  final void Function(String message) onReport;

  /// Told about a line that is held for [window].
  final void Function(String message)? onHeld;

  /// Told about a held line that playback progress made harmless.
  final void Function(String message)? onDropped;

  /// How long a non-terminal line waits for playback progress.
  final Duration window;

  /// Within this time the same text is reported only once.
  final Duration repeatWindow;

  bool _closed = false;
  Timer? _timer;
  String? _pending;
  Duration? _lastPosition;
  String? _lastReported;
  final Stopwatch _sinceReport = Stopwatch();

  /// Whether a line is held right now.
  bool get holding => _timer != null;

  /// One error line from media_kit's error stream.
  void error(String message) {
    if (_closed) return;

    if (isTerminal(message)) {
      // The held line, if any, is part of the same failure.
      _cancelPending();
      _report(message);
      return;
    }

    if (_timer != null) return;

    _pending = message;
    onHeld?.call(message);
    _timer = Timer(window, _expire);
  }

  /// A position sample; a position past the previous one is progress.
  void position(Duration position) {
    if (_closed) return;

    final last = _lastPosition;
    _lastPosition = position;

    if (last != null && position > last) progress();
  }

  /// Playback progressed (a new frame, a moving position): a held line was
  /// not fatal.
  void progress() {
    final pending = _pending;
    if (_closed || _timer == null || pending == null) return;

    _cancelPending();
    onDropped?.call(pending);
  }

  /// A new source opens, or the current one stopped: nothing of the
  /// previous one carries over.
  void reset() {
    _cancelPending();
    _lastPosition = null;
    _lastReported = null;
    _sinceReport
      ..stop()
      ..reset();
  }

  /// Stops for good; nothing is reported afterwards.
  void close() {
    _closed = true;
    reset();
  }

  void _expire() {
    _timer = null;
    final pending = _pending;
    _pending = null;

    if (pending == null || _closed) return;

    _report(pending);
  }

  void _report(String message) {
    if (_closed) return;

    if (_lastReported == message && _sinceReport.isRunning && _sinceReport.elapsed < repeatWindow) {
      return;
    }

    _lastReported = message;
    _sinceReport
      ..reset()
      ..start();

    onReport(message);
  }

  void _cancelPending() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  // ---------------------------------------------------------------------------
  // Classification
  // ---------------------------------------------------------------------------

  /// Whether [message] ends the current source without waiting.
  ///
  /// A line that says the stream will be reconnected is never terminal,
  /// whatever error it quotes: ffmpeg carries on by itself.
  static bool isTerminal(String message) {
    final text = withoutUrls(message.toLowerCase());

    if (_any(text, _recovering)) return false;

    return _any(text, _lifecycle) ||
        _any(text, _videoOutput) ||
        _any(text, _decoderInit) ||
        _any(text, _transport) ||
        _httpServerFailure.hasMatch(text) ||
        _any(text, _sourceOpen);
  }

  /// [text] with every URL replaced by a space.
  static String withoutUrls(String text) => text.replaceAll(_url, ' ');

  static bool _any(String text, List<String> markers) => markers.any(text.contains);

  static final RegExp _url = RegExp(r'[a-z][a-z0-9+.-]*://\S*', caseSensitive: false);

  static final RegExp _httpServerFailure = RegExp(r'(?:server returned|http error)\s+5\d\d(?:\D|$)');

  /// ffmpeg recovers from these by itself (the http protocol's reconnect).
  static const _recovering = ['will reconnect', 'reconnecting', 'tls read returned', 'ffurl_read returned'];

  static const _lifecycle = [
    'player has been disposed',
    'player has been released',
    'operation was cancelled',
    'operation was canceled',
  ];

  static const _videoOutput = [
    'surface has been released',
    'failed to create surface',
    'failed to create texture',
    'texture is unavailable',
    'egl_bad',
    'vulkan error',
    'gpu context failed',
  ];

  static const _decoderInit = ['no decoder found', 'unsupported codec', 'codec is not supported'];

  static const _transport = [
    'connection timed out',
    'network timeout',
    'network is down',
    'network is unreachable',
    'host is unreachable',
    'connection refused',
    'connection reset',
    'connection aborted',
    'software caused connection abort',
    'broken pipe',
    'no route to host',
    'failed to resolve',
    'could not resolve host',
    'unable to resolve host',
    'no address associated with hostname',
    'getaddrinfo failed',
    'nodename nor servname',
    'no such host is known',
    'temporary failure in name resolution',
    'name or service not known',
    'tls handshake',
    'ssl handshake',
    'certificate verify failed',
    'input/output error',
    'i/o error',
  ];

  static const _sourceOpen = [
    'server returned 401',
    'server returned 403',
    'server returned 404',
    'http error 401',
    'http error 403',
    'http error 404',
    'protocol not found',
    'unknown protocol',
    'no protocol handler',
    // mpv's own "Failed to open <url>." ends the file it was loading.
    'failed to open',
    'error opening input',
    'unable to open input',
    'invalid data found when processing input',
    'could not find codec parameters',
    'no streams found',
  ];
}
