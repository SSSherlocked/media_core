import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart';

final class _RecordingDriver implements KernelPresentationDriver {
  _RecordingDriver(this.label, {this.onApply});

  final String label;
  final Future<void> Function(PresentationMode mode)? onApply;

  final List<PresentationMode> applied = <PresentationMode>[];
  int disposeCount = 0;

  @override
  Future<void> apply(PlayerId playerId, PresentationRequest request) async {
    applied.add(request.mode);
    await onApply?.call(request.mode);
  }

  @override
  Future<void> dispose() async => disposeCount++;
}

void main() {
  final player = PlayerId('player_chain');

  group('PresentationMode', () {
    test('keeps the two fullscreen variants apart', () {
      expect(PresentationMode.fullscreen.isFullscreen, isTrue);
      expect(PresentationMode.fullscreen.isWindowFullscreen, isFalse);

      expect(PresentationMode.windowFullscreen.isWindowFullscreen, isTrue);
      expect(PresentationMode.windowFullscreen.isFullscreen, isFalse);

      expect(PresentationMode.fullscreen.isAnyFullscreen, isTrue);
      expect(PresentationMode.windowFullscreen.isAnyFullscreen, isTrue);
      expect(PresentationMode.normal.isAnyFullscreen, isFalse);
      expect(PresentationMode.pip.isAnyFullscreen, isFalse);
    });

    test('neither fullscreen variant counts as an overlay', () {
      expect(PresentationMode.fullscreen.isOverlay, isFalse);
      expect(PresentationMode.windowFullscreen.isOverlay, isFalse);
      expect(PresentationMode.pip.isOverlay, isTrue);
      expect(PresentationMode.floating.isOverlay, isTrue);
    });

    test('both fullscreen variants need the presentation layer', () {
      expect(PresentationMode.fullscreen.requiresPresentationLayer, isTrue);
      expect(PresentationMode.windowFullscreen.requiresPresentationLayer, isTrue);
      expect(PresentationMode.normal.requiresPresentationLayer, isFalse);
    });

    test('capabilities treat window fullscreen as its own ability', () {
      const capabilities = PresentationCapabilities(fullscreen: false);

      expect(capabilities.supports(PresentationMode.fullscreen), isFalse);
      expect(capabilities.supports(PresentationMode.windowFullscreen), isTrue);
      expect(capabilities.canWindowFullscreen, isTrue);
      expect(capabilities.supportedModes, contains(PresentationMode.windowFullscreen));
      expect(capabilities.supportedModes, isNot(contains(PresentationMode.fullscreen)));
    });

    test('policy separates allowing the window from allowing the screen', () {
      const policy = PresentationPolicy(allowFullscreen: false);

      expect(policy.canEnter(PresentationMode.fullscreen), isFalse);
      expect(policy.canEnter(PresentationMode.windowFullscreen), isTrue);
    });

    test('requests expose the variant they ask for', () {
      expect(PresentationRequest.fullscreen().isAnyFullscreen, isTrue);
      expect(PresentationRequest.fullscreen().isWindowFullscreen, isFalse);
      expect(PresentationRequest.windowFullscreen().isWindowFullscreen, isTrue);
      expect(PresentationRequest.windowFullscreen().isFullscreen, isFalse);
      expect(PresentationRequest.normal().isAnyFullscreen, isFalse);
    });
  });

  group('PresentationDriverChain', () {
    test('routes each mode to the driver that owns it', () async {
      final fullscreen = _RecordingDriver('fullscreen');
      final pip = _RecordingDriver('pip');
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(
            modes: {PresentationMode.fullscreen, PresentationMode.windowFullscreen},
            driver: fullscreen,
          ),
          PresentationDriverBinding(modes: {PresentationMode.pip}, driver: pip),
        ],
      );

      await chain.apply(player, PresentationRequest.fullscreen());
      await chain.apply(player, PresentationRequest.pip());
      await chain.apply(player, PresentationRequest.windowFullscreen());

      // The fullscreen driver serves both variants. It is released with normal
      // when PiP takes over, and re-entered when window fullscreen comes back:
      // the chain, not the incoming driver, owns that hand-off.
      expect(fullscreen.applied, <PresentationMode>[
        PresentationMode.fullscreen,
        PresentationMode.normal,
        PresentationMode.windowFullscreen,
      ]);
      expect(pip.applied, <PresentationMode>[PresentationMode.pip, PresentationMode.normal]);
    });

    test('releases the outgoing driver before activating the next one', () async {
      final order = <String>[];
      final fullscreen = _RecordingDriver('fullscreen', onApply: (mode) async => order.add('fullscreen:${mode.name}'));
      final pip = _RecordingDriver('pip', onApply: (mode) async => order.add('pip:${mode.name}'));
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(modes: {PresentationMode.fullscreen}, driver: fullscreen),
          PresentationDriverBinding(modes: {PresentationMode.pip}, driver: pip),
        ],
      );

      await chain.apply(player, PresentationRequest.fullscreen());
      await chain.apply(player, PresentationRequest.pip());

      expect(order, <String>['fullscreen:fullscreen', 'fullscreen:normal', 'pip:pip']);
    });

    test('normal releases the active driver and is a no-op when idle', () async {
      final fullscreen = _RecordingDriver('fullscreen');
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(modes: {PresentationMode.fullscreen}, driver: fullscreen),
        ],
      );

      await chain.apply(player, PresentationRequest.normal());
      expect(fullscreen.applied, isEmpty);

      await chain.apply(player, PresentationRequest.fullscreen());
      await chain.apply(player, PresentationRequest.normal());

      expect(fullscreen.applied, <PresentationMode>[PresentationMode.fullscreen, PresentationMode.normal]);
      expect(chain.activeBinding, isNull);
    });

    test('repeating the same mode does not release and re-enter it', () async {
      final fullscreen = _RecordingDriver('fullscreen');
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(modes: {PresentationMode.fullscreen}, driver: fullscreen),
        ],
      );

      await chain.apply(player, PresentationRequest.fullscreen());
      await chain.apply(player, PresentationRequest.fullscreen());

      expect(fullscreen.applied, <PresentationMode>[PresentationMode.fullscreen, PresentationMode.fullscreen]);
    });

    test('refuses a mode no installed driver serves', () async {
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(modes: {PresentationMode.pip}, driver: _RecordingDriver('pip')),
        ],
      );

      await expectLater(chain.apply(player, PresentationRequest.fullscreen()), throwsA(isA<UnsupportedError>()));
      expect(chain.canServe(PresentationMode.fullscreen), isFalse);
      expect(chain.canServe(PresentationMode.normal), isTrue);
    });

    test('rejects two drivers claiming the same mode', () {
      expect(
        () => PresentationDriverChain(
          bindings: [
            PresentationDriverBinding(modes: {PresentationMode.pip}, driver: _RecordingDriver('a')),
            PresentationDriverBinding(modes: {PresentationMode.pip}, driver: _RecordingDriver('b')),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a driver that fails to release does not block the next transition', () async {
      final failing = _RecordingDriver(
        'failing',
        onApply: (mode) async {
          if (mode == PresentationMode.normal) {
            throw StateError('release failed');
          }
        },
      );
      final pip = _RecordingDriver('pip');
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(modes: {PresentationMode.fullscreen}, driver: failing),
          PresentationDriverBinding(modes: {PresentationMode.pip}, driver: pip),
        ],
      );

      await chain.apply(player, PresentationRequest.fullscreen());
      await expectLater(chain.apply(player, PresentationRequest.pip()), throwsA(isA<StateError>()));

      // The failure is reported, but the chain is not stuck holding the
      // broken driver as active.
      await chain.apply(player, PresentationRequest.pip());
      expect(pip.applied.last, PresentationMode.pip);
    });

    test('dispose releases every driver, including inactive ones', () async {
      final fullscreen = _RecordingDriver('fullscreen');
      final pip = _RecordingDriver('pip');
      final chain = PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(modes: {PresentationMode.fullscreen}, driver: fullscreen),
          PresentationDriverBinding(modes: {PresentationMode.pip}, driver: pip),
        ],
      );

      await chain.dispose();

      expect(fullscreen.disposeCount, 1);
      expect(pip.disposeCount, 1);
    });
  });

  group('PresentationState orientation', () {
    test('a repeated orientation is not republished', () async {
      final controller = PresentationController();
      final seen = <VideoOrientation>[];
      controller.state.listen((state) => seen.add(state.orientation));

      controller
        ..updateOrientation(VideoOrientation.portrait)
        ..updateOrientation(VideoOrientation.portrait)
        ..updateOrientation(VideoOrientation.landscape);

      // The state subject delivers asynchronously.
      await Future<void>.delayed(Duration.zero);

      expect(seen, <VideoOrientation>[VideoOrientation.unknown, VideoOrientation.portrait, VideoOrientation.landscape]);
      expect(controller.current.orientation, VideoOrientation.landscape);
    });
  });
}
