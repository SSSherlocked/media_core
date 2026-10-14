import 'package:media_core_native/src/method_channel_media_core_native.dart';
import 'package:media_core_native/src/native_platform_provider.dart' show NativePlatformProvider;
import 'package:media_core_native/src/platform_probe_report.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Platform side of the capability probe.
///
/// The interface exists so the probe is swappable: a host can install a fake in
/// tests (or its own implementation for a platform this package does not
/// cover) without touching anything above it.
///
/// Responsibilities:
///
/// - define how the platform is asked
/// - hold the active implementation
///
/// It does not:
///
/// - parse the answer (see [PlatformProbeReport])
/// - cache it (see [NativePlatformProvider])
abstract class MediaCoreNativePlatform extends PlatformInterface {
  /// Creates the platform interface.
  MediaCoreNativePlatform() : super(token: _token);

  static final Object _token = Object();

  static MediaCoreNativePlatform _instance = MethodChannelMediaCoreNative();

  /// The active implementation.
  static MediaCoreNativePlatform get instance => _instance;

  /// Installs another implementation.
  static set instance(MediaCoreNativePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Invokes [method] on the platform.
  ///
  /// Implementations must let exceptions through: the caller decides what a
  /// failure means, and every caller in this package treats one as "unknown".
  Future<T?> invoke<T>(String method, [Object? arguments]);

  /// Asks the platform what it can do.
  ///
  /// Never throws — a platform that cannot answer reports
  /// [PlatformProbeReport.unknown].
  Future<PlatformProbeReport> probe() => readPlatformReport(this);
}
