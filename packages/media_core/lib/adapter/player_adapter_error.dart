import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_adapter_error.freezed.dart';

/// Error produced by a player adapter.
///
/// [PlayerAdapterError] represents backend-specific
/// playback failures in a normalized format.
///
/// Responsibilities:
///
/// - describe adapter failures
/// - classify recoverability
/// - provide debugging context
///
/// It does not:
///
/// - perform recovery
/// - retry operations
/// - write logs
///
/// Those belong to:
///
/// - RecoveryManager
/// - DiagnosticsManager
@freezed
abstract class PlayerAdapterError with _$PlayerAdapterError {
  /// Creates adapter error.
  const factory PlayerAdapterError({
    /// Error category.
    required PlayerAdapterErrorType type,

    /// Human readable message.
    required String message,

    /// Original backend error.
    Object? cause,

    /// Stack trace.
    StackTrace? stackTrace,

    /// Whether error can recover automatically.
    @Default(false) bool recoverable,

    /// Backend identifier.
    String? backend,

    /// Additional metadata.
    @Default({}) Map<String, Object?> metadata,
  }) = _PlayerAdapterError;

  /// Creates an unknown error.
  factory PlayerAdapterError.unknown(Object error) {
    return PlayerAdapterError(type: PlayerAdapterErrorType.unknown, message: error.toString(), cause: error);
  }
}

/// Adapter error categories.
enum PlayerAdapterErrorType {
  /// Unknown failure.
  unknown,

  /// Source cannot be opened.
  openFailed,

  /// Network connection failed.
  network,

  /// Unsupported media format.
  unsupportedFormat,

  /// Decoder initialization failed.
  decoder,

  /// Hardware acceleration failure.
  hardwareDecoder,

  /// Audio output failure.
  audio,

  /// Renderer failure.
  renderer,

  /// Invalid operation.
  invalidOperation,

  /// Backend internal failure.
  backend,
}

/// Extensions for adapter errors.
extension PlayerAdapterErrorExtension on PlayerAdapterError {
  /// Whether this error is related to network.
  bool get isNetwork {
    return type == PlayerAdapterErrorType.network;
  }

  /// Whether this error may require backend switch.
  bool get requiresFallback {
    return switch (type) {
      PlayerAdapterErrorType.unsupportedFormat ||
      PlayerAdapterErrorType.decoder ||
      PlayerAdapterErrorType.hardwareDecoder ||
      PlayerAdapterErrorType.backend => true,
      _ => false,
    };
  }

  /// Whether retry may succeed.
  bool get retryable {
    return recoverable || isNetwork;
  }
}
