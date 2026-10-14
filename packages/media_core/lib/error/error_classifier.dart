import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';

/// Classifies a concrete [PlayerErrorCode] into a broad
/// [PlayerErrorCategory].
///
/// This class contains only error classification logic.
///
/// It does not:
/// - decide whether an error should be retried;
/// - decide whether fallback should be used;
/// - decide whether recovery should be performed;
/// - format error messages;
/// - inspect runtime error context.
///
/// The result of this classifier is consumed by error policies.
final class ErrorClassifier {
  /// Classification rules are static, so instances exist only to satisfy
  /// dependency injection of a classifier.
  const ErrorClassifier();

  /// Classifies [code] into an error category.
  ///
  /// Unknown or custom error codes that are not explicitly recognized
  /// are classified as [PlayerErrorCategory.unknown].
  static PlayerErrorCategory classify(PlayerErrorCode code) {
    final value = code.value;

    // =========================================================================
    // General
    // =========================================================================

    if (value == PlayerErrorCode.unknown.value) {
      return PlayerErrorCategory.unknown;
    }

    if (value == PlayerErrorCode.invalidArgument.value) {
      return PlayerErrorCategory.invalidArgument;
    }

    if (value == PlayerErrorCode.unsupported.value) {
      return PlayerErrorCategory.unsupported;
    }

    if (value == PlayerErrorCode.invalidState.value || value == PlayerErrorCode.playbackInvalidState.value) {
      return PlayerErrorCategory.state;
    }

    if (value == PlayerErrorCode.cancelled.value ||
        value == PlayerErrorCode.staleGeneration.value ||
        value == PlayerErrorCode.superseded.value) {
      return PlayerErrorCategory.cancellation;
    }

    if (value == PlayerErrorCode.timeout.value || value == PlayerErrorCode.networkTimeout.value) {
      return PlayerErrorCategory.timeout;
    }

    if (value == PlayerErrorCode.internal.value) {
      return PlayerErrorCategory.internal;
    }

    // =========================================================================
    // Source
    // =========================================================================

    if (value == PlayerErrorCode.sourceMissing.value ||
        value == PlayerErrorCode.sourceInvalid.value ||
        value == PlayerErrorCode.sourceResolveFailed.value ||
        value == PlayerErrorCode.sourceInspectFailed.value ||
        value == PlayerErrorCode.sourceValidationFailed.value ||
        value == PlayerErrorCode.sourceProtocolUnsupported.value ||
        value == PlayerErrorCode.sourceMediaTypeUnsupported.value ||
        value == PlayerErrorCode.sourceFormatUnsupported.value) {
      return PlayerErrorCategory.source;
    }

    // =========================================================================
    // Network
    // =========================================================================

    if (value == PlayerErrorCode.network.value ||
        value == PlayerErrorCode.networkUnavailable.value ||
        value == PlayerErrorCode.networkDnsFailed.value ||
        value == PlayerErrorCode.networkConnectionFailed.value ||
        value == PlayerErrorCode.networkConnectionRefused.value ||
        value == PlayerErrorCode.networkAborted.value) {
      return PlayerErrorCategory.network;
    }

    // =========================================================================
    // HTTP
    // =========================================================================

    if (value == PlayerErrorCode.httpError.value) {
      return PlayerErrorCategory.http;
    }

    // =========================================================================
    // Authentication
    // =========================================================================

    if (value == PlayerErrorCode.authenticationRequired.value ||
        value == PlayerErrorCode.authenticationFailed.value ||
        value == PlayerErrorCode.authorizationFailed.value) {
      return PlayerErrorCategory.authentication;
    }

    // =========================================================================
    // Security / TLS
    // =========================================================================

    if (value == PlayerErrorCode.tlsError.value) {
      return PlayerErrorCategory.security;
    }

    // =========================================================================
    // Adapter
    // =========================================================================

    if (value == PlayerErrorCode.adapterUnavailable.value ||
        value == PlayerErrorCode.adapterUnsupported.value ||
        value == PlayerErrorCode.adapterInitializationFailed.value ||
        value == PlayerErrorCode.adapterDisposed.value) {
      return PlayerErrorCategory.adapter;
    }

    // =========================================================================
    // Backend
    // =========================================================================

    if (value == PlayerErrorCode.backendUnavailable.value ||
        value == PlayerErrorCode.backendInitializationFailed.value ||
        value == PlayerErrorCode.backendOpenFailed.value ||
        value == PlayerErrorCode.backendPlayFailed.value ||
        value == PlayerErrorCode.backendPauseFailed.value ||
        value == PlayerErrorCode.backendStopFailed.value ||
        value == PlayerErrorCode.backendSeekFailed.value ||
        value == PlayerErrorCode.backendFatal.value) {
      return PlayerErrorCategory.backend;
    }

    // =========================================================================
    // Playback
    // =========================================================================

    if (value == PlayerErrorCode.playbackFailed.value ||
        value == PlayerErrorCode.unexpectedStop.value ||
        value == PlayerErrorCode.invalidSeekPosition.value ||
        value == PlayerErrorCode.invalidPlaybackRate.value ||
        value == PlayerErrorCode.invalidVolume.value) {
      return PlayerErrorCategory.playback;
    }

    // =========================================================================
    // Decoder
    // =========================================================================

    if (value == PlayerErrorCode.decoderError.value ||
        value == PlayerErrorCode.decoderUnavailable.value ||
        value == PlayerErrorCode.codecUnsupported.value) {
      return PlayerErrorCategory.decoder;
    }

    // =========================================================================
    // Demuxer
    // =========================================================================

    if (value == PlayerErrorCode.demuxerError.value) {
      return PlayerErrorCategory.demuxer;
    }

    // =========================================================================
    // Media
    // =========================================================================

    if (value == PlayerErrorCode.mediaCorrupted.value ||
        value == PlayerErrorCode.mediaMetadataInvalid.value ||
        value == PlayerErrorCode.noPlayableStream.value ||
        value == PlayerErrorCode.streamEndedUnexpectedly.value) {
      return PlayerErrorCategory.media;
    }

    // =========================================================================
    // Resource
    // =========================================================================

    if (value == PlayerErrorCode.resourceUnavailable.value || value == PlayerErrorCode.resourceLimitExceeded.value) {
      return PlayerErrorCategory.resource;
    }

    // =========================================================================
    // Memory
    // =========================================================================

    if (value == PlayerErrorCode.memoryPressure.value) {
      return PlayerErrorCategory.memory;
    }

    // =========================================================================
    // Thermal
    // =========================================================================

    if (value == PlayerErrorCode.thermalPressure.value) {
      return PlayerErrorCategory.thermal;
    }

    // =========================================================================
    // Bandwidth
    // =========================================================================

    if (value == PlayerErrorCode.insufficientBandwidth.value) {
      return PlayerErrorCategory.bandwidth;
    }

    // =========================================================================
    // Renderer
    // =========================================================================

    if (value == PlayerErrorCode.rendererInitializationFailed.value ||
        value == PlayerErrorCode.rendererSurfaceFailed.value ||
        value == PlayerErrorCode.rendererTextureFailed.value) {
      return PlayerErrorCategory.renderer;
    }

    // =========================================================================
    // Geometry
    // =========================================================================

    if (value == PlayerErrorCode.geometryInvalid.value) {
      return PlayerErrorCategory.geometry;
    }

    // =========================================================================
    // Presentation
    // =========================================================================

    if (value == PlayerErrorCode.presentationFailed.value ||
        value == PlayerErrorCode.pipFailed.value ||
        value == PlayerErrorCode.fullscreenFailed.value ||
        value == PlayerErrorCode.floatingFailed.value) {
      return PlayerErrorCategory.presentation;
    }

    // =========================================================================
    // Audio
    // =========================================================================

    if (value == PlayerErrorCode.audioInitializationFailed.value ||
        value == PlayerErrorCode.audioFocusFailed.value ||
        value == PlayerErrorCode.audioRouteFailed.value ||
        value == PlayerErrorCode.audioUnsupported.value) {
      return PlayerErrorCategory.audio;
    }

    // =========================================================================
    // Recording
    // =========================================================================

    if (value == PlayerErrorCode.recordingUnsupported.value ||
        value == PlayerErrorCode.recordingInitializationFailed.value ||
        value == PlayerErrorCode.recordingFailed.value ||
        value == PlayerErrorCode.recordingOutputInvalid.value ||
        value == PlayerErrorCode.recordingStorageUnavailable.value) {
      return PlayerErrorCategory.recording;
    }

    // =========================================================================
    // Cache
    // =========================================================================

    if (value == PlayerErrorCode.cacheError.value ||
        value == PlayerErrorCode.cacheStorageUnavailable.value ||
        value == PlayerErrorCode.cacheEntryInvalid.value ||
        value == PlayerErrorCode.cacheLimitExceeded.value) {
      return PlayerErrorCategory.cache;
    }

    // =========================================================================
    // Concurrency
    // =========================================================================

    if (value == PlayerErrorCode.concurrencyLimitExceeded.value || value == PlayerErrorCode.lockUnavailable.value) {
      return PlayerErrorCategory.concurrency;
    }

    // =========================================================================
    // Lifecycle
    // =========================================================================

    if (value == PlayerErrorCode.disposed.value ||
        value == PlayerErrorCode.lifecycleInactive.value ||
        value == PlayerErrorCode.lifecycleTransitionFailed.value) {
      return PlayerErrorCategory.lifecycle;
    }

    // =========================================================================
    // Fallback
    // =========================================================================

    if (value == PlayerErrorCode.fallbackUnavailable.value || value == PlayerErrorCode.fallbackSelectionFailed.value) {
      return PlayerErrorCategory.fallback;
    }

    // =========================================================================
    // Recovery
    // =========================================================================

    if (value == PlayerErrorCode.recoveryUnavailable.value ||
        value == PlayerErrorCode.recoveryFailed.value ||
        value == PlayerErrorCode.recoveryExhausted.value) {
      return PlayerErrorCategory.recovery;
    }

    return PlayerErrorCategory.unknown;
  }

