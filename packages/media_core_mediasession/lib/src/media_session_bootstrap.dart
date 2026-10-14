import 'package:audio_session/audio_session.dart' as asession;
import 'package:media_core/media_core.dart';

import 'package:media_core_mediasession/src/media_session_config.dart';
import 'package:media_core_mediasession/src/media_session_driver.dart';

/// Turns the system media surfaces on for the whole app.
///
/// The kernel already hands the active player to whichever driver it has, and
/// switches players as playback moves between them — so a single driver serves
/// every player in the process, and the only thing a host has to do is say yes
/// once:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   // One line at app start: every player created afterwards — video, music,
///   // the feed, the focused cell of a multiview wall — publishes to the
///   // notification, the lock screen, SMTC or MPRIS.
///   await MediaSessionBootstrap.enable();
///
///   runApp(const MyApp());
/// }
/// ```
///
/// ### Why one driver for the whole process
///
/// The platform has exactly one media notification: one `AudioService` handler,
/// one SMTC session, one MPRIS name. Two drivers would fight over it — and
/// `AudioService.init` asserts in debug on a second call — so this class owns
/// the single instance and hands the same one to every kernel.
///
/// ### Why it is opt-in
///
/// Posting notifications and starting a foreground service is an app-level
/// decision: it needs manifest entries, an icon set and (on Android 13+) a
/// runtime permission. A library that did this behind a host's back would be
/// surprising at best, and a crash in the manifest-less case at worst. Nothing
/// happens until [enable] is called; after that everything is automatic.
///
/// Responsibilities:
///
/// - own the one driver
/// - install it into the kernel's process-wide slot
/// - hand it to a kernel that already exists, or to a host that wants its own
///
/// It does not:
///
/// - decide when a player becomes active (the kernel does)
/// - publish state (the driver does)
/// - request the Android notification permission (the app does; see the README)
final class MediaSessionBootstrap {
  const MediaSessionBootstrap._();

  static MediaSessionDriver? _current;
  static KernelAudioDriver Function()? _installedFactory;

  /// The driver in use, or null when the surfaces are off.
  static MediaSessionDriver? get current => _current;

  /// Whether the surfaces are on for this process.
  static bool get enabled => _current != null;

  /// Enables the system media surfaces.
  ///
  /// Idempotent: calling it again returns the driver already in use, so a page
  /// that wants to be sure does not have to check first.
  ///
  /// [driver] exists for a host that configured its own — it still owns
  /// initializing it — and for tests, which have no audio_service platform.
  ///
  /// Throws when the platform refuses to initialize (a missing `audio_service`
  /// manifest entry on Android, for instance). A host that wants the app to
  /// boot regardless should catch and log, which is what the example app does.
  static Future<MediaSessionDriver> enable({
    MediaSessionConfig config = const MediaSessionConfig(),
    MediaSessionDriver? driver,
    Uri? Function(PlayerSource source)? artUriResolver,
    asession.AudioSessionConfiguration? sessionConfiguration,
  }) async {
    final existing = _current;

    if (existing != null) {
      return existing;
    }

    final session =
        driver ??
        MediaSessionDriver(config: config, artUriResolver: artUriResolver, sessionConfiguration: sessionConfiguration);

    await session.initialize();

    install(session);

    return session;
  }

  /// Installs an already-initialized driver as the process-wide one.
  ///
  /// The kernel half of [enable], on its own: a host that performed the
  /// platform handshake itself — or wants a driver with a configuration
  /// [enable] cannot express — uses this, and so does a test, which has no
  /// platform to initialize.
  static void install(MediaSessionDriver session) {
    _current = session;

    MediaSessionDriver factory() => session;

    _installedFactory = factory;

    // Every kernel created from now on takes it; one created earlier attaches
    // it with `attachAudio`, which [attachTo] does.
    PlayerKernel.audioDriverFactory = factory;
  }

  /// Attaches the enabled driver to a kernel that predates [enable].
  ///
  /// Enables the surfaces first when they are off, so a host that forgot to
  /// call [enable] still gets a working surface instead of a silently missing
  /// one.
  static Future<MediaSessionDriver> attachTo(
    PlayerKernel kernel, {
    MediaSessionConfig config = const MediaSessionConfig(),
    MediaSessionDriver? driver,
    Uri? Function(PlayerSource source)? artUriResolver,
  }) async {
    final session = await enable(config: config, driver: driver, artUriResolver: artUriResolver);

    kernel.attachAudio(session);

    return session;
  }

  /// Turns the surfaces off and releases the driver.
  ///
  /// Publishes idle state and clears the media item first, so the notification
  /// and the platform's "now playing" entry go away instead of describing a
  /// player that no longer exists.
  static Future<void> disable() async {
    final session = _current;

    if (session == null) {
      return;
    }

    _current = null;

    // Clear the slot before disposing: a kernel created in between must not
    // pick up a driver that is going away. Compared by factory identity so a
    // host's own factory is never called just to check.
    if (identical(PlayerKernel.audioDriverFactory, _installedFactory)) {
      PlayerKernel.audioDriverFactory = null;
    }

    _installedFactory = null;

    await session.dispose();
  }

  @override
  String toString() {
    return 'MediaSessionBootstrap(enabled: $enabled, driver: $_current)';
  }
}
