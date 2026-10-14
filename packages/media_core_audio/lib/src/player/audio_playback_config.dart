import 'package:media_core_audio/src/player/audio_playback_controller.dart' show AudioPlaybackController;
import 'package:media_core_audio/src/track/music_quality.dart';

/// Tuning for [AudioPlaybackController].
final class AudioPlaybackConfig {
  /// Creates a config.
  const AudioPlaybackConfig({
    this.loadTimeout = const Duration(seconds: 20),
    this.restartThreshold = const Duration(seconds: 5),
    this.prefetchNext = true,
    this.refreshSourceOnError = true,
    this.initialQuality = MusicQuality.auto,
  });

  /// How long a source may take to start playing before the controller
  /// re-resolves it.
  ///
  /// A music API can hand back a syntactically valid URL that never produces
  /// audio (expired signature, region block, dead CDN node). Without this the
  /// player would sit in "loading" forever, because none of those cases raise
  /// an engine error.
  final Duration loadTimeout;

  /// Position below which "previous" goes to the previous track instead of
  /// restarting the current one.
  final Duration restartThreshold;

  /// Whether the next queue entry's URL and lyric are warmed up while the
  /// current track plays.
  final bool prefetchNext;

  /// Whether a failed playback is retried once with a freshly resolved URL.
  final bool refreshSourceOnError;

  /// Quality requested when the caller does not name one.
  final MusicQuality initialQuality;
}

/// The music player: one queue, one engine handle, one state snapshot.
///
/// Built on the same kernel as every other media_core player, but with the
/// decisions a *music* player makes:
///
/// - one handle is created once and re-opened per track, instead of one player
///   per song (engine startup per track is audible and burns a decoder);
/// - playback URLs are cached with their expiry and re-resolved rather than
///   replayed, because they are signed and short-lived;
/// - a failed or never-starting source is refreshed exactly once before the
///   failure is surfaced — one retry is what distinguishes a stale signature
///   from a genuinely unplayable track;
/// - the next track's URL and lyric are prefetched, so pressing "next" is not
///   followed by a stall;
/// - every action funnels through the queue, so "what plays next" has exactly
///   one answer ([PlayQueue]) and not one per call site.
///
