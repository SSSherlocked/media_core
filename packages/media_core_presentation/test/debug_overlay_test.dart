import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_presentation/media_core_presentation.dart';

void main() {
  testWidgets('debug two layers', (tester) async {
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
    debugPrint('initial controls: ${find.text('controls').evaluate().length}');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.byType(MediaPlayerOverlay)));
    addTearDown(gesture.removePointer);
    await tester.pump();
    debugPrint('after enter controls: ${find.text('controls').evaluate().length}');
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    debugPrint('after hide controls: ${find.text('controls').evaluate().length}');
    debugPrint('content: ${find.text('content').evaluate().length}');
    final ao = find.ancestor(of: find.text('controls'), matching: find.byType(AnimatedOpacity)).evaluate();
    debugPrint('controls AO ancestors: ${ao.length}');
  });
}

Widget _controlBar(BuildContext context) {
  return const Text('controls', textDirection: TextDirection.ltr);
}

Widget _anyContent(BuildContext context) {
  return const Text('content', textDirection: TextDirection.ltr);
}
