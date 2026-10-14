import 'package:equatable/equatable.dart';

/// Reason that caused a fallback operation.
///
/// A fallback reason is descriptive metadata. It does not decide which
/// fallback strategy should be used.
sealed class FallbackReason extends Equatable {
  /// Creates a fallback reason.
  const FallbackReason();

  /// The reason could not be determined.
  const factory FallbackReason.unknown() = FallbackReasonUnknown;

  /// Fallback was triggered because the backend could not play the source.
  const factory FallbackReason.backend() = FallbackReasonBackend;

  /// Fallback was triggered to move to a different delivery line.
  const factory FallbackReason.line() = FallbackReasonLine;

  /// Fallback was triggered to change the media quality.
  const factory FallbackReason.quality() = FallbackReasonQuality;

  /// Fallback was triggered because of network degradation.
  const factory FallbackReason.network() = FallbackReasonNetwork;

  /// Fallback was triggered because the decoder could not handle the stream.
  const factory FallbackReason.decoder() = FallbackReasonDecoder;

  /// Fallback was triggered because the renderer failed.
  const factory FallbackReason.renderer() = FallbackReasonRenderer;

  /// Fallback was triggered because an operation timed out.
  const factory FallbackReason.timeout() = FallbackReasonTimeout;

  /// Whether this is the unknown reason.
  bool get isUnknown => this is FallbackReasonUnknown;

  /// Whether this is the backend reason.
  bool get isBackend => this is FallbackReasonBackend;

  /// Whether this is the line reason.
  bool get isLine => this is FallbackReasonLine;

  /// Whether this is the quality reason.
  bool get isQuality => this is FallbackReasonQuality;

  /// Whether this is the network reason.
  bool get isNetwork => this is FallbackReasonNetwork;

  /// Whether this is the decoder reason.
  bool get isDecoder => this is FallbackReasonDecoder;

  /// Whether this is the renderer reason.
  bool get isRenderer => this is FallbackReasonRenderer;

  /// Whether this is the timeout reason.
  bool get isTimeout => this is FallbackReasonTimeout;

  @override
  List<Object?> get props => <Object?>[];
}

/// Unknown fallback reason.
final class FallbackReasonUnknown extends FallbackReason {
  /// Creates the unknown fallback reason.
  const FallbackReasonUnknown();

  @override
  String toString() => 'unknown';
}

/// Backend fallback.
final class FallbackReasonBackend extends FallbackReason {
  /// Creates the backend fallback reason.
  const FallbackReasonBackend();

  @override
  String toString() => 'backend';
}

/// Line fallback.
final class FallbackReasonLine extends FallbackReason {
  /// Creates the line fallback reason.
  const FallbackReasonLine();

  @override
  String toString() => 'line';
}

/// Quality fallback.
final class FallbackReasonQuality extends FallbackReason {
  /// Creates the quality fallback reason.
  const FallbackReasonQuality();

  @override
  String toString() => 'quality';
}

/// Network fallback.
final class FallbackReasonNetwork extends FallbackReason {
  /// Creates the network fallback reason.
  const FallbackReasonNetwork();

  @override
  String toString() => 'network';
}

/// Decoder fallback.
final class FallbackReasonDecoder extends FallbackReason {
  /// Creates the decoder fallback reason.
  const FallbackReasonDecoder();

  @override
  String toString() => 'decoder';
}

/// Renderer fallback.
final class FallbackReasonRenderer extends FallbackReason {
  /// Creates the renderer fallback reason.
  const FallbackReasonRenderer();

  @override
  String toString() => 'renderer';
}

/// Timeout fallback.
final class FallbackReasonTimeout extends FallbackReason {
  /// Creates the timeout fallback reason.
  const FallbackReasonTimeout();

  @override
  String toString() => 'timeout';
}
