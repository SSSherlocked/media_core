import 'package:media_core/network/network_condition.dart';
import 'package:media_core/network/network_metrics.dart';
import 'package:media_core/network/network_monitor.dart';
import 'package:media_core/network/network_request.dart';
import 'package:media_core/network/network_response.dart';
import 'package:media_core/network/network_state.dart';

/// Manages network operations and state.
///
/// [NetworkManager] is the main entry point for
/// network-related functionality inside media_core.
///
/// Responsibilities:
///
/// - manage network monitor lifecycle
/// - expose current network state
/// - execute network requests
/// - provide network information
///
/// It does not:
///
/// - implement HTTP protocol
/// - access platform APIs directly
/// - decode business models
///
/// Those belong to:
///
/// - adapters
/// - platform implementations
final class NetworkManager {
  /// Creates a network manager.
  NetworkManager({required NetworkMonitor monitor, NetworkRequestExecutor? executor})
    : _monitor = monitor,
      _executor = executor;

  final NetworkMonitor _monitor;

  final NetworkRequestExecutor? _executor;

  /// Current network state.
  NetworkState get state {
    return _monitor.state;
  }

  /// Current network condition.
  NetworkCondition get condition {
    return _monitor.condition;
  }

  /// Current metrics.
  NetworkMetrics get metrics {
    return _monitor.metrics;
  }

  /// Network state changes.
  Stream<NetworkState> get stateStream {
    return _monitor.stateStream;
  }

  /// Network condition changes.
  Stream<NetworkCondition> get conditionStream {
    return _monitor.conditionStream;
  }

  /// Network metrics changes.
  Stream<NetworkMetrics> get metricsStream {
    return _monitor.metricsStream;
  }

  /// Starts network monitoring.
  Future<void> start() {
    return _monitor.start();
  }

  /// Stops network monitoring.
  Future<void> stop() {
    return _monitor.stop();
  }

  /// Executes a network request.
  ///
  /// Throws [StateError] when no executor
  /// has been configured.
  Future<NetworkResponse> request(NetworkRequest request) {
    final executor = _executor;

    if (executor == null) {
      throw StateError('No NetworkRequestExecutor configured');
    }

    return executor.execute(request);
  }

  /// Releases resources.
  Future<void> dispose() async {
    await _monitor.dispose();
  }
}

/// Executes network requests.
///
/// Implementations can be provided by:
///
/// - http adapter
/// - dio adapter
/// - platform network layer
abstract interface class NetworkRequestExecutor {
  /// Executes a request.
  Future<NetworkResponse> execute(NetworkRequest request);
}
