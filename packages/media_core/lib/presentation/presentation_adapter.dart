import 'dart:async';

import 'package:media_core/presentation/presentation_capabilities.dart';
import 'package:media_core/presentation/presentation_event.dart';
import 'package:media_core/presentation/presentation_request.dart';

/// Platform presentation adapter.
///
/// Responsible for communicating with
/// native presentation APIs.
///
/// Examples:
///
/// - Android PiP
/// - iOS PiP
/// - Windows fullscreen
/// - macOS window mode
///
/// Adapter does not:
///
/// - own presentation state
/// - manage lifecycle
/// - decide transitions
abstract interface class PresentationAdapter {
  /// Current platform capability.
  PresentationCapabilities get capabilities;

  /// Emits capability changes.
  ///
  /// Examples:
  ///
  /// - PiP permission changed
  /// - device capability changed
  /// - window environment changed
  Stream<PresentationCapabilities> get capabilityChanges;

  /// Platform presentation events.
  ///
  /// Examples:
  ///
  /// - fullscreen entered
  /// - PiP entered
  /// - floating closed
  Stream<PresentationEvent> get events;

  /// Executes platform operation.
  Future<void> apply(PresentationRequest request);

  /// Refresh capabilities.
  Future<void> refreshCapabilities();

  /// Release resources.
  Future<void> dispose();
}
