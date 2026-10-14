// Temporary smoke check for presentation widgets. Deleted after the run.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/media_core.dart' hide PlayerOverlay;
import 'package:media_core_presentation/media_core_presentation.dart';

double _opacityOf(WidgetTester tester, String text) {
  return tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: find.text(text), matching: find.byType(AnimatedOpacity)).first,
      )
      .opacity;
}

void main() {
  test('VideoOrientation derives landscape / portrait / square', () {
    expect(VideoOrientation.fromSize(1920, 1080), VideoOrientation.landscape);
    expect(VideoOrientation.fromSize(1080, 1920), VideoOrientation.portrait);
    expect(VideoOrientation.fromSize(1000, 1000), VideoOrientation.square);
    expect(VideoOrientation.fromSize(0, 0), VideoOrientation.unknown);
  });

  testWidgets('overlay: touch mode always shows withControls layers', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaPlayerOverlay(
            hoverMode: false,
            child: ColoredBox(color: Colors.black),
            layers: [
              PlayerOverlayLayer(
                slot: PlayerOverlaySlot.bottom,
                visibility: PlayerOverlayVisibility.withControls,
                builder: _controlBar,
              ),
              PlayerOverlayLayer(slot: PlayerOverlaySlot.center, builder: _anyContent),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Text), findsNWidgets(2));
    expect(_opacityOf(tester, 'controls'), 1.0, reason: 'touch mode keeps withControls layers visible');
  });

  testWidgets('overlay: hover mode reveals on enter, auto-hides after idle', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaPlayerOverlay(
            hoverMode: true,
            hoverAutoHideDelay: Duration(seconds: 5),
            child: ColoredBox(color: Colors.black),
            layers: [
              PlayerOverlayLayer(
                slot: PlayerOverlaySlot.bottom,
                visibility: PlayerOverlayVisibility.withControls,
                builder: _controlBar,
              ),
              PlayerOverlayLayer(slot: PlayerOverlaySlot.center, builder: _anyContent),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_opacityOf(tester, 'controls'), 0.0, reason: 'hover mode hides withControls layers while idle');
    // An always layer is not wrapped in an AnimatedOpacity at all: there is no
    // other opacity for it to fade to, so the wrapper would only add a layer.
    expect(find.text('content'), findsOneWidget, reason: 'always layers never hide');
    expect(
      find.ancestor(of: find.text('content'), matching: find.byType(AnimatedOpacity)),
      findsNothing,
      reason: 'always layers are not animated',
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

  testWidgets('stage: portrait video + fill strategy uses cover fit', (WidgetTester tester) async {
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
    final presentation = MediaCorePresentation(
      config: const PresentationCapabilityConfig(overlayHoverMode: false),
    );
    expect(presentation.overlayHoverMode, isFalse);
  });
}

Widget _controlBar(BuildContext context) {
  return const Text('controls', textDirection: TextDirection.ltr);
}

Widget _anyContent(BuildContext context) {
  return const Text('content', textDirection: TextDirection.ltr);
}
