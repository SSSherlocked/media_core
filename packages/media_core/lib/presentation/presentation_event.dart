import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/presentation/presentation_mode.dart';

part 'presentation_event.freezed.dart';

/// Represents an event emitted by the presentation subsystem.
///
/// Events are immutable descriptions of something that happened.
///
/// Events do not:
///
/// - execute native APIs
/// - modify presentation state
/// - perform transitions
/// - manage lifecycle
///
/// They are consumed by:
///
/// - PresentationController
/// - PresentationReducer
///
/// Platform adapters create events when:
///
/// - a transition starts
/// - a transition completes
/// - a transition fails
/// - the system changes presentation externally
///
/// Flow:
///
/// ```text
/// PresentationRequest
///          │
///          ▼
/// PresentationController
///          │
///          ▼
/// PresentationAdapter
///          │
///          ▼
/// PresentationEvent
///          │
///          ▼
/// PresentationReducer
///          │
///          ▼
/// PresentationState
/// ```
@freezed
sealed class PresentationEvent with _$PresentationEvent {
  /// Platform transition started.
  ///
  /// Example:
  ///
  /// User requests fullscreen.
  ///
  /// Android starts fullscreen animation.
  ///
  /// Adapter emits:
  ///
  /// PresentationStarted(fullscreen)
  ///
  const factory PresentationEvent.started({
    /// Target presentation mode.
    required PresentationMode mode,

    /// Request lifecycle generation.
    ///
    /// Used to ignore stale callbacks.
    @Default(0) int generation,

    /// Original request id.
    ///
    /// Useful when multiple async
    /// operations exist.
    String? requestId,

    /// Event source.
    ///
    /// Examples:
    ///
    /// - android
    /// - ios
    /// - windows
    /// - user
    /// - lifecycle
    String? source,
  }) = PresentationStarted;

  /// Platform transition completed.
  ///
  /// The platform has successfully
  /// reached the requested mode.
  const factory PresentationEvent.completed({
    /// Actual active presentation mode.
    required PresentationMode mode,

    /// Request generation.
    @Default(0) int generation,

    /// Request identifier.
    String? requestId,

    /// Event source.
    String? source,
  }) = PresentationCompleted;

  /// Platform transition failed.
  ///
  /// Reducer will clear transition state
  /// and expose error information.
  const factory PresentationEvent.failed({
    /// Error message.
    required String error,

    /// Target mode if known.
    PresentationMode? mode,

    /// Request generation.
    @Default(0) int generation,

    /// Request identifier.
    String? requestId,

    /// Event source.
    String? source,
  }) = PresentationFailed;

  /// Platform reported external state change.
  ///
  /// Examples:
  ///
  /// - Android PiP entered by system
  /// - Android PiP closed by user
  /// - desktop window moved externally
  /// - system fullscreen changed
  const factory PresentationEvent.changed({
    /// Actual mode reported by platform.
    required PresentationMode mode,

    /// Event generation.
    @Default(0) int generation,

    /// Request identifier.
    String? requestId,

    /// Event source.
    String? source,
  }) = PresentationChanged;

  /// Presentation subsystem disposed.
  ///
  /// This is lifecycle event.
  ///
  /// It does not represent a mode change.
  const factory PresentationEvent.disposed({
    /// Lifecycle generation.
    @Default(0) int generation,

    /// Request identifier.
    String? requestId,

    /// Event source.
    String? source,
  }) = PresentationDisposed;

  const PresentationEvent._();

  /// Whether event contains an error.
  bool get hasError => maybeMap(failed: (_) => true, orElse: () => false);

  /// Error message.
  ///
  /// Returns null for non-failed events.
  String? get error => maybeMap(failed: (event) => event.error, orElse: () => null);

  /// Whether event contains a presentation mode.
  bool get hasMode => maybeMap(
    started: (_) => true,
    completed: (_) => true,
    failed: (event) => event.mode != null,
    changed: (_) => true,
    disposed: (_) => false,
    orElse: () => false,
  );

  /// Presentation mode carried by event.
  PresentationMode? get mode => maybeMap(
    started: (event) => event.mode,
    completed: (event) => event.mode,
    failed: (event) => event.mode,
    changed: (event) => event.mode,
    disposed: (_) => null,
    orElse: () => null,
  );

  /// Event generation.
  ///
  /// Used to discard stale async callbacks.
  @override
  int get generation => map(
    started: (event) => event.generation,
    completed: (event) => event.generation,
    failed: (event) => event.generation,
    changed: (event) => event.generation,
    disposed: (event) => event.generation,
  );

  /// Optional request identifier.
  @override
  String? get requestId => map(
    started: (event) => event.requestId,
    completed: (event) => event.requestId,
    failed: (event) => event.requestId,
    changed: (event) => event.requestId,
    disposed: (event) => event.requestId,
  );

  /// Event source.
  @override
  String? get source => map(
    started: (event) => event.source,
    completed: (event) => event.source,
    failed: (event) => event.source,
    changed: (event) => event.source,
    disposed: (event) => event.source,
  );
}
