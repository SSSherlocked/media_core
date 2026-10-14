import 'package:example/demos/registry.dart';
import 'package:example/language.dart';
import 'package:example/ui/module_catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:media_core/media_core.dart';
import 'package:media_core_logging/media_core_logging.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart';
import 'package:media_core_mediasession/media_core_mediasession.dart';

/// media_core example: a runnable tour of the framework.
///
/// Two kinds of entry, on purpose:
///
/// - **可运行示例 / Runnable demos** — real pages that create a player and play
///   media (player, live, feed, music, presentation). These are what a
///   developer debugs against, and what shows the intended wiring end to end.
/// - **模块速览 / Module tour** — one page per module with a snippet and a
///   runnable function that prints what the module did. Useful for the
///   pure-logic modules (lyrics parsing, queue rules, source resolution) that
///   need no device and no network to demonstrate.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit loads libmpv; the example drives the vendored copy in this repo.
  MediaKitPlayerAdapter.ensureInitialized();

  // Framework logs are silent by default (a release build prints nothing).
  // The example turns them on so a developer can watch what the framework
  // decides while pressing buttons.
  MediaCoreLog.level = LogLevel.debug;

  // System media surfaces, enabled once for the whole app: every player this
  // example creates afterwards — the player page, the feed, live, the styles
  // page, the music player — publishes to the notification / lock screen / SMTC
  // / MPRIS without any per-page wiring. The 'media-session' page shows the
  // round trip; this line is the whole integration.
  //
  // Caught on purpose: a platform that cannot start audio_service (a missing
  // manifest entry on Android, an unsupported embedder) must not keep the demo
  // app from booting — the surfaces are simply off, and the probe/`media-session`
  // pages say so.
  try {
    await MediaSessionBootstrap.enable();
    MediaCoreLog.info(LogCategory.player, 'media session surfaces enabled');
  } on Object catch (error) {
    MediaCoreLog.warning(
      LogCategory.player,
      'media session surfaces unavailable',
      fields: <String, Object?>{'error': '$error'},
    );
  }

  runApp(const MediaCoreExampleApp());
}

/// The example application.
class MediaCoreExampleApp extends StatefulWidget {
  /// Creates the example application.
  const new({super.key});

  @override
  State<MediaCoreExampleApp> createState() => _MediaCoreExampleAppState();
}

final class _MediaCoreExampleAppState extends State<MediaCoreExampleApp> {
  final DemoLanguageNotifier _language = DemoLanguageNotifier(DemoLanguage.zh);

  @override
  void dispose() {
    _language.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DemoLanguageScope(
      notifier: _language,
      child: MaterialApp(
        title: 'media_core example',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        ),
        home: ModuleCatalogPage(entries: runnableDemos),
      ),
    );
  }
}