  /// Returns whether [code] can be classified into a known built-in
  /// category.
  static bool isKnown(PlayerErrorCode code) {
    return classify(code) != PlayerErrorCategory.unknown;
  }

  /// Returns the category value for [code].
  ///
  /// This is useful when serializing classification information without
  /// exposing the category object itself.
  static String categoryValue(PlayerErrorCode code) {
    return classify(code).value;
  }

  /// Returns whether [code] belongs to the specified [category].
  static bool isCategory(PlayerErrorCode code, PlayerErrorCategory category) {
    return classify(code) == category;
  }

  /// Returns whether [code] represents an unsupported capability.
  static bool isUnsupported(PlayerErrorCode code) {
    return classify(code) == PlayerErrorCategory.unsupported;
  }

  /// Returns whether [code] represents a cancellation.
  static bool isCancellation(PlayerErrorCode code) {
    return classify(code) == PlayerErrorCategory.cancellation;
  }

  /// Returns whether [code] represents a network-related error.
  static bool isNetworkRelated(PlayerErrorCode code) {
    return classify(code).isNetworkRelated;
  }

  /// Returns whether [code] represents a media-related error.
  static bool isMediaRelated(PlayerErrorCode code) {
    return classify(code).isMediaRelated;
  }

  /// Returns whether [code] represents a playback-related error.
  static bool isPlaybackRelated(PlayerErrorCode code) {
    return classify(code).isPlaybackRelated;
  }

  /// Returns whether [code] represents a resource-related error.
  static bool isResourceRelated(PlayerErrorCode code) {
    return classify(code).isResourceRelated;
  }

  /// Returns whether [code] represents a presentation-related error.
  static bool isPresentationRelated(PlayerErrorCode code) {
    return classify(code).isPresentationRelated;
  }
}
