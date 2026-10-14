/// The transport state a render device reports for the current item.
///
/// Named after the DLNA `TransportState` vocabulary because that is
/// the only protocol today whose eventing distinguishes
/// [transitioning]; a backend with fewer states maps onto this enum
/// rather than inventing its own, so a controller's UI code never
/// branches per protocol.
enum CastTransportState {
  /// The renderer holds no media.
  noMedia,

  /// Media is loaded but not playing.
  stopped,

  /// Playing.
  playing,

  /// Paused.
  paused,

  /// Between states (a seek, a buffer stall on the receiver).
  transitioning,

  /// The state could not be read — a dropped device, an unreachable
  /// control URL.
  ///
  /// Distinct from [noMedia] on purpose: "the receiver says it holds
  /// nothing" and "the receiver is not answering" need different UI
  /// (a disabled play button versus a "device offline" affordance),
  /// and collapsing them would hide the second case inside the first.
  unknown,
}

/// Extension helpers for [CastTransportState].
extension CastTransportStateX on CastTransportState {
  /// Whether the receiver is producing output.
  bool get isPlaying => this == CastTransportState.playing;

  /// Whether playback can be resumed from here.
  bool get canResume => this == CastTransportState.paused || this == CastTransportState.stopped;

  /// Whether the state says anything about the device at all.
  bool get isKnown => this != CastTransportState.unknown;
}

/// Where the receiver's playhead is.
final class CastPosition {
  /// Creates a position report.
  const CastPosition({
    required this.position,
    required this.duration,
    this.transportState = CastTransportState.unknown,
  });

  /// No position information.
  const CastPosition.unknown()
    : position = Duration.zero,
      duration = Duration.zero,
      transportState = CastTransportState.unknown;

  /// Media time the receiver is playing.
  final Duration position;

  /// Duration the receiver believes the media has.
  final Duration duration;

  /// Transport state at the time of the report, when the protocol
  /// returns them together (DLNA's `GetPositionInfo` does).
  final CastTransportState transportState;
}
