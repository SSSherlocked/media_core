/// Music playback for media_core: sources, queue, lyrics, desktop lyrics,
/// background playback and downloads — logic only, no UI and no theme.
///
/// The package has two halves that can be used independently:
///
/// **1. Capability (host-facing)** — bridges the kernel to the platform:
///
/// - `audio_service` — media notification, lock screen controls, background
///   playback (Android/iOS; Windows via audio_service_win)
/// - `audio_session` — audio focus, interruptions (calls, other apps),
///   becoming-noisy (headphones unplugged)
///
/// ```dart
/// final audio = MediaCoreAudio();
/// await audio.initialize();
/// kernel.attachAudio(audio);
/// ```
///
/// Platform permission and manifest checklist: `doc/permissions.md`.
///
/// **2. Music (player-facing)** — a player built for songs:
///
/// ```dart
/// final kernel = PlayerKernel()..registerBackend(MediaKitPlayerAdapter.defaultRegistration());
/// final registry = MusicSourceRegistry([myPlatformSource, LocalMusicSource(roots: ['/music'])]);
/// final player = AudioPlaybackController(kernel, registry: registry);
///
/// // Queue + play modes (list / list-loop / single-loop / random)
/// await player.setQueue(await myPlatformSource.search('周杰伦'));
/// player.setPlayMode(PlayMode.random);
///
/// // Lyrics (LRC with translation and word timing), cached and prefetching
/// final lyric = await player.loadCurrentLyric();
///
/// // Permissions the module needs beyond its own Dart code
/// final permissions = AudioPermissionService();
/// await permissions.request(AudioPermission.notifications); // Android 13+
/// await permissions.request(AudioPermission.mediaLibrary);  // local music only
///
/// // Desktop lyrics: shows a native overlay window
/// // (Windows / Android / macOS / Linux; iOS and web have no such window).
/// // show() obtains the overlay authorization itself and waits for it.
/// final overlay = DesktopLyricController(player);
/// if (await overlay.show()) {
///   // the window is on screen
/// }
///
/// // Background playback: notification/lock-screen/MPRIS with real metadata
/// final background = MusicBackgroundBinding(player, audio)..attach();
///
/// // Downloads (ffmpeg: HLS, signed CDNs, tags, codec choice)
/// final downloads = MusicDownloadQueue();
/// downloads.downloadTrack(track: track, source: source, directory: '/music');
/// ```
library;

import 'package:media_core_mediasession/media_core_mediasession.dart';

// Background playback binding for the music player.
export 'package:media_core_audio/src/background/music_background_binding.dart';
// Desktop lyrics: the logic plus the native windows it draws into
// (packages/media_core_audio/{windows,android,macos,linux}).
export 'package:media_core_audio/src/desktop_lyric/desktop_lyric_controller.dart';
export 'package:media_core_audio/src/desktop_lyric/desktop_lyric_state.dart';
export 'package:media_core_audio/src/desktop_lyric/desktop_lyric_transport.dart';
// Downloads.
export 'package:media_core_audio/src/download/music_download_queue.dart';
export 'package:media_core_audio/src/download/music_download_request.dart';
export 'package:media_core_audio/src/download/music_download_task.dart';
export 'package:media_core_audio/src/download/music_downloader.dart';
export 'package:media_core_audio/src/lyric/lrc_parser.dart';
// Lyrics.
export 'package:media_core_audio/src/lyric/lyric_document.dart';
export 'package:media_core_audio/src/lyric/lyric_line.dart';
export 'package:media_core_audio/src/lyric/lyric_loader.dart';
export 'package:media_core_audio/src/lyric/lyric_timeline.dart';
// Capability (background audio + audio session). The implementation lives in
// media_core_mediasession now — these names are this module's historical
// spelling of it, so music hosts and older call sites keep compiling.
export 'package:media_core_audio/src/media_core_audio.dart';
// Runtime permissions (notifications, media library, overlay).
export 'package:media_core_audio/src/permission/audio_permission.dart';
export 'package:media_core_audio/src/permission/audio_permission_service.dart';
// Music player.
export 'package:media_core_audio/src/player/audio_playback_config.dart';
export 'package:media_core_audio/src/player/audio_playback_controller.dart';
export 'package:media_core_audio/src/player/audio_playback_state.dart';
// Queue and play modes.
export 'package:media_core_audio/src/queue/play_mode.dart';
export 'package:media_core_audio/src/queue/play_queue.dart';
// Sources.
export 'package:media_core_audio/src/source/local_music_source.dart';
export 'package:media_core_audio/src/source/music_source.dart';
export 'package:media_core_audio/src/source/music_source_registry.dart';
// Track models.
export 'package:media_core_audio/src/track/music_quality.dart';
export 'package:media_core_audio/src/track/music_track.dart';
export 'package:media_core_audio/src/track/track_source.dart';
export 'package:media_core_mediasession/media_core_mediasession.dart';

// ============================================================================
// Names this module used before the media surfaces moved out
// ============================================================================

/// The music module's name for [MediaSessionConfig].
typedef AudioCapabilityConfig = MediaSessionConfig;

/// The music module's name for [MediaSessionHandler].
typedef MediaCoreAudioHandler = MediaSessionHandler;

/// The music module's name for [MediaSessionState].
typedef AudioHandlerState = MediaSessionState;

/// The music module's name for [MediaSessionItem].
typedef AudioHandlerMediaItem = MediaSessionItem;
