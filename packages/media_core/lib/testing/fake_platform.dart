import 'package:media_core/platform/platform_capabilities.dart';
import 'package:media_core/platform/platform_codec_capabilities.dart';
import 'package:media_core/platform/platform_device_profile.dart';
import 'package:media_core/platform/platform_info.dart';
import 'package:media_core/platform/platform_provider.dart';
import 'package:media_core/platform/platform_type.dart';

/// Scriptable [PlatformProvider] for tests.
final class FakePlatformProvider implements PlatformProvider {
  /// Creates a fake provider.
  FakePlatformProvider({
    PlatformType? type,
    PlatformInfo? info,
    PlatformCapabilities? capabilities,
    PlatformDeviceProfile? device,
    PlatformCodecCapabilities? codecs,
  }) : type = type ?? PlatformType.unknown,
       info = info ?? PlatformInfo(type: type ?? PlatformType.unknown, name: 'FakeDevice', version: '1.0.0'),
       capabilities = capabilities ?? const PlatformCapabilities(),
       device = device ?? PlatformDeviceProfile.unknown,
       codecs = codecs ?? PlatformCodecCapabilities.unknown;

  @override
  PlatformType type;

  @override
  PlatformInfo info;

  @override
  PlatformCapabilities capabilities;

  @override
  PlatformDeviceProfile device;

  @override
  PlatformCodecCapabilities codecs;

  bool _ready = false;

  @override
  bool get isReady => _ready;

  /// Marks the provider as ready.
  void markReady() => _ready = true;
}
