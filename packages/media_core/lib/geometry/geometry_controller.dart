import 'dart:async';

import 'package:media_core/geometry/display_size.dart';
import 'package:media_core/geometry/geometry_event.dart';
import 'package:media_core/geometry/geometry_snapshot.dart';
import 'package:media_core/geometry/geometry_state.dart';
import 'package:media_core/geometry/video_geometry.dart';
import 'package:media_core/geometry/video_rotation.dart';
import 'package:media_core/geometry/video_size.dart';
import 'package:rxdart/rxdart.dart';

/// Controls video geometry lifecycle.
///
/// Responsibilities:
///
/// - own geometry state
/// - receive geometry events
/// - reduce state changes
/// - provide immutable snapshots
/// - protect against stale async updates
///
/// Does not:
///
/// - perform layout
/// - resize widgets
/// - control renderer
/// - call platform APIs
final class GeometryController {
  /// Creates a controller publishing [initialState] as its first state.
  GeometryController({GeometryState initialState = const GeometryState.initial()})
    : _stateSubject = BehaviorSubject<GeometryState>.seeded(initialState) {
    // The counter follows the restored state: starting from zero would make
    // every later update carry a generation the reducer rejects as stale.
    _generation = initialState.generation;
  }

  final BehaviorSubject<GeometryState> _stateSubject;

  bool _disposed = false;

  late int _generation;

  /// Current state stream.
  ValueStream<GeometryState> get state => _stateSubject.stream;

  /// Current state.
  GeometryState get current => _stateSubject.value;

  /// Current snapshot.
  GeometrySnapshot get snapshot => GeometrySnapshot.fromState(current);

  /// Current geometry.
  VideoGeometry get geometry => current.geometry;

  /// Current generation.
  int get generation => _generation;

  /// Whether geometry initialized.
  bool get initialized => current.initialized;

  /// Updates geometry.
  ///
  /// Called by:
  ///
  /// - player adapter
  /// - renderer backend
  /// - media metadata parser
  void update(VideoGeometry geometry) {
    _ensureNotDisposed();

    final generation = _advanceGeneration();

    dispatch(GeometryEvent.changed(geometry, generation));
  }

  /// Updates video size.
  void updateVideoSize(VideoSize size) {
    _ensureNotDisposed();

    final next = current.geometry.copyWithVideoSize(size);

    update(next);
  }

  /// Updates display size.
  void updateDisplaySize(DisplaySize size) {
    _ensureNotDisposed();

    final next = current.geometry.copyWithDisplaySize(size);

    update(next);
  }

  /// Updates rotation.
  void updateRotation(VideoRotationInfo rotation) {
    _ensureNotDisposed();

    final next = current.geometry.copyWithRotation(rotation);

    update(next);
  }

  /// Clears geometry.
  void clear() {
    _ensureNotDisposed();

    final generation = _advanceGeneration();

    dispatch(GeometryEvent.reset(generation));
  }

  /// Receives geometry event.
  void dispatch(GeometryEvent event) {
    _ensureNotDisposed();

    final next = current.reduce(event);

    if (next != current) {
      _stateSubject.add(next);
    }
  }

  /// Restores state.
  void restore(GeometryState state) {
    _ensureNotDisposed();

    if (state.generation < _generation) {
      return;
    }

    _generation = state.generation > _generation ? state.generation : _generation;

    _stateSubject.add(state);
  }

  /// Starts a new generation without changing the geometry.
  ///
  /// The new generation is published, not only counted: a caller that tags an
  /// asynchronous update with it needs the state to move with the counter, or
  /// the callback would look stale the moment it arrives. Marking the state
  /// also means every earlier callback is rejected from here on.
  int nextGeneration() {
    _ensureNotDisposed();

    final generation = _advanceGeneration();

    _stateSubject.add(current.withGeneration(generation));

    return generation;
  }

  /// Advances the generation counter past both the counter and the state.
  ///
  /// The two can diverge — a restored state arrives with its own generation —
  /// and an event below the state's generation is discarded, so the next
  /// generation has to be strictly newer than both.
  int _advanceGeneration() {
    final stateGeneration = current.generation;

    return _generation = (_generation > stateGeneration ? _generation : stateGeneration) + 1;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('GeometryController has already been disposed.');
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _stateSubject.close();
  }
}
