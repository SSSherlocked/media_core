import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart' hide PipController;
import 'package:media_core_pip/media_core_pip.dart';

/// A player the kernel would own, without needing a kernel.
final class _FakePlayer implements PortablePlayer {
  _FakePlayer(this.id);

  @override
  final PlayerId id;

  /// Flipped by a test to stand in for a page that disposed its player.
  bool disposed = false;

  @override
  int get videoWidth => 1920;

  @override
  int get videoHeight => 1080;

  /// No framework handle: the test's own builder renders it.
  @override
  PlayerHandle? get handle => null;

  @override
  bool get isDisposed => disposed;
}

final class _FakeRegistry implements PortablePlayerRegistry {
  _FakeRegistry(this.players);

  final Map<String, _FakePlayer> players;

  void forget(String id) => players.remove(id);

  @override
  PortablePlayer? find(PlayerId id) => players[id.value];
}

final class _FakeDesktopWindow implements PipWindow {
  Rect bounds = const Rect.fromLTWH(0, 0, 1280, 720);

  @override
  Future<PipWindowSnapshot> capture() async =>
      PipWindowSnapshot(bounds: bounds, alwaysOnTop: false, resizable: true, skipTaskbar: false, title: 'test');

  @override
  Future<void> applySmallWindow({
    required Size size,
    required Offset position,
    required double? aspectRatio,
    required bool alwaysOnTop,
    required bool resizable,
    required bool skipTaskbar,
    required String title,
  }) async {}

  @override
  Future<void> restore(PipWindowSnapshot snapshot) async {}

  @override
  Future<void> setAlwaysOnTop({required bool value}) async {}

  @override
  Future<void> setMinimumSize(Size size) async {}

  @override
  Future<void> setAspectRatio(double aspectRatio) async {}

  @override
  Future<void> startDragging() async {}
}

PlayerId _id(String value) => PlayerId(value);

