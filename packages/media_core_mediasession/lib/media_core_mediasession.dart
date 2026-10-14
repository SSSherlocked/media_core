/// System media surfaces for `media_core`.
///
/// One capability, four platforms: a media notification with controls on
/// Android, the lock screen and Control Center on iOS, SMTC on Windows and
/// MPRIS on Linux — plus audio focus, interruptions and pause-on-unplug. It
/// works for **any** player the kernel owns, video included; that is the reason
/// it is a package of its own rather than part of the music module.
///
/// The one thing a host has to do is say yes, once, at app start — after that
/// every player is published automatically:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await MediaSessionBootstrap.enable();   // every kernel takes it from here
///   runApp(const MyApp());
/// }
/// ```
///
/// Or drive it explicitly, per kernel:
///
/// ```dart
/// final kernel = PlayerKernel();
///
/// final session = MediaSessionDriver(config: const MediaSessionConfig.video());
/// await session.initialize();          // once, early
/// kernel.attachAudio(session);         // the kernel hands over active players
///
/// // Tell the surfaces where artwork comes from, for a source that has none:
/// session.artUriResolver = (source) => thumbnailFor(source.uri);
///
/// final handle = await kernel.create(source: source, config: const PlayerConfig(autoPlay: true));
/// // The notification now shows the title, play/pause, ±10s and stop, and the
/// // buttons drive this handle.
/// ```
///
/// What the host still owns (a library cannot declare these for the app):
///
/// - Android: `AudioServiceActivity`, the `AudioService` service and
///   `MediaButtonReceiver` entries in the manifest, plus the
///   `POST_NOTIFICATIONS` permission on API 33+ (`media_core_audio`'s
///   `AudioPermissionService` asks for exactly that one, or use your own
///   permission plugin);
/// - iOS: the `audio` background mode in `Info.plist`, otherwise the lock
///   screen entry disappears when the app is suspended;
/// - drawables for the control icons named in [MediaSessionConfig].
library;

import 'package:media_core_mediasession/src/media_session_config.dart' show MediaSessionConfig;

// The handler extends `BaseAudioHandler` and its streams carry these types, so
// a host that observes the surfaces would otherwise have to depend on
// audio_service itself just to name them.
export 'package:audio_service/audio_service.dart'
    show AudioProcessingState, BaseAudioHandler, MediaAction, MediaControl, MediaItem, PlaybackState;

export 'package:media_core_mediasession/src/media_session_bootstrap.dart';
export 'package:media_core_mediasession/src/media_session_config.dart';
export 'package:media_core_mediasession/src/media_session_driver.dart';
export 'package:media_core_mediasession/src/media_session_handler.dart';
