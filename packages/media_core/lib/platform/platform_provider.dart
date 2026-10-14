import 'package:media_core/platform/platform_capabilities.dart';
import 'package:media_core/platform/platform_codec_capabilities.dart';
import 'package:media_core/platform/platform_device_profile.dart';
import 'package:media_core/platform/platform_info.dart';
import 'package:media_core/platform/platform_type.dart';

/// Provides platform runtime information.
///
/// [PlatformProvider] is the abstraction layer
/// between media core and host platform.
///
/// Responsibilities:
///
/// - provide platform type
/// - provide platform information
/// - provide platform capabilities
///
/// It does not:
///
/// - access native APIs directly
/// - initialize player backend
///
/// Those belong to:
///
/// - PlatformInfo
/// - BackendFactory
abstract interface class PlatformProvider {
  /// Current platform type.
  PlatformType get type;

  /// Platform information.
  PlatformInfo get info;

  /// Platform capabilities.
  PlatformCapabilities get capabilities;

  /// Device facts (cores, memory, ABI width).
  ///
  /// Separate from [capabilities] because it answers a different question:
  /// capabilities say what can be done, this says how much room there is to do
  /// it in. Both are needed to pick a decoder.
  PlatformDeviceProfile get device;

  /// What the platform can decode, and in hardware or not.
  PlatformCodecCapabilities get codecs;

  /// Whether provider is ready.
  bool get isReady;
}
