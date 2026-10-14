import 'dart:async';

import 'package:media_core/network/network_condition.dart';
import 'package:media_core/network/network_metrics.dart';
import 'package:media_core/network/network_state.dart';

/// Monitors network changes.
///
/// [NetworkMonitor] provides an abstraction for observing
/// network state changes and metrics.
///
/// Responsibilities:
///
/// - expose network condition stream
/// - expose network state stream
/// - expose metrics updates
/// - manage monitor lifecycle
///
/// It does not:
///
/// - access platform APIs directly
/// - perform connectivity checks
/// - execute network requests
///
/// Platform implementations belong to:
///
/// - platform/
/// - adapter/
abstract interface class NetworkMonitor {
  /// Current network state.
  NetworkState get state;

  /// Current network condition.
  NetworkCondition get condition;

  /// Latest network metrics.
  NetworkMetrics get metrics;

  /// Stream of network state changes.
  Stream<NetworkState> get stateStream;

  /// Stream of network condition changes.
  Stream<NetworkCondition> get conditionStream;

  /// Stream of metrics updates.
  Stream<NetworkMetrics> get metricsStream;

  /// Starts monitoring.
  Future<void> start();

  /// Stops monitoring.
  Future<void> stop();

  /// Releases resources.
  Future<void> dispose();
}

/// Base implementation for network monitors.
///
/// Platform implementations can extend this class
/// and update state through protected methods.
abstract class BaseNetworkMonitor implements NetworkMonitor {
  /// Creates a monitor with the broadcast controllers that back the state,
  /// condition and metrics streams platform implementations publish into.
  BaseNetworkMonitor();

  final StreamController<NetworkState> _stateController = StreamController<NetworkState>.broadcast();

  final StreamController<NetworkCondition> _conditionController = StreamController<NetworkCondition>.broadcast();

  final StreamController<NetworkMetrics> _metricsController = StreamController<NetworkMetrics>.broadcast();

  NetworkState _state = NetworkState.initial();

  NetworkCondition _condition = NetworkCondition.unknown();

  NetworkMetrics _metrics = NetworkMetrics.empty();

  bool _started = false;

  @override
  NetworkState get state {
    return _state;
  }

  @override
  NetworkCondition get condition {
    return _condition;
  }

  @override
  NetworkMetrics get metrics {
    return _metrics;
  }

  @override
  Stream<NetworkState> get stateStream {
    return _stateController.stream;
  }

  @override
  Stream<NetworkCondition> get conditionStream {
    return _conditionController.stream;
  }

  @override
  Stream<NetworkMetrics> get metricsStream {
    return _metricsController.stream;
  }

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;

    await onStart();
  }

  @override
  Future<void> stop() async {
    if (!_started) {
      return;
    }

    _started = false;

    await onStop();
  }

  /// Called when monitoring starts.
  Future<void> onStart();

  /// Called when monitoring stops.
  Future<void> onStop();

  /// Updates current network state.
  void updateState(NetworkState value) {
    _state = value;

    _stateController.add(value);
  }

  /// Updates current network condition.
  void updateCondition(NetworkCondition value) {
    _condition = value;

    _conditionController.add(value);
  }

  /// Updates current metrics.
  void updateMetrics(NetworkMetrics value) {
    _metrics = value;

    _metricsController.add(value);
  }

  @override
  Future<void> dispose() async {
    await stop();

    await _stateController.close();
    await _conditionController.close();
    await _metricsController.close();
  }
}
