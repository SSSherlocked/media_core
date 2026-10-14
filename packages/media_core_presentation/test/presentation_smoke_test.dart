// Temporary smoke check for presentation widgets. Deleted after the run.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart' hide PlayerOverlay;
import 'package:media_core_presentation/media_core_presentation.dart';

double _opacityOf(WidgetTester tester, String text) {
  return tester
      .widget<AnimatedOpacity>(find.ancestor(of: find.text(text), matching: find.byType(AnimatedOpacity)).first)
      .opacity;
}

void main() {
  test('VideoOrientation derives landscape / portrait / square', () {
    expect(VideoOrientation.fromSize(1920, 1080), VideoOrientation.landscape);
    expect(VideoOrientation.fromSize(1080, 1920), VideoOrientation.portrait);
    expect(VideoOrientation.fromSize(1000, 1000), VideoOrientation.square);
    expect(VideoOrientation.fromSize(0, 0), VideoOrientation.unknown);
  });

  testWidgets('overlay: touch mode always shows withControls layers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaPlayerOverlay(
            hoverMode: false,
            layers: [
              PlayerOverlayLayer(
                slot: PlayerOverlaySlot.bottom,
                visibility: PlayerOverlayVisibility.withControls,
                builder: _controlBar,
              ),
              PlayerOverlayLayer(slot: PlayerOverlaySlot.center, builder: _anyContent),
            ],
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Text), findsNWidgets(2));
    expect(_opacityOf(tester, 'controls'), 1.0, reason: 'touch mode keeps withControls layers visible');
  });

  testWidgets('overlay: hover mode reveals on enter, auto-hides after idle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaPlayerOverlay(
            hoverAutoHideDelay: Duration(seconds: 5),
            layers: [
              PlayerOverlayLayer(
                slot: PlayerOverlaySlot.bottom,
                visibility: PlayerOverlayVisibility.withControls,
                builder: _controlBar,
              ),
              PlayerOverlayLayer(slot: PlayerOverlaySlot.center, builder: _anyContent),
            ],
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_opacityOf(tester, 'controls'), 0.0, reason: 'hover mode hides withControls layers while idle');
    // always layers never hide, and the implementation expresses that by not
    // wrapping them in an AnimatedOpacity at all - asserting on a wrapper that
    // is deliberately absent would look for a widget that cannot exist.
    expect(
      find.ancestor(of: find.text('content'), matching: find.byType(AnimatedOpacity)),
      findsNothing,
      reason: 'always layers are never opacity-hidden',
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.byType(MediaPlayerOverlay)));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(_opacityOf(tester, 'controls'), 1.0, reason: 'hover reveals withControls layers');

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(_opacityOf(tester, 'controls'), 0.0, reason: 'auto-hide after idle delay');
    expect(find.text('content'), findsOneWidget, reason: 'always layers still visible');
  });

  testWidgets('overlay: a moving pointer revives the layers, a quiet one lets them fall', (tester) async {
    const delay = Duration(milliseconds: 500);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaPlayerOverlay(
            hoverAutoHideDelay: delay,
            layers: [
              PlayerOverlayLayer(
                slot: PlayerOverlaySlot.bottom,
                visibility: PlayerOverlayVisibility.withControls,
                builder: _controlBar,
              ),
            ],
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final center = tester.getCenter(find.byType(MediaPlayerOverlay));

    await gesture.moveTo(center);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_opacityOf(tester, 'controls'), 1.0, reason: 'entering reveals');

    // A pointer that never left cannot send another enter event, so the idle
    // fade has to be liftable by movement alone.
    await tester.pump(delay * 2 + const Duration(milliseconds: 50));
    expect(_opacityOf(tester, 'controls'), 0.0, reason: 'a quiet stretch hides them');

    await gesture.moveTo(center + const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_opacityOf(tester, 'controls'), 1.0, reason: 'moving brings them back');

    // ...and the countdown has to arm again afterwards: a cancelled timer left
    // in the field reads as "already counting", which would strand the layers
    // on screen for the rest of the session.
    await tester.pump(delay * 2 + const Duration(milliseconds: 50));
    expect(_opacityOf(tester, 'controls'), 0.0, reason: 'and it fades on its own again');
  });

  testWidgets('stage: portrait video + fill strategy uses cover fit', (tester) async {
    final presentation = MediaCorePresentation(
      config: const PresentationCapabilityConfig(portraitFullscreenStrategy: PortraitFullscreenStrategy.fill),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresentationStage(
            presentation: presentation,
            orientation: VideoOrientation.portrait,
            videoBuilder: (context, orientation) => const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.widget<FittedBox>(find.byType(FittedBox)).fit, BoxFit.cover);
  });

  test('kernel presentation shortcuts throw without driver', () async {
    final kernel = PlayerKernel();
    addTearDown(kernel.dispose);

    expect(() => kernel.enterFullscreen(PlayerId('nope')), throwsStateError);
  });

  test('MediaCorePresentation hover mode honours config override', () {
    final presentation = MediaCorePresentation(config: const PresentationCapabilityConfig(overlayHoverMode: false));
    expect(presentation.overlayHoverMode, isFalse);
  });
}

Widget _controlBar(BuildContext context) {
  return const Text('controls', textDirection: TextDirection.ltr);
}

Widget _anyContent(BuildContext context) {
  return const Text('content', textDirection: TextDirection.ltr);
}
