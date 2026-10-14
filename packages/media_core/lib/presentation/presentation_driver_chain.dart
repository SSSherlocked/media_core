import 'package:media_core/identity/player_id.dart';
import 'package:media_core/kernel/kernel_presentation_driver.dart';
import 'package:media_core/presentation/presentation_mode.dart';
import 'package:media_core/presentation/presentation_request.dart';

/// Binds a driver to the presentation modes it owns.
///
/// One feature package owns one mode, so a host that installs fullscreen and
/// PiP end up with two drivers and the kernel's single driver slot between
/// them. This pairing is what lets [PresentationDriverChain] route a request
/// to the driver that can serve it.
///
/// [modes] must not be empty: a binding that owns nothing can never be routed
/// to, and silently keeping it would hide a wiring mistake.
final class PresentationDriverBinding {
  /// Binds [driver] to the [modes] it owns; rejects an empty [modes].
  PresentationDriverBinding({required Set<PresentationMode> modes, required this.driver})
    : assert(modes.isNotEmpty, 'A presentation driver binding must own at least one mode'),
      modes = Set<PresentationMode>.unmodifiable(modes);

  /// Modes [driver] is responsible for.
  final Set<PresentationMode> modes;

  /// The driver itself.
  final KernelPresentationDriver driver;

  /// Whether this binding's driver is the one to serve [mode].
  bool owns(PresentationMode mode) => modes.contains(mode);

  @override
  String toString() => 'PresentationDriverBinding(${modes.map((mode) => mode.name).join(', ')})';
}

/// Routes presentation requests to the feature driver that owns each mode.
///
/// Responsibilities:
///
/// - own the per-mode driver bindings
/// - route a request to the driver that declares the mode
/// - deactivate the previously active driver before activating another
/// - refuse a mode no installed driver serves
///
/// It does not:
///
/// - perform any platform call
/// - track presentation state (the presentation module does)
/// - decide when a mode change is appropriate
///
/// ## Why the previous driver is deactivated
///
/// Modes are not independent: a window cannot be fullscreen *and* a small
/// always-on-top window, and a mobile app cannot be in system
/// picture-in-picture while showing an in-app floating surface. With one
/// composite driver this cleanup happened inside its own `apply`, which was
/// possible only because the same object owned every mode. Once the modes live
/// in separate packages, the chain is the only place that knows the previous
/// owner, so it performs the exit: the outgoing driver is asked for
/// [PresentationMode.normal] before the incoming one is asked for its mode.
///
/// A driver that throws on a mode it does not own keeps standalone use
/// honest — installing only the fullscreen driver and requesting PiP is a
/// wiring error, not something to swallow.
final class PresentationDriverChain implements KernelPresentationDriver {
  /// Creates a chain from [bindings].
  ///
  /// Two bindings claiming the same mode is a wiring mistake, not a precedence
  /// question, and is rejected at construction.
  PresentationDriverChain({required List<PresentationDriverBinding> bindings})
    : bindings = List<PresentationDriverBinding>.unmodifiable(bindings) {
    final claimed = <PresentationMode>{};
    for (final binding in this.bindings) {
      for (final mode in binding.modes) {
        if (!claimed.add(mode)) {
          throw ArgumentError('Presentation mode ${mode.name} is claimed by more than one driver.');
        }
      }
    }
  }

  /// Installed bindings, in installation order.
  final List<PresentationDriverBinding> bindings;

  PresentationDriverBinding? _active;
  bool _disposed = false;

  /// Binding currently owning the presentation, or `null` when none is active.
  PresentationDriverBinding? get activeBinding => _active;

  /// Whether any installed driver serves [mode].
  ///
  /// [PresentationMode.normal] is always servable: it means "leave whatever is
  /// active", which is a no-op when nothing is.
  bool canServe(PresentationMode mode) => mode == PresentationMode.normal || _find(mode) != null;

  /// Drivers this chain can route to, in installation order.
  Iterable<KernelPresentationDriver> get drivers => bindings.map((binding) => binding.driver);

  @override
  Future<void> apply(PlayerId playerId, PresentationRequest request) async {
    if (_disposed) {
      throw StateError('PresentationDriverChain has been disposed.');
    }

    // Normal is the absence of a mode, so no driver owns it: it is served by
    // asking the active driver to release, and is a no-op when none is active.
    if (request.mode == PresentationMode.normal) {
      await _releaseActive(playerId);
      return;
    }

    final target = _find(request.mode);
    if (target == null) {
      throw UnsupportedError(
        'No presentation driver is installed for mode "${request.mode.name}". '
        'Installed modes: ${bindings.expand((binding) => binding.modes).map((mode) => mode.name).join(', ')}.',
      );
    }

    if (_active != null && !identical(_active, target)) {
      await _releaseActive(playerId);
    }

    await target.driver.apply(playerId, request);
    _active = target;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _active = null;
    for (final binding in bindings) {
      await binding.driver.dispose();
    }
  }

  /// Asks the active driver to release its mode, then forgets it.
  ///
  /// The outgoing feature releases its mode first; the incoming one must not
  /// have to know what it is replacing. A driver that fails to release is
  /// still forgotten, because keeping it active would block every later
  /// transition on a feature that is already known to be misbehaving.
  Future<void> _releaseActive(PlayerId playerId) async {
    final previous = _active;
    _active = null;
    if (previous == null) {
      return;
    }
    try {
      await previous.driver.apply(playerId, PresentationRequest.normal());
    } finally {
      _active = null;
    }
  }

  PresentationDriverBinding? _find(PresentationMode mode) {
    for (final binding in bindings) {
      if (binding.owns(mode)) {
        return binding;
      }
    }
    return null;
  }
}
