import 'dart:async';

import 'package:media_core/media_core.dart';

import 'package:media_core_presentation/src/media_core_presentation.dart';

/// Bridges a [MediaCorePresentation] driver into the core
/// presentation module's [PresentationAdapter] contract.
///
/// Use this when wiring through `PresentationController` /
/// `PresentationCoordinator` instead of (or alongside) assigning
/// [PlayerKernel.presentationDriver]:
///
/// ```dart
/// final driver = MediaCorePresentation();
/// await driver.initialize();
///
/// final adapter = KernelPresentationAdapter(driver);
/// final controller = PresentationController();
/// // PresentationRequest flows: controller → adapter → driver → platform
/// ```
///
/// Nothing in this repository constructs it: every current host reaches the
/// driver through the kernel. It is kept for a host that owns the adapter
/// contract, and is not exercised by any test here.
final class KernelPresentationAdapter extends PresentationAdapterBase {
  /// Creates the adapter wrapping [driver].
  KernelPresentationAdapter(this.driver) : super(initialCapabilities: _capabilitiesFor(driver));

  /// The wrapped capability driver.
  final MediaCorePresentation driver;

  static PresentationCapabilities _capabilitiesFor(MediaCorePresentation driver) {
    return PresentationCapabilities(
      // PiP and the in-window floating mode are only served on desktop here;
      // system picture-in-picture belongs to media_core_pip's own drivers.
      pip: driver.supportsPresentationWindow,
      floating: driver.supportsPresentationWindow,
    );
  }

  @override
  Future<void> apply(PresentationRequest request) async {
    // The adapter contract has no player identity; the driver's
    // window-level operations do not need one on desktop.
    final playerId = PlayerId('presentation-adapter');
    await driver.apply(playerId, request);
    // Echo the request generation: this event reports the outcome of *this*
    // transition, and a callback left over from an older request must not be
    // able to overwrite newer presentation state.
    emit(PresentationEvent.changed(mode: request.mode, generation: request.generation, source: 'kernel-adapter'));
  }

  @override
  Future<void> refreshCapabilities() async {
    updateCapabilities(_capabilitiesFor(driver));
  }

  @override
  Future<void> onDispose() async {
    await driver.dispose();
  }
}
