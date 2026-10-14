/// Defines shared constants used by the media player core.
///
/// This class contains stable defaults, limits, and timing values used
/// across player modules. Runtime configuration should normally be exposed
/// through the corresponding configuration or policy classes rather than
/// modifying these constants.
abstract final class PlayerConstants {
  /// Default player volume.
  static const double defaultVolume = 1;

  /// Minimum supported volume.
  static const double minVolume = 0;

  /// Maximum supported volume.
  static const double maxVolume = 1;

  /// Default playback rate.
  static const double defaultPlaybackRate = 1;

  /// Minimum supported playback rate.
  static const double minPlaybackRate = 0.25;

  /// Maximum supported playback rate.
  static const double maxPlaybackRate = 4;

  /// Default video width used when actual dimensions are unavailable.
  static const int defaultVideoWidth = 1920;

  /// Default video height used when actual dimensions are unavailable.
  static const int defaultVideoHeight = 1080;

  /// Minimum accepted video width.
  static const int minVideoWidth = 1;

  /// Minimum accepted video height.
  static const int minVideoHeight = 1;

  /// Maximum accepted video width.
  static const int maxVideoWidth = 7680;

  /// Maximum accepted video height.
  static const int maxVideoHeight = 4320;

  /// Default seek tolerance.
  static const Duration defaultSeekTolerance = Duration(milliseconds: 100);

  /// Maximum time allowed for player initialization.
  static const Duration initializationTimeout = Duration(seconds: 15);

  /// Maximum time allowed for opening a source.
  static const Duration openTimeout = Duration(seconds: 18);

  /// Maximum time allowed for preparing a source.
  static const Duration prepareTimeout = Duration(seconds: 15);

  /// Maximum time allowed for stopping playback.
  static const Duration stopTimeout = Duration(seconds: 5);

  /// Maximum time allowed for player disposal.
  static const Duration disposeTimeout = Duration(seconds: 5);

  /// Maximum time allowed for a recovery attempt.
  static const Duration recoveryTimeout = Duration(seconds: 12);

  /// Maximum time allowed for a fallback attempt.
  static const Duration fallbackTimeout = Duration(seconds: 15);

  /// Minimum buffering threshold before playback may continue.
  static const Duration bufferingThreshold = Duration(milliseconds: 250);

  /// Default playback progress update interval.
  static const Duration progressInterval = Duration(milliseconds: 250);

  /// Default metrics collection interval.
  static const Duration metricsInterval = Duration(seconds: 1);

  /// Debounce interval used for video geometry changes.
  ///
  /// This is intentionally aligned with the player core's geometry
  /// stabilization strategy to avoid excessive renderer/layout updates.
  static const Duration geometryDebounce = Duration(milliseconds: 180);

  /// Maximum number of recovery attempts allowed by default.
  static const int maxRecoveryAttempts = 3;

  /// Maximum number of fallback attempts allowed by default.
  static const int maxFallbackAttempts = 3;

  /// Maximum number of generic retries allowed by default.
  static const int maxRetries = 3;

  /// Default delay between retry attempts.
  static const Duration retryDelay = Duration(seconds: 1);

  /// Default maximum number of players retained by a pool.
  static const int defaultPoolCapacity = 4;

  /// Default maximum number of simultaneous preload operations.
  static const int defaultPreloadCapacity = 2;

  /// Default network connection timeout.
  static const Duration networkConnectTimeout = Duration(seconds: 10);

  /// Default network receive timeout.
  static const Duration networkReceiveTimeout = Duration(seconds: 15);

  /// Default network send timeout.
  static const Duration networkSendTimeout = Duration(seconds: 15);

  /// Maximum time allowed for source inspection.
  static const Duration sourceInspectionTimeout = Duration(seconds: 10);

  /// Maximum number of metadata entries retained in lightweight snapshots.
  static const int maxMetadataEntries = 100;

  /// Maximum number of source lines retained by source inspection.
  static const int maxSourceLines = 100;

  /// Maximum number of quality options exposed by default.
  static const int maxQualityOptions = 50;

  /// Default cache size in bytes.
  static const int defaultCacheSizeBytes = 256 * 1024 * 1024;

  /// Maximum default recording duration.
  static const Duration maxRecordingDuration = Duration(hours: 12);

  /// Returns whether [value] is a valid volume.
  static bool isValidVolume(double value) {
    return value >= minVolume && value <= maxVolume;
  }

  /// Returns whether [value] is a valid playback rate.
  static bool isValidPlaybackRate(double value) {
    return value >= minPlaybackRate && value <= maxPlaybackRate;
  }

  /// Returns whether [value] is a valid video width.
  static bool isValidVideoWidth(int value) {
    return value >= minVideoWidth && value <= maxVideoWidth;
  }

  /// Returns whether [value] is a valid video height.
  static bool isValidVideoHeight(int value) {
    return value >= minVideoHeight && value <= maxVideoHeight;
  }

  /// Returns whether the supplied video dimensions are valid.
  static bool isValidVideoDimensions(int width, int height) {
    return isValidVideoWidth(width) && isValidVideoHeight(height);
  }

  /// Clamps [value] to the supported volume range.
  static double clampVolume(double value) {
    return value.clamp(minVolume, maxVolume);
  }

  /// Clamps [value] to the supported playback-rate range.
  static double clampPlaybackRate(double value) {
    return value.clamp(minPlaybackRate, maxPlaybackRate);
  }

  /// Returns the default video aspect ratio.
  static double get defaultVideoAspectRatio {
    return defaultVideoWidth / defaultVideoHeight;
  }
}
