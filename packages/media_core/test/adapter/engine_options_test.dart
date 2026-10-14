import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/adapter/engine_option.dart';
import 'package:media_core/adapter/player_adapter_registry.dart';
import 'package:media_core/event/player_event_bus.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/kernel/kernel_options.dart';
import 'package:media_core/kernel/player_handle.dart';
import 'package:media_core/source/player_source.dart';
import 'package:media_core/testing/fake_player_adapter.dart';
import 'package:media_core/testing/test_player_factory.dart';

PlayerSource _source(String id) => PlayerSource(id: SourceId(id), uri: Uri.parse('https://example.com/$id.flv'));

PlayerHandle _handle(FakePlayerAdapter adapter) {
  return PlayerHandle(
    player: TestPlayerFactory.player(1),
    adapter: adapter,
    registration: PlayerAdapterRegistration(
      id: 'fake',
      factory: TestPlayerFactory.fakeAdapterFactory(),
      capabilities: const FakePlayerAdapterBehavior().capabilities,
    ),
    adapterContext: TestPlayerFactory.context(),
    eventBus: PlayerEventBus(),
    options: const KernelOptions(),
  );
}

void main() {
  test('live options are delivered and reported as applied', () async {
    final fake = FakePlayerAdapter(id: 'fake-1');
    final handle = _handle(fake);

    await handle.initialize();
    await handle.open(_source('s1'));

    final report = await handle.applyEngineOptions(const [
      EngineOption('hwdec', 'auto'),
      EngineOption('cache-secs', 30),
    ]);

    expect(report.appliedLive.map((option) => option.key), <String>['hwdec', 'cache-secs']);
    expect(report.rebuiltFor, isEmpty);
    expect(fake.receivedEngineOptions.map((option) => option.key), containsAll(<String>['hwdec', 'cache-secs']));
    expect(identical(handle.adapter, fake), isTrue);

    await handle.dispose();
  });

  test('options the engine cannot take live rebuild the engine on the same backend', () async {
    final original = FakePlayerAdapter(id: 'fake-1')
      ..engineOptionHandler = (option) =>
          option.key == 'needs-rebuild' ? EngineOptionOutcome.needsRebuild : EngineOptionOutcome.appliedLive;
    final handle = _handle(original);

    await handle.initialize();
    await handle.open(_source('s1'));

    final report = await handle.applyEngineOptions(const [
      EngineOption('hwdec', 'auto'),
      EngineOption('needs-rebuild', 'yes'),
    ]);

    expect(report.appliedLive.map((option) => option.key), <String>['hwdec']);
    expect(report.rebuiltFor.map((option) => option.key), <String>['needs-rebuild']);

    // Same backend, fresh instance, source preserved.
    expect(handle.backendId, 'fake');
    expect(identical(handle.adapter, original), isFalse);

    // The persisted options were replayed on the fresh engine before it opened.
    final rebuilt = handle.adapter as FakePlayerAdapter;
    expect(rebuilt.receivedEngineOptions.map((option) => option.key), containsAll(<String>['hwdec', 'needs-rebuild']));

    await handle.dispose();
  });

  test('nextOpen effect never rebuilds the engine', () async {
    final original = FakePlayerAdapter(id: 'fake-1')..engineOptionHandler = (_) => EngineOptionOutcome.needsRebuild;
    final handle = _handle(original);

    await handle.initialize();
    await handle.open(_source('s1'));

    final report = await handle.applyEngineOptions(const [
      EngineOption('cache-size', 999),
    ], effect: EngineOptionEffect.nextOpen);

    expect(report.stagedForNextOpen.map((option) => option.key), <String>['cache-size']);
    expect(report.rebuiltFor, isEmpty);
    expect(identical(handle.adapter, original), isTrue);

    await handle.dispose();
  });

  test('rebuildEngine replaces the instance and keeps the source', () async {
    final original = FakePlayerAdapter(id: 'fake-1');
    final handle = _handle(original);

    await handle.initialize();
    await handle.open(_source('s1'));

    await handle.applyEngineOptions(const [EngineOption('volume-max', 100)]);

    await handle.rebuildEngine(reason: 'test');

    expect(identical(handle.adapter, original), isFalse);
    expect(handle.source?.id, isNotNull);

    final rebuilt = handle.adapter as FakePlayerAdapter;
    expect(rebuilt.receivedEngineOptions.map((option) => option.key), <String>['volume-max']);

    await handle.dispose();
  });
}