void main() {
  late _FakeRegistry registry;
  late _FakePlayer player;
  late PipDriver driver;
  late PipSessionController controller;

  setUp(() {
    player = _FakePlayer(_id('player-a'));
    registry = _FakeRegistry(<String, _FakePlayer>{'player-a': player});
    driver = PipDriver(platform: PipPlatform.desktop, desktopWindow: _FakeDesktopWindow());
    controller = PipSessionController(
      driver: driver,
      registry: registry,
      surfaceBuilder: (context, playerId) => Text(playerId.value, textDirection: TextDirection.ltr),
    );
  });

  tearDown(() async {
    await controller.dispose();
    await driver.dispose();
  });

  group('PipController handover', () {
    test('carries a live player into the small window', () async {
      await controller.enter(_id('player-a'));

      expect(controller.isActive, isTrue);
      expect(controller.playerId, _id('player-a'));
      expect(controller.hasCarriedPlayer, isTrue);
      expect(driver.isPip, isTrue);
    });

    test('refuses to carry a player the page already disposed', () async {
      player.disposed = true;

      await expectLater(controller.enter(_id('player-a')), throwsA(isA<StateError>()));
      expect(controller.isActive, isFalse, reason: 'a window with no video must not open');
    });

    test('refuses a player that was never registered', () async {
      await expectLater(controller.enter(_id('missing')), throwsA(isA<StateError>()));
    });

    test('passes the video size to the driver so the window is shaped right', () async {
      await controller.enter(_id('player-a'));

      expect(driver.videoWidth, 1920);
      expect(driver.videoHeight, 1080);
    });

    test('leaves the small window without touching the player', () async {
      await controller.enter(_id('player-a'));

      await controller.exit();

      expect(controller.isActive, isFalse);
      expect(player.disposed, isFalse, reason: 'the kernel owns the player, not the window');
      expect(controller.hasCarriedPlayer, isTrue, reason: 'the host can re-attach it to a page');
    });

    test('toggle enters and leaves', () async {
      await controller.toggle(_id('player-a'));
      expect(controller.isActive, isTrue);

      await controller.toggle(_id('player-a'));
      expect(controller.isActive, isFalse);
    });

    test('reports session changes', () async {
      final seen = <bool>[];
      controller.onSessionChanged.listen((session) => seen.add(session.active));

      await controller.enter(_id('player-a'));
      await controller.exit();
      await Future<void>.delayed(Duration.zero);

      expect(seen, <bool>[true, false]);
    });
  });

  group('PipController auto-enter policy', () {
    test('enters when the page goes away while playing', () async {
      final entered = await controller.onPageExit(playerId: _id('player-a'), playing: true);

      expect(entered, isTrue);
      expect(controller.isActive, isTrue);
    });

    test('stays put when the video is paused', () async {
      final entered = await controller.onPageExit(playerId: _id('player-a'), playing: false);

      expect(entered, isFalse);
      expect(controller.isActive, isFalse);
    });

    test('honours a policy that ignores playback state', () async {
      final ignoring = PipSessionController(
        driver: driver,
        registry: registry,
        autoEnter: PipAutoEnterPolicy.defaults.copyWith(requirePlaying: false),
      );
      addTearDown(ignoring.dispose);

      final entered = await ignoring.onPageExit(playerId: _id('player-a'), playing: false);

      expect(entered, isTrue);
    });

    test('honours a policy that disables page exit', () async {
      final disabled = PipSessionController(
        driver: driver,
        registry: registry,
        autoEnter: PipAutoEnterPolicy.defaults.copyWith(onPageExit: false),
      );
      addTearDown(disabled.dispose);

      expect(await disabled.onPageExit(playerId: _id('player-a'), playing: true), isFalse);
      expect(disabled.isActive, isFalse);
    });

    test('a backgrounded app is a separate trigger', () async {
      final noBackground = PipSessionController(
        driver: driver,
        registry: registry,
        autoEnter: PipAutoEnterPolicy.defaults.copyWith(onAppBackground: false),
      );
      addTearDown(noBackground.dispose);

      expect(await noBackground.onAppBackgrounded(playerId: _id('player-a'), playing: true), isFalse);

      final withBackground = PipSessionController(
        driver: driver,
        registry: registry,
        autoEnter: PipAutoEnterPolicy.defaults.copyWith(onAppBackground: true),
      );
      addTearDown(withBackground.dispose);

      expect(await withBackground.onAppBackgrounded(playerId: _id('player-a'), playing: true), isTrue);
      expect(withBackground.isActive, isTrue);
    });

    test('returning to the foreground does not close a window the viewer opened', () async {
      await controller.enter(_id('player-a'));

      await controller.onAppResumed();

      expect(controller.isActive, isTrue);
    });

    test('a repeated trigger for the same player does not re-enter', () async {
      await controller.onPageExit(playerId: _id('player-a'), playing: true);
      final again = await controller.onPageExit(playerId: _id('player-a'), playing: true);

      expect(again, isTrue);
      expect(controller.isActive, isTrue);
    });
  });

  group('PipController surface', () {
    testWidgets('builds the host surface for the carried player', (tester) async {
      late Widget surface;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              return surface = controller.buildSurface(context, _id('player-a'));
            },
          ),
        ),
      );

      expect(find.text('player-a'), findsOneWidget);
      expect(surface, isNotNull);
    });

    test('refuses to build a surface for a player without a handle and no builder', () async {
      final bare = PipSessionController(driver: driver, registry: registry);
      addTearDown(bare.dispose);

      expect(() => bare.buildSurface(_FakeBuildContext(), _id('player-a')), throwsA(isA<StateError>()));
    });
  });

  group('PipController lifecycle', () {
    test('a disposed controller refuses further transitions', () async {
      await controller.dispose();

      await expectLater(controller.enter(_id('player-a')), throwsA(isA<StateError>()));
    });
  });
}

/// Minimal context stand-in: `buildSurface` only passes it to a builder.
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
