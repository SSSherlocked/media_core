import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_core/adapter/player_adapter_config.dart';
import 'package:media_core/core/player_config.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/platform/platform_capabilities.dart';
import 'package:media_core/platform/platform_codec_capabilities.dart';
import 'package:media_core/platform/platform_device_profile.dart';

part 'player_adapter_context.freezed.dart';

/// Context provided when initializing a player adapter.
///
/// [PlayerAdapterContext] contains environment
/// information required by a playback backend.
///
/// Responsibilities:
///
/// - provide initialization dependencies
/// - provide player/session identity
/// - provide adapter options
///
/// It does not:
///
/// - manage playback state
/// - create adapters
/// - collect metrics
///
/// Those belong to:
///
/// - PlayerAdapterState
/// - PlayerAdapterFactory
/// - PlayerAdapterMetrics
@freezed
abstract class PlayerAdapterContext with _$PlayerAdapterContext {
  /// Creates adapter context.
  const factory PlayerAdapterContext({
    /// PlayerIdentity identifier.
    required PlayerId playerId,

    /// Playback session identifier.
    required SessionId sessionId,

    /// Adapter configuration.
    @Default(PlayerAdapterConfig()) PlayerAdapterConfig config,

    /// PlayerIdentity configuration.
    PlayerConfig? playerConfig,

    /// Backend specific options.
    @Default({}) Map<String, Object?> options,

    /// Capabilities reported by the running device.
    ///
    /// Filled from the platform probe the kernel was given; the defaults are
    /// what a host that attached no provider gets, and they report themselves
    /// as [PlatformCapabilities.reported] `false` so a backend can tell.
    @Default(PlatformCapabilities()) PlatformCapabilities platform,

    /// Device facts of the running device (cores, memory, ABI width).
    @Default(PlatformDeviceProfile.unknown) PlatformDeviceProfile device,

    /// What the device can decode, and in hardware or not.
    @Default(PlatformCodecCapabilities.unknown) PlatformCodecCapabilities codecs,

    /// Debug mode.
    @Default(false) bool debug,
  }) = _PlayerAdapterContext;

  /// Creates minimal context.
  factory PlayerAdapterContext.basic({required PlayerId playerId, required SessionId sessionId}) {
    return PlayerAdapterContext(playerId: playerId, sessionId: sessionId);
  }
}

/// Extensions for adapter context.
extension PlayerAdapterContextExtension on PlayerAdapterContext {
  /// Whether custom options exist.
  bool get hasOptions {
    return options.isNotEmpty;
  }

  /// Gets backend option.
  T? option<T>(String key) {
    final value = options[key];

    if (value is T) {
      return value;
    }

    return null;
  }

  /// Creates context with option.
  PlayerAdapterContext putOption(String key, Object? value) {
    return copyWith(options: {...options, key: value});
  }
}
