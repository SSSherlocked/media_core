import 'package:media_core/coordinator/lifecycle_coordinator.dart';
import 'package:media_core/coordinator/page_coordinator.dart';
import 'package:media_core/coordinator/playback_coordinator.dart';
import 'package:media_core/coordinator/player_audio_coordinator.dart';
import 'package:media_core/coordinator/player_coordinator.dart';
import 'package:media_core/coordinator/preload_coordinator.dart';
import 'package:media_core/coordinator/presentation_coordinator.dart';
import 'package:media_core/coordinator/resource_coordinator.dart';

/// Global coordinator for player runtime.
///
/// [GlobalPlayerCoordinator] is the root
/// coordination layer.
///
/// It combines all player related
/// coordinators.
///
/// It does not:
///
/// - create players
/// - execute backend commands
/// - store playback state
///
/// Those belong to:
///
/// - PlayerFactory
/// - PlayerAdapter
/// - PlaybackController
final class GlobalPlayerCoordinator {
  /// Creates global coordinator.
  GlobalPlayerCoordinator({
    PlayerCoordinator? player,
    PlaybackCoordinator? playback,
    PageCoordinator? page,
    PlayerAudioCoordinator? audio,
    ResourceCoordinator? resource,
    PreloadCoordinator? preload,
    LifecycleCoordinator? lifecycle,
    PresentationCoordinator? presentation,
  }) : player = player ?? PlayerCoordinator(),
       playback = playback ?? PlaybackCoordinator(),
       page = page ?? PageCoordinator(),
       audio = audio ?? PlayerAudioCoordinator(),
       resource = resource ?? ResourceCoordinator(),
       preload = preload ?? PreloadCoordinator(),
       lifecycle = lifecycle ?? LifecycleCoordinator(),
       presentation = presentation ?? PresentationCoordinator();

  /// PlayerIdentity identity and session coordination.
  final PlayerCoordinator player;

  /// Playback coordination.
  final PlaybackCoordinator playback;

  /// Page coordination.
  final PageCoordinator page;

  /// Audio coordination.
  final PlayerAudioCoordinator audio;

  /// Resource coordination.
  final ResourceCoordinator resource;

  /// Preload coordination.
  final PreloadCoordinator preload;

  /// Lifecycle coordination.
  final LifecycleCoordinator lifecycle;

  /// Presentation coordination.
  final PresentationCoordinator presentation;

  /// Initializes coordinator.
  Future<void> initialize() async {}

  /// Clears all runtime bindings.
  void clear() {
    player.clear();

    playback.clear();

    page.clear();

    audio.clear();

    resource.clear();

    preload.clear();

    lifecycle.clear();

    presentation.clear();
  }

  /// Disposes all coordinators.
  Future<void> dispose() async {
    await player.dispose();

    await playback.dispose();

    await page.dispose();

    await audio.dispose();

    await resource.dispose();

    await preload.dispose();

    await lifecycle.dispose();

    await presentation.dispose();
  }
}
