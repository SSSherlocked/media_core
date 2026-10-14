import 'package:example/demos/module_demo.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_native/media_core_native.dart';

/// What the platform probe answers on the device running this app.
///
/// The demo prints the report rather than drawing it: the numbers come from a
/// method channel, the interesting part is which of them are present at all,
/// and a printed table is the medium that shows "unreported" as clearly as it
/// shows a value. Run it on a phone, a TV box and a desktop and the three
/// reports explain why the same stream plays differently on each.
class ProbeDemo extends ModuleDemo {
  /// Creates the demo.
  const new();

  @override
  String get id => 'platform-probe';

  @override
  ModuleCategory get category => ModuleCategory.capability;

  @override
  String get nameZh => '平台能力探针';

  @override
  String get nameEn => 'Platform capability probe';

  @override
  String get purposeZh =>
      '主包知道后端支持什么，只有平台知道设备能做什么。探针一次问清编解码硬解、分辨率上限、内存与核数、系统特性，answers 通过 kernel.attachPlatformProvider 进入每个 session 与适配器，解码策略据此决定直接软解还是尝试硬解。';

  @override
  String get purposeEn =>
      'The core knows what a backend supports; only the platform knows what the device can do. One probe answers hardware decoding per codec, resolution ceilings, memory, cores and system features; kernel.attachPlatformProvider carries it into every session and adapter, where the decode policy decides between trying hardware and going straight to software.';

  @override
  List<String> get pointsZh => const <String>[
    'canDecodeInHardware 返回 bool? —— null 是"平台没说过"，false 才是"平台说不行"',
    '缺失字段 / 缺失整段 / 调用失败都读作未知，未知设备不会被降级',
    'Linux 刻意不上报编解码矩阵（需要 libva），平台级答案仍走 capabilities.hardwareDecode',
    'backgroundPlayback 看的是应用声明（Android 清单 / iOS UIBackgroundModes），不是平台能力',
  ];

  @override
  List<String> get pointsEn => const <String>[
    'canDecodeInHardware returns bool? — null means "not asked", false means the platform said no',
    'A missing field, a missing section and a failed call all read as unknown; an unknown device is never tuned down',
    'Linux deliberately reports no codec matrix (that needs libva); the platform-level answer still travels in capabilities.hardwareDecode',
    "backgroundPlayback reflects the app's declaration (Android manifest / iOS UIBackgroundModes), not the platform's ability",
  ];

  @override
  String get snippet => '''
final provider = await NativePlatformProvider.load();
kernel.attachPlatformProvider(provider);

// Every session and every adapter now carries facts:
handle.session.context.platform;      // capability flags, reported: true

// The question a decoder decision actually asks:
provider.canHardwareDecode(VideoCodec.hevc, width: 3840, height: 2160);
// true  → hardware exists (and no invented ceiling refuses it)
// false → the platform said no: mpv is told hwdec=no up front
// null  → nobody asked: the engine keeps its own fallback behaviour
''';

  @override
  Future<String> run() async {
    final buffer = StringBuffer();

    final provider = await NativePlatformProvider.load();

    buffer
      ..writeln('probe: ${provider.isReady ? 'reported by the platform' : 'no answer (unknown everywhere)'}')
      ..writeln('       $provider')
      ..writeln()
      ..writeln('info')
      ..writeln('  type         : ${provider.type.value}')
      ..writeln('  name         : ${_orUnknown(provider.info.name)}')
      ..writeln('  version      : ${_orUnknown(provider.info.version)}')
      ..writeln('  build        : ${_orUnknown(provider.info.buildNumber)}')
      ..writeln('  architecture : ${_orUnknown(provider.info.architecture)}')
      ..writeln('  device model : ${_orUnknown(provider.info.deviceModel)}')
      ..writeln('  emulator     : ${provider.info.isEmulator}')
      ..writeln();

    final capabilities = provider.capabilities;

    buffer
      ..writeln('capabilities (reported: ${capabilities.reported})')
      ..writeln('  hardware decode    : ${capabilities.hardwareDecode}')
      ..writeln('  software decode    : ${capabilities.softwareDecode}')
      ..writeln('  picture in picture : ${capabilities.pictureInPicture}')
      ..writeln('  background playback: ${capabilities.backgroundPlayback}')
      ..writeln('  external display   : ${capabilities.externalDisplay}')
      ..writeln('  fullscreen         : ${capabilities.fullscreen}')
      ..writeln();

    final device = provider.device;

    buffer
      ..writeln('device (reported: ${device.reported})')
      ..writeln('  cpu cores              : ${device.cpuCores}')
      ..writeln('  total ram (MB)         : ${device.totalRamMb ?? 'unknown'}')
      ..writeln('  low ram device         : ${device.lowRamDevice}')
      ..writeln('  64-bit ABI             : ${device.supports64BitAbi}')
      ..writeln('  low end (derived)      : ${device.isLowEnd}')
      ..writeln('  software decode threads: ${device.softwareDecodeThreads}')
      ..writeln()
      ..writeln('video codecs (reported: ${provider.codecs.reported})');

    if (provider.codecs.isEmpty) {
      // The honest shape of an unanswered codec section: every question below
      // stays unknown, and the engine keeps its own behaviour.
      buffer.writeln('  (none reported — every codec question below answers "unknown")');
    } else {
      for (final codec in VideoCodec.values) {
        final support = provider.codecs[codec];

        if (support == null) {
          continue;
        }

        final ceiling = support.hasSizeLimits
            ? 'up to ${support.maxWidth}x${support.maxHeight}'
            : 'no reported ceiling';

        buffer.writeln('  ${codec.name.padRight(6)}: ${support.hardware ? 'hardware' : 'software only'} ($ceiling)');
      }
    }

    buffer
      ..writeln()
      ..writeln('the questions a backend asks');

    for (final entry in <({String label, VideoCodec codec, int width, int height})>[
      (label: 'H.264 @1080p', codec: VideoCodec.h264, width: 1920, height: 1080),
      (label: 'H.264 @4K   ', codec: VideoCodec.h264, width: 3840, height: 2160),
      (label: 'HEVC  @1080p', codec: VideoCodec.hevc, width: 1920, height: 1080),
      (label: 'HEVC  @4K   ', codec: VideoCodec.hevc, width: 3840, height: 2160),
      (label: 'AV1   @1080p', codec: VideoCodec.av1, width: 1920, height: 1080),
    ]) {
      buffer.writeln(
        '  ${entry.label} → ${provider.canHardwareDecode(entry.codec, width: entry.width, height: entry.height)}',
      );
    }

    buffer
      ..writeln()
      ..writeln('null above means "not asked"; the decode policy keeps the engine\'s own behaviour there.')
      ..writeln('attach it once and every later player carries it:')
      ..writeln('  kernel.attachPlatformProvider(provider)  →  session.context.platform')
      ..writeln('                                           →  adapter context: device + codecs');

    return buffer.toString();
  }

  static String _orUnknown(String? value) {
    final trimmed = value?.trim();

    return (trimmed == null || trimmed.isEmpty) ? 'unknown' : trimmed;
  }
}
