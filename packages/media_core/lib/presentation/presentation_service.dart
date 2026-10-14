import 'dart:async';

import 'package:media_core/geometry/video_orientation.dart';
import 'package:media_core/presentation/presentation_adapter.dart';
import 'package:media_core/presentation/presentation_capabilities.dart';
import 'package:media_core/presentation/presentation_controller.dart';
import 'package:media_core/presentation/presentation_event.dart';
import 'package:media_core/presentation/presentation_request.dart';
import 'package:media_core/presentation/presentation_state.dart';
import 'package:rxdart/rxdart.dart';

/// Application level presentation service.
///
/// PresentationService is the public API layer
/// above PresentationController.
///
/// Responsibilities:
///
/// - expose presentation API
/// - forward requests
/// - expose presentation state
/// - expose capabilities
/// - synchronize adapter events
///
/// Does not:
///
/// - own presentation state
/// - execute platform operations
/// - call native APIs
/// - manage windows
///
/// Platform operations are handled by:
///
/// PresentationAdapter
///
/// Nothing in the package constructs this service; it is a host-facing API
/// layer that a host builds from its own [PresentationController] and adapter.
/// It stays inert until a host wires it.
final class PresentationService {
  /// Binds [controller] to [adapter], forwarding the adapter's events into the controller.
  PresentationService({required PresentationController controller, required PresentationAdapter adapter})
    : _controller = controller,
      _adapter = adapter {
    _eventSubscription = _adapter.events.listen(_onEvent);
    _capabilitySubscription = _adapter.capabilityChanges.listen(_onCapabilities);

    // The state carries the same capabilities the adapter reports, so a reader
    // that only watches [state] sees the platform it is running on.
    _controller.updateCapabilities(_adapter.capabilities);
  }

  final PresentationController _controller;

  final PresentationAdapter _adapter;

  StreamSubscription<PresentationEvent>? _eventSubscription;

  StreamSubscription<PresentationCapabilities>? _capabilitySubscription;

  bool _disposed = false;

  // ============================================================
  // State
  // ============================================================

  /// Current presentation state stream.
  ValueStream<PresentationState> get state => _controller.state;

  /// Current presentation state.
  PresentationState get current => _controller.current;

  /// Current platform capabilities.
  PresentationCapabilities get capabilities => _adapter.capabilities;

  /// Updates the media orientation the presentation describes.
  ///
  /// Fed from the video-size events the host already receives; see
  /// [PresentationController.updateOrientation].
  void updateOrientation(VideoOrientation orientation) {
    _ensureNotDisposed();

    _controller.updateOrientation(orientation);
  }

  // ============================================================
  // Request API
  // ============================================================

  /// Requests presentation change.
  ///
  /// Flow:
  ///
  /// UI
  ///  |
  /// PresentationService
  ///  |
  /// PresentationController  (logical transition + generation)
  ///  |
  /// PresentationAdapter     (platform execution)
  ///
  /// The adapter executes the request stamped with the generation the
  /// controller assigned, so the events the adapter reports are matched to
  /// this transition instead of being discarded as stale. A platform failure
  /// is recorded in the state and does not escape to the caller: the
  /// presentation state stream is the observable outcome of a request.
  Future<void> request(PresentationRequest request) async {
    _ensureNotDisposed();

    final generation = await _controller.request(request);

    try {
      await _adapter.apply(request.copyWith(generation: generation));
    } on Object catch (error) {
      _controller.handleEvent(
        PresentationEvent.failed(
          mode: request.mode,
          error: error.toString(),
          generation: generation,
          source: request.source,
        ),
      );

      return;
    }

    _settleTransition(request, generation);
  }

  /// Enter fullscreen.
  Future<void> enterFullscreen() {
    return request(PresentationRequest.fullscreen());
  }

  /// Exit fullscreen.
  Future<void> exitFullscreen() {
    return request(PresentationRequest.normal());
  }

  /// Enter picture-in-picture.
  Future<void> enterPip() {
    return request(PresentationRequest.pip());
  }

  /// Exit picture-in-picture.
  Future<void> exitPip() {
    return request(PresentationRequest.normal());
  }

  /// Enter floating window.
  Future<void> enterFloating() {
    return request(PresentationRequest.floating());
  }

  /// Exit current presentation mode.
  Future<void> exit() {
    return request(PresentationRequest.normal(source: 'service'));
  }

  // ============================================================
  // Capability
  // ============================================================

  /// Refresh platform capability.
  ///
  /// Adapter updates its own capability state.
  ///
  /// Controller reads capability when needed.
  Future<void> refreshCapabilities() async {
    _ensureNotDisposed();

    await _adapter.refreshCapabilities();

    // An adapter that reports through [PresentationAdapter.capabilityChanges]
    // already updated the state; one that only mutates its own view is synced
    // here so the state never lags behind the platform.
    if (!_disposed) {
      _controller.updateCapabilities(_adapter.capabilities);
    }
  }

  // ============================================================
  // Events
  // ============================================================

  /// Receives platform events.
  void _onEvent(PresentationEvent event) {
    if (_disposed) {
      return;
    }

    _controller.handleEvent(event);
  }

  /// Receives platform capability changes.
  void _onCapabilities(PresentationCapabilities capabilities) {
    if (_disposed) {
      return;
    }

    _controller.updateCapabilities(capabilities);
  }

  /// Completes a transition the adapter returned from without reporting.
  ///
  /// Adapters may report through [PresentationAdapter.events], and one that
  /// does has already cleared the transition by the time [request] resumes.
  /// When `apply` returns silently the platform operation is nonetheless done,
  /// so leaving the state transitioning would strand every reader waiting for
  /// it to settle.
  void _settleTransition(PresentationRequest request, int generation) {
    if (_disposed) {
      return;
    }

    final state = _controller.current;

    if (state.generation != generation || !state.transitioning) {
      return;
    }

    _controller.handleEvent(
      PresentationEvent.completed(mode: request.mode, generation: generation, source: request.source),
    );
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PresentationService has already been disposed.');
    }
  }

  /// Releases resources.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _capabilitySubscription?.cancel();
    _capabilitySubscription = null;

    await _adapter.dispose();

    await _controller.dispose();
  }
}
