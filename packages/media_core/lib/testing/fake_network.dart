import 'dart:async';

import 'package:media_core/network/network_condition.dart';
import 'package:media_core/network/network_metrics.dart';
import 'package:media_core/network/network_monitor.dart';
import 'package:media_core/network/network_state.dart';

/// Scriptable [NetworkMonitor] for tests.
///
/// State changes are pushed manually through [updateState] and
/// replayed to subscribers of the broadcast streams.
final class FakeNetworkMonitor implements NetworkMonitor {
  final StreamController<NetworkState> _stateController = StreamController<NetworkState>.broadcast();
  final StreamController<NetworkCondition> _conditionController = StreamController<NetworkCondition>.broadcast();
  final StreamController<NetworkMetrics> _metricsController = StreamController<NetworkMetrics>.broadcast();

  NetworkState _state = NetworkState.initial();
  NetworkMetrics _metrics = const NetworkMetrics();
  bool _started = false;
  bool _disposed = false;

  @override
  NetworkState get state => _state;

  @override
  NetworkCondition get condition => _state.toCondition();

  @override
  NetworkMetrics get metrics => _metrics;

  @override
  Stream<NetworkState> get stateStream => _stateController.stream;

  @override
  Stream<NetworkCondition> get conditionStream => _conditionController.stream;

  @override
  Stream<NetworkMetrics> get metricsStream => _metricsController.stream;

  /// Whether [start] was called.
  bool get started => _started;

  /// Whether [dispose] was called.
  bool get disposed => _disposed;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _started = false;
    await _stateController.close();
    await _conditionController.close();
    await _metricsController.close();
  }

  /// Pushes a new network state to subscribers.
  void updateState(NetworkState state) {
    _state = state;
    _stateController.add(state);
    _conditionController.add(state.toCondition());
  }

  /// Pushes new metrics to subscribers.
  void updateMetrics(NetworkMetrics metrics) {
    _metrics = metrics;
    _metricsController.add(metrics);
  }
}

extension on NetworkState {
  /// Derives a condition snapshot from the state.
  NetworkCondition toCondition() {
    return NetworkCondition(connected: connected, type: type, quality: quality, metered: metered, expensive: expensive);
  }
}
