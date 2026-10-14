import 'package:clock/clock.dart';
import 'package:media_core/diagnostics/network_snapshot.dart';

/// Collects aggregate network diagnostics for the media core.
///
/// [NetworkDiagnostics] maintains the latest network diagnostic snapshot.
/// It receives measurements from the network layer or platform integration
/// and does not own the underlying network implementation.
///
/// Responsibilities:
///
/// - maintain the latest network snapshot
/// - track active network requests
/// - track transferred bytes
/// - record latency measurements
/// - record transfer rates
/// - maintain connection state
///
/// It does not:
///
/// - create network clients
/// - perform network requests
/// - monitor sockets directly
/// - determine network connectivity by itself
/// - retain a history of network snapshots
///
/// Those responsibilities belong to:
///
/// - network modules
/// - platform-specific network integrations
/// - diagnostics managers
final class NetworkDiagnostics {
  /// Creates network diagnostics.
  NetworkDiagnostics() : _snapshot = NetworkSnapshot(timestamp: clock.now());

  /// Latest network snapshot.
  NetworkSnapshot _snapshot;

  /// Whether these diagnostics have been disposed.
  bool _disposed = false;

  /// Current network snapshot.
  NetworkSnapshot get snapshot => _snapshot;

  /// Updates the current connection state.
  void setConnected({required bool connected}) {
    _ensureNotDisposed();

    _snapshot = _snapshot.copyWith(timestamp: clock.now(), connected: connected);
  }

  /// Updates the number of active network requests.
  ///
  /// Negative values are normalized to zero.
  void setActiveRequests(int count) {
    _ensureNotDisposed();

    _snapshot = _snapshot.copyWith(timestamp: clock.now(), activeRequests: count < 0 ? 0 : count);
  }

  /// Records received network bytes.
  ///
  /// [bytes] represents the number of newly received bytes.
  void recordReceived(int bytes) {
    _ensureNotDisposed();

    _snapshot = _snapshot.copyWith(timestamp: clock.now(), bytesReceived: _snapshot.bytesReceived + bytes);
  }

  /// Records sent network bytes.
  ///
  /// [bytes] represents the number of newly sent bytes.
  void recordSent(int bytes) {
    _ensureNotDisposed();

    _snapshot = _snapshot.copyWith(timestamp: clock.now(), bytesSent: _snapshot.bytesSent + bytes);
  }

  /// Records a network latency measurement.
  void recordLatency(Duration latency) {
    _ensureNotDisposed();

    _snapshot = _snapshot.copyWith(timestamp: clock.now(), latency: latency);
  }

  /// Records current network transfer rates.
  ///
  /// Rates are expressed in bytes per second.
  void recordRates({double? downloadBytesPerSecond, double? uploadBytesPerSecond}) {
    _ensureNotDisposed();

    _snapshot = _snapshot.copyWith(
      timestamp: clock.now(),
      downloadRateBytesPerSecond: downloadBytesPerSecond,
      uploadRateBytesPerSecond: uploadBytesPerSecond,
    );
  }

  /// Resets accumulated network measurements.
  ///
  /// The current connection state is preserved because resetting diagnostic
  /// counters does not imply that the network connection has changed.
  void reset() {
    _ensureNotDisposed();

    _snapshot = NetworkSnapshot(timestamp: clock.now(), connected: _snapshot.connected);
  }

  /// Disposes the diagnostics.
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('NetworkDiagnostics has been disposed.');
    }
  }
}
