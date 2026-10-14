import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/media_core.dart';

import 'package:media_core_better_player/media_core_better_player.dart';

/// The capability truth of the BetterPlayer adapter, pinned here because
/// the design-level answer ("ExoPlayer merges natively, so declare
/// `native`") is true of the engine and false of the surface this
/// adapter can actually reach: `BetterPlayerDataSource` takes one URI.
///
/// A `native` claim here routes composite sources past every backend
/// that *could* take two inputs and then plays them video-only, which
/// is the exact silent failure the planner layer exists to make loud.
/// If a merge data source is ever added to the plugin surface, update
/// this test at the same time the capability changes, not after.
void main() {
  group('BetterPlayer composite capability', () {
    test('does not advertise composite support it cannot honor', () {
      expect(
        BetterPlayerAdapter.defaultCapabilities.supportsComposite,
        isFalse,
        reason:
            'a single-URI BetterPlayerDataSource cannot consume a '
            'CompositeMediaSource without dropping its audio',
      );
    });
  });

  group('planning a DASH pair against the real adapters', () {
    final pair = CompositeMediaSource(
      videoTracks: [MediaTrack(uri: Uri.parse('https://example.com/v.m4s'), kind: MediaTrackType.video)],
      audioTracks: [MediaTrack(uri: Uri.parse('https://example.com/a.m4s'), kind: MediaTrackType.audio)],
    );

    test('refuses loudly rather than playing the pair video-only', () {
      const planner = DefaultMediaSourcePlanner();

      final plan = planner.plan(pair, BetterPlayerAdapter.defaultCapabilities);

      expect(plan, isA<UnsupportedPlan>());
    });

    test('the selector prefers an external-audio backend over this one', () {
      // media_kit declares externalAudio and actually mounts the extra
      // essence; BetterPlayer declares none. A DASH pair must not win
      // on a bigger number that nothing behind it can honor.
      final registry = PlayerAdapterRegistry()
        ..register(
          PlayerAdapterRegistration(
            id: 'better_player',
            factory: _NullFactory(),
            capabilities: BetterPlayerAdapter.defaultCapabilities,
          ),
        )
        ..register(
          PlayerAdapterRegistration(
            id: 'media_kit',
            factory: _NullFactory(),
            capabilities: const PlayerAdapterCapabilities(
              supportedProtocols: {'https'},
              supportedFormats: {'m4s', 'mp4'},
              compositeSupport: CompositeSupport.externalAudio,
            ),
          ),
        );

      final selected = PlayerAdapterSelector(registry).requireMedia(pair);

      expect(selected.id, 'media_kit');
    });
  });
}

class _NullFactory implements PlayerAdapterFactory {
  @override
  PlayerAdapter create(String id) => throw UnsupportedError('selection-only factory');

  @override
  bool supports(String id) => true;
}
