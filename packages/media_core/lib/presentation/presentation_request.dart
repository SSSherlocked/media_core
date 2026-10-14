import 'package:clock/clock.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/presentation/presentation_mode.dart';

part 'presentation_request.freezed.dart';

/// Describes a presentation transition request.
///
/// A request represents an intention to change
/// presentation mode.
///
/// It does not:
///
/// - execute platform operations
/// - change window state
/// - call native APIs
///
/// The request is processed by:
///
/// - PresentationController
///
/// and executed by:
///
/// - PresentationAdapter
@freezed
abstract class PresentationRequest with _$PresentationRequest {
  /// Creates a presentation request from its fields.
  const factory PresentationRequest({
    /// Target presentation mode.
    ///
    /// Example:
    ///
    /// normal -> fullscreen
    ///
    @Default(PresentationMode.normal) PresentationMode mode,

    /// Whether transition animation
    /// should be used.
    ///
    /// The platform adapter decides
    /// whether animation is supported.
    @Default(true) bool animated,

    /// Whether this request is generated
    /// automatically.
    ///
    /// Examples:
    ///
    /// - device rotation
    /// - app lifecycle
    /// - playback policy
    @Default(false) bool automatic,

    /// Request source.
    ///
    /// Examples:
    ///
    /// - user
    /// - system
    /// - lifecycle
    /// - orientation
    String? source,

    /// Request generation.
    ///
    /// Used to match async
    /// platform callbacks.
    @Default(0) int generation,

    /// Unique request identifier.
    ///
    /// Useful for debugging
    /// and tracing lifecycle.
    String? requestId,

    /// Request creation timestamp.
    DateTime? createdAt,
  }) = _PresentationRequest;

  const PresentationRequest._();

  /// Creates normal mode request.
  factory PresentationRequest.normal({
    bool animated = true,

    bool automatic = false,

    String? source,

    int generation = 0,
  }) {
    return PresentationRequest(
      animated: animated,

      automatic: automatic,

      source: source,

      generation: generation,

      createdAt: clock.now(),
    );
  }

  /// Creates fullscreen request.
  factory PresentationRequest.fullscreen({
    bool animated = true,

    bool automatic = false,

    String? source,

    int generation = 0,
  }) {
    return PresentationRequest(
      mode: PresentationMode.fullscreen,

      animated: animated,

      automatic: automatic,

      source: source,

      generation: generation,

      createdAt: clock.now(),
    );
  }

  /// Creates window-level fullscreen request.
  ///
  /// Fills the application window without changing the window itself; see
  /// [PresentationMode.windowFullscreen].
  factory PresentationRequest.windowFullscreen({
    bool animated = true,

    bool automatic = false,

    String? source,

    int generation = 0,
  }) {
    return PresentationRequest(
      mode: PresentationMode.windowFullscreen,

      animated: animated,

      automatic: automatic,

      source: source,

      generation: generation,

      createdAt: clock.now(),
    );
  }

  /// Creates PiP request.
  factory PresentationRequest.pip({bool animated = true, bool automatic = false, String? source, int generation = 0}) {
    return PresentationRequest(
      mode: PresentationMode.pip,

      animated: animated,

      automatic: automatic,

      source: source,

      generation: generation,

      createdAt: clock.now(),
    );
  }

  /// Creates floating window request.
  factory PresentationRequest.floating({
    bool animated = true,

    bool automatic = false,

    String? source,

    int generation = 0,
  }) {
    return PresentationRequest(
      mode: PresentationMode.floating,

      animated: animated,

      automatic: automatic,

      source: source,

      generation: generation,

      createdAt: clock.now(),
    );
  }

  /// Whether request enters fullscreen.
  bool get isFullscreen => mode == PresentationMode.fullscreen;

  /// Whether request enters window-level fullscreen.
  bool get isWindowFullscreen => mode == PresentationMode.windowFullscreen;

  /// Whether request enters either fullscreen variant.
  bool get isAnyFullscreen => isFullscreen || isWindowFullscreen;

  /// Whether request enters PiP.
  bool get isPip => mode == PresentationMode.pip;

  /// Whether request enters floating.
  bool get isFloating => mode == PresentationMode.floating;

  /// Whether request restores normal mode.
  bool get isNormal => mode == PresentationMode.normal;

  /// Whether request changes presentation.
  bool get changesPresentation => mode != PresentationMode.normal;
}
