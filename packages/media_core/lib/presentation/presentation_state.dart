import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/geometry/video_orientation.dart';
import 'package:media_core/presentation/presentation_adapter.dart' show PresentationAdapter;
import 'package:media_core/presentation/presentation_capabilities.dart';
import 'package:media_core/presentation/presentation_mode.dart';

part 'presentation_state.freezed.dart';

/// Represents the current presentation lifecycle state.
///
/// This state is the logical source of truth for the
/// presentation subsystem.
///
/// It describes:
///
/// - current presentation mode
/// - target presentation mode
/// - transition status
/// - presentation capabilities
/// - presentation availability
/// - presentation errors
/// - lifecycle generation
///
/// It does not:
///
/// - enter fullscreen
/// - leave fullscreen
/// - create a PiP window
/// - create a floating window
/// - call platform APIs
/// - control system UI
///
/// Platform-specific operations are handled by
/// [PresentationAdapter].
@freezed
abstract class PresentationState with _$PresentationState {
  /// Creates a presentation state from its fields.
  const factory PresentationState({
    /// Current active presentation mode.
    ///
    /// This represents the mode that has successfully
    /// completed.
    ///
    /// During a transition, this value remains unchanged
    /// until the transition is completed.
    @Default(PresentationMode.normal) PresentationMode mode,

    /// Target presentation mode.
    ///
    /// This is non-null while a transition is being
    /// processed.
    ///
    /// Example:
    ///
    /// ```text
    /// mode:
    ///   normal
    ///
    /// targetMode:
    ///   fullscreen
    ///
    /// transitioning:
    ///   true
    /// ```
    PresentationMode? targetMode,

    /// Presentation capabilities reported by the
    /// current environment.
    ///
    /// Capabilities describe what the environment supports.
    /// They do not describe the current presentation mode.
    @Default(PresentationCapabilities()) PresentationCapabilities capabilities,

    /// Orientation of the media currently being presented.
    ///
    /// Both fullscreen variants present differently per orientation — a
    /// portrait video filling a portrait phone, a landscape video taking over
    /// the screen, a portrait video letterboxed on a desktop monitor — so the
    /// orientation belongs to the presentation state rather than to one
    /// platform's driver. Drivers and hosts read it to pick a layout strategy;
    /// nothing here decides that strategy for them.
    @Default(VideoOrientation.unknown) VideoOrientation orientation,

    /// Whether a presentation transition is currently
    /// running.
    @Default(false) bool transitioning,

    /// Whether the presentation subsystem is enabled.
    ///
    /// This represents application-level availability of
    /// presentation functionality.
    @Default(true) bool enabled,

    /// Whether presentation is currently available.
    ///
    /// This can become false when the presentation subsystem
    /// cannot currently perform presentation operations.
    ///
    /// Examples:
    ///
    /// - player has been disposed
    /// - required platform resource is unavailable
    /// - presentation lifecycle has ended
    @Default(true) bool available,

    /// Lifecycle generation.
    ///
    /// Used to distinguish newer presentation operations
    /// from stale asynchronous callbacks.
    ///
    /// The controller owns generation changes.
    ///
    /// The reducer uses generation to prevent an older
    /// asynchronous event from overwriting newer state.
    @Default(0) int generation,

    /// Last presentation error.
    ///
    /// A null value means that the current state does not
    /// contain a presentation error.
    String? error,
  }) = _PresentationState;

  const PresentationState._();

  /// Creates the initial presentation state.
  ///
  /// The player starts in normal presentation mode.
  factory PresentationState.initial() {
    return const PresentationState();
  }

  /// Whether fullscreen presentation is active.
  bool get isFullscreen => mode == PresentationMode.fullscreen;

  /// Whether picture-in-picture presentation is active.
  bool get isPip => mode == PresentationMode.pip;

  /// Whether floating presentation is active.
  bool get isFloating => mode == PresentationMode.floating;

  /// Whether normal presentation is active.
  bool get isNormal => mode == PresentationMode.normal;

  /// Whether a presentation transition is running.
  bool get isTransitioning => transitioning;

  /// Whether the state contains a presentation error.
  bool get hasError => error != null;

  /// Whether a target presentation mode exists.
  bool get hasTarget => targetMode != null;

  /// Whether the current presentation mode is supported
  /// by the current environment.
  bool get isSupported => capabilities.supports(mode);

  /// Whether a new presentation request can currently
  /// be accepted.
  ///
  /// A request cannot be accepted when:
  ///
  /// - presentation is disabled
  /// - presentation is unavailable
  /// - another transition is running
  /// - the current state contains an error
  bool get canRequestChange => enabled && available && !transitioning && !hasError;

  /// Creates a state representing a pending transition.
  ///
  /// The current [mode] is intentionally preserved.
  ///
  /// Only [targetMode] and transition status change.
  PresentationState transitioningTo(PresentationMode target) {
    return copyWith(targetMode: target, transitioning: true, error: null);
  }

  /// Creates a state representing a successfully
  /// completed transition.
  ///
  /// The new mode becomes the current active mode and
  /// the pending target is cleared.
  PresentationState completed(PresentationMode newMode) {
    return copyWith(mode: newMode, targetMode: null, transitioning: false, error: null);
  }

  /// Creates a state representing a failed transition.
  ///
  /// The current active mode is preserved because the
  /// requested transition did not complete successfully.
  PresentationState failed(String message) {
    return copyWith(targetMode: null, transitioning: false, error: message);
  }
}
