import 'dart:async';

import 'package:media_core/presentation/presentation_adapter.dart';
import 'package:media_core/presentation/presentation_capabilities.dart';
import 'package:media_core/presentation/presentation_event.dart';

/// Base implementation of PresentationAdapter.
///
/// Provides common adapter infrastructure:
///
/// - event stream
/// - capability storage
/// - lifecycle management
///
/// Does not:
///
/// - execute transitions
/// - create events automatically
/// - manage presentation state
abstract class PresentationAdapterBase implements PresentationAdapter {
  /// Creates the adapter infrastructure with [initialCapabilities].
  PresentationAdapterBase({PresentationCapabilities initialCapabilities = const PresentationCapabilities()})
    : _capabilities = initialCapabilities;

  PresentationCapabilities _capabilities;

  final StreamController<PresentationEvent> _eventController = StreamController.broadcast();

  final StreamController<PresentationCapabilities> _capabilityController = StreamController.broadcast();

  bool _disposed = false;

  // ------------------------------------------------------------
  // Capability
  // ------------------------------------------------------------

  @override
  PresentationCapabilities get capabilities => _capabilities;

  @override
  Stream<PresentationCapabilities> get capabilityChanges => _capabilityController.stream;

  /// Replaces the reported capabilities and publishes them on [capabilityChanges].
  ///
  /// Throws once the adapter has been disposed, so a late platform callback
  /// cannot resurrect capability reporting after teardown.
  void updateCapabilities(PresentationCapabilities value) {
    _ensureNotDisposed();

    _capabilities = value;

    _capabilityController.add(value);
  }

  // ------------------------------------------------------------
  // Events
  // ------------------------------------------------------------

  @override
  Stream<PresentationEvent> get events => _eventController.stream;

  /// Emit platform event.
  ///
  /// Example:
  ///
  /// Android:
  /// entered PiP
  ///
  /// Windows:
  /// fullscreen changed
  void emit(PresentationEvent event) {
    if (_disposed) {
      return;
    }

    _eventController.add(event);
  }

  // ------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PresentationAdapter disposed');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;

    await onDispose();

    await _eventController.close();

    await _capabilityController.close();
  }

  /// Platform cleanup.
  Future<void> onDispose() async {}
}
