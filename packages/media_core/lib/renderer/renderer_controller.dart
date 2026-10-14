import 'dart:async';

import 'package:clock/clock.dart';
import 'package:media_core/renderer/renderer_capabilities.dart';
import 'package:media_core/renderer/renderer_config.dart';
import 'package:media_core/renderer/renderer_state.dart';
import 'package:rxdart/rxdart.dart';

/// Controls renderer lifecycle and state.
///
/// The controller owns renderer state but does not implement
/// platform-specific rendering.
///
/// Responsibilities:
///
/// - initialize renderer state
/// - update renderer configuration
/// - track surface readiness
/// - track rendering state
/// - track renderer generation
/// - expose reactive state
///
/// Does not:
///
/// - create platform surfaces
/// - control video playback
/// - perform video geometry calculations
/// - call platform APIs
final class RendererController {
  /// Creates a controller whose state starts at [initialState].
  ///
  /// The generation is taken from that state rather than starting at zero, so a
  /// controller restored after a surface was recreated keeps rejecting reports
  /// from the renderer instance it replaced.
  RendererController({RendererState initialState = const RendererState.initial()})
    : _stateSubject = BehaviorSubject<RendererState>.seeded(initialState),
      _generation = initialState.generation;

  final BehaviorSubject<RendererState> _stateSubject;

  bool _disposed = false;
  int _generation;

  /// Reactive renderer state.
  ValueStream<RendererState> get state => _stateSubject.stream;

  /// Current renderer state.
  RendererState get current => _stateSubject.value;

  /// Current renderer generation.
  int get generation => _generation;

  /// What the current renderer says it can do.
  RendererCapabilities get capabilities => current.capabilities;

  /// How the current renderer has been asked to present video.
  RendererConfig get config => current.config;

  /// Whether the renderer has been initialized with its capabilities.
  bool get initialized => current.initialized;

  /// Whether a surface exists that frames can be drawn into.
  bool get surfaceReady => current.surfaceReady;

  /// Whether frames are being drawn right now.
  bool get rendering => current.rendering;

  /// Whether a first frame could be displayed: initialized, surface ready,
  /// capable and enabled all at once.
  bool get canRender => current.canRender;

  /// Initializes the renderer.
  ///
  /// A new generation can be supplied when the platform renderer has been
  /// recreated externally. Otherwise the current generation is preserved.
  void initialize({required RendererCapabilities capabilities, RendererConfig? config, int? generation}) {
    _ensureNotDisposed();

    if (generation != null) {
      _generation = generation;
    }

    final next = current.initialize(
      capabilities: capabilities,
      config: config,
      generation: _generation,
      updatedAt: clock.now(),
    );

    _emit(next);
  }

  /// Updates renderer configuration.
  void updateConfig(RendererConfig config) {
    _ensureNotDisposed();

    _emit(current.copyWith(config: config, updatedAt: clock.now()));
  }

  /// Updates renderer surface readiness.
  ///
  /// Losing the surface also stops rendering: a frame drawn into a surface the
  /// platform took back is not a frame anyone can see.
  void setSurfaceReady({required bool value}) {
    _ensureNotDisposed();

    _emit(current.markSurfaceReady(value: value, generation: _generation, updatedAt: clock.now()));
  }

  /// Starts rendering when the renderer is ready.
  void startRendering() {
    _ensureNotDisposed();

    _emit(current.startRendering(updatedAt: clock.now()));
  }

  /// Stops rendering while keeping the renderer initialized.
  void stopRendering() {
    _ensureNotDisposed();

    _emit(current.stopRendering(updatedAt: clock.now()));
  }

  /// Updates renderer capabilities.
  ///
  /// If the new capabilities cannot render video, active rendering is stopped
  /// automatically.
  void updateCapabilities(RendererCapabilities capabilities) {
    _ensureNotDisposed();

    var next = current.copyWith(capabilities: capabilities, updatedAt: clock.now());

    if (!capabilities.canRender && next.rendering) {
      next = next.stopRendering(updatedAt: clock.now());
    }

    _emit(next);
  }

  /// Advances the renderer generation and invalidates the current renderer
  /// lifecycle.
  ///
  /// This is normally called when the underlying rendering surface or native
  /// renderer is recreated.
  int nextGeneration() {
    _ensureNotDisposed();

    _generation++;

    _emit(current.nextGeneration(updatedAt: clock.now()));

    return _generation;
  }

  /// Resets renderer state while preserving the current generation.
  void reset() {
    _ensureNotDisposed();

    _emit(current.reset(updatedAt: clock.now()));
  }

  /// Restores a previously captured renderer state.
  ///
  /// The controller generation is updated to the restored state's generation
  /// so that subsequent asynchronous renderer operations use the same
  /// generation boundary.
  void restore(RendererState state) {
    _ensureNotDisposed();

    _generation = state.generation;
    _emit(state);
  }

  void _emit(RendererState state) {
    if (_disposed) {
      return;
    }

    if (state.generation > _generation) {
      _generation = state.generation;
    }

    _stateSubject.add(state);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('RendererController has been disposed.');
    }
  }

  /// Releases the reactive state stream.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _stateSubject.close();
  }
}
