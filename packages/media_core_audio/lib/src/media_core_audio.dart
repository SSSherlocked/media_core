import 'package:media_core_mediasession/media_core_mediasession.dart';

/// Audio capability driver for the media_core kernel.
///
/// The implementation lives in `media_core_mediasession`, where it belongs: the
/// media surfaces (notification, lock screen, SMTC, MPRIS) and audio focus are
/// the same for a video player, and keeping them there means a video host gets
/// them without depending on the music module. This class is the module's
/// historical name for the same driver, kept so music hosts and the example
/// keep compiling:
///
/// ```dart
/// final audio = MediaCoreAudio();
/// await audio.initialize();
/// kernel.attachAudio(audio);
/// ```
///
/// New hosts — music or video — can use [MediaSessionDriver] directly, with
/// [MediaSessionConfig.video] for a player that has no queue.
final class MediaCoreAudio extends MediaSessionDriver {
  /// Creates the driver.
  MediaCoreAudio({super.config, super.sessionConfiguration, super.artUriResolver});
}
