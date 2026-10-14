import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/adapter/composite_support.dart';
import 'package:media_core/adapter/player_adapter_base.dart';
import 'package:media_core/adapter/player_adapter_capabilities.dart';
import 'package:media_core/adapter/player_adapter_context.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/kernel/player_kernel.dart';
import 'package:media_core/source/media_source.dart';
import 'package:media_core/source/media_source_bridge.dart';
import 'package:media_core/source/media_track.dart';
import 'package:media_core/source/media_track_type.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/source/source_inspector_chain.dart';
import 'package:media_core/source/source_resolve_context.dart';
import 'package:media_core/source/source_resolved.dart';
import 'package:media_core/source/source_resolver.dart';
import 'package:media_core/source/source_resolver_chain.dart';
import 'package:media_core/source/source_service.dart';
import 'package:media_core/source/source_type.dart';
import 'package:media_core/testing/test_player_factory.dart';

MediaTrack _videoTrack(String url) => MediaTrack(uri: Uri.parse(url), kind: MediaTrackType.video);

CompositeMediaSource _bilibiliPair() => CompositeMediaSource(
  videoTracks: [_videoTrack('https://example.com/v.m4s')],
  audioTracks: [MediaTrack(uri: Uri.parse('https://example.com/a.m4s'), kind: MediaTrackType.audio)],
);

/// Minimal base-derived adapter used only to exercise the
/// composite-on-none rejection in [PlayerAdapterBase.open].
final class _GuardTestAdapter extends PlayerAdapterBase {
  _GuardTestAdapter({super.capabilities});

  int openCalls = 0;

  @override
  Future<void> onInitialize(PlayerAdapterContext context) async {}

  @override
  Future<void> onOpen(PlayerSource source) async {
    openCalls++;
  }

  @override
  Future<void> onPlay() async {}

  @override
  Future<void> onPause() async {}

  @override
  Future<void> onStop() async {}

  @override
  Future<void> onSeek(Duration position) async {}

  @override
  Future<void> onSetVolume(double volume) async {}

  @override
  Future<void> onSetRate(double rate) async {}

  @override
  Future<void> onClose() async {}

  @override
  Future<void> onDispose() async {}
}

/// Resolver that carries a freshly built PlayerSource — the exact
/// shape that used to drop the bridge metadata.
class _ReplacingResolver implements SourceResolver {
  @override
  bool supports(PlayerSource source) => true;

  @override
  Future<ResolvedSource> resolve(PlayerSource source, {SourceResolveContext? context}) async {
    return ResolvedSource(
      sourceId: source.id,
      uri: source.uri,
      source: PlayerSource(id: source.id, uri: source.uri, title: 'replaced'),
    );
  }
}

SourceService _serviceReplacing() => SourceService(
  resolverChain: SourceResolverChain(resolvers: [_ReplacingResolver()]),
  inspectorChain: SourceInspectorChain(),
);

void main() {
  group('MediaSourceBridge stable identity', () {
    test('two bridges of the same source produce the same SourceId', () {
      final pair = _bilibiliPair();

      expect(pair.toPlayerSource().id, pair.toPlayerSource().id);
    });

    test('changed primary URI changes the derived SourceId', () {
      final first = ProgressiveMediaSource(track: _videoTrack('https://example.com/a.mp4'));
      final second = ProgressiveMediaSource(track: _videoTrack('https://example.com/b.mp4'));

      expect(first.toPlayerSource().id, isNot(second.toPlayerSource().id));
    });

    test('explicit id still wins over the derived one', () {
      final bridged = _bilibiliPair().toPlayerSource(id: SourceId('mine'));

      expect(bridged.id.value, 'mine');
    });
  });

  group('MediaSourceBridge live declaration', () {
    test('a declared live source bridges as SourceType.live', () {
      final live = ProgressiveMediaSource(track: _videoTrack('https://example.com/index.m3u8'), live: true);

      final bridged = live.toPlayerSource();

      expect(bridged.type, SourceType.live);
      expect(bridged.isLive, isTrue);
    });

    test('a live composite keeps the declaration across the bridge', () {
      final pair = CompositeMediaSource(
        videoTracks: [_videoTrack('https://example.com/live_v.m4s')],
        audioTracks: [MediaTrack(uri: Uri.parse('https://example.com/live_a.m4s'), kind: MediaTrackType.audio)],
        live: true,
      );

      expect(pair.toPlayerSource().isLive, isTrue);
    });

    test('an HLS URL without the declaration stays on demand', () {
      // The scheme says nothing about liveness — only the provider does.
      // Inferring live from `.m3u8` would put every VOD HLS asset behind
      // the live guards, and inferring VOD from a missing duration would
      // put every live stream behind the seek bar.
      final vod = ProgressiveMediaSource(track: _videoTrack('https://example.com/index.m3u8'));

      final bridged = vod.toPlayerSource();

      expect(bridged.isLive, isFalse);
      expect(bridged.type, SourceType.remote);
    });
  });

  group('PlayerKernel bridge metadata across resolution', () {
    test('composite metadata survives a resolver that carries its own source', () async {
      final kernel = PlayerKernel(sourceService: _serviceReplacing())
        ..registerBackend(
          PlayerAdapterRegistration(
            id: 'fake',
            factory: TestPlayerFactory.fakeAdapterFactory(),
            capabilities: const PlayerAdapterCapabilities(supportedProtocols: {'https'}),
          ),
        );

      final bridged = _bilibiliPair().toPlayerSource();
      final handle = await kernel.create(source: bridged);

      final opened = handle.source;
      expect(opened, isNotNull);
      expect(opened!.title, 'replaced');
      expect(
        MediaSourceBridge.compositeFromPlayerSource(opened),
        isA<CompositeMediaSource>(),
        reason:
            'the resolver replaced the PlayerSource; the bridge '
            'entry must have been re-attached',
      );

      await kernel.release(handle.id);
      await kernel.dispose();
    });
  });

  group('PlayerAdapterBase.open composite guard', () {
    test('composite on a none backend is refused before onOpen runs', () async {
      final adapter = _GuardTestAdapter(capabilities: const PlayerAdapterCapabilities());
      await adapter.initialize(TestPlayerFactory.context());

      await expectLater(
        adapter.open(_bilibiliPair().toPlayerSource()),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            allOf(contains('compositeSupport: none'), contains('native or external-audio')),
          ),
        ),
      );
      expect(adapter.openCalls, 0);

      await adapter.dispose();
    });

    test('composite reaches onOpen when the backend declares support', () async {
      final adapter = _GuardTestAdapter(
        capabilities: const PlayerAdapterCapabilities(compositeSupport: CompositeSupport.native),
      );
      await adapter.initialize(TestPlayerFactory.context());

      await adapter.open(_bilibiliPair().toPlayerSource());

      expect(adapter.openCalls, 1);

      await adapter.dispose();
    });

    test('progressive and unbridged sources are never refused', () async {
      final adapter = _GuardTestAdapter(capabilities: const PlayerAdapterCapabilities());
      await adapter.initialize(TestPlayerFactory.context());

      await adapter.open(ProgressiveMediaSource(track: _videoTrack('https://example.com/v.mp4')).toPlayerSource());
      await adapter.open(PlayerSource(id: SourceId('plain'), uri: Uri.parse('https://example.com/x.mp4')));

      expect(adapter.openCalls, 2);

      await adapter.dispose();
    });
  });
}
