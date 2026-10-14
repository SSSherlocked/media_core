import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:media_core_presentation/media_core_presentation.dart';

/// Hover behaviour has its own suite in `presentation_smoke_test.dart` (reveal,
/// idle fade, revive). What no test pinned is the *cost* of the fix: a desktop
/// mouse reports a hundred moves a second, and every report used to cancel the
/// countdown, build a new timer and rebuild the layer.
///
/// The rule these hold is the one the widget now implements: movement marks
/// the running window and buys exactly one more; the rebuild happens on the
/// reveal and on the fade, never on a pointer report.
Future<(TestGesture mouse, Offset inside, int Function() builds)> _start(WidgetTester tester) async {
  var builds = 0;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaPlayerOverlay(
          hoverAutoHideDelay: const Duration(milliseconds: 600),
          layers: <PlayerOverlayLayer>[
            PlayerOverlayLayer(
              slot: PlayerOverlaySlot.bottom,
              visibility: PlayerOverlayVisibility.withControls,
              builder: (context) {
                builds++;

                return const Center(child: Text('bar'));
              },
            ),
          ],
          child: const ColoredBox(color: Colors.black),
        ),
      ),
    ),
  );

  final inside = tester.getCenter(find.byType(MediaPlayerOverlay));
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);

  await mouse.addPointer(location: inside);

  addTearDown(mouse.removePointer);

  await tester.pumpAndSettle();

  return (mouse, inside, () => builds);
}

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.ancestor(of: find.text('bar'), matching: find.byType(AnimatedOpacity)).first)
    .opacity;

/// Two windows plus the animation: long enough that a window bought by
/// movement has also expired.
const Duration _quiet = Duration(milliseconds: 1400);

void main() {
  testWidgets('pointer reports rebuild nothing; only the fade does', (tester) async {
    final (mouse, inside, builds) = await _start(tester);

    final revealed = builds();

    for (var i = 0; i < 50; i++) {
      await mouse.moveTo(inside + Offset(4.0 + i, 2));
    }

    expect(
      builds() - revealed,
      0,
      reason:
          'movement marks the countdown - a report that rebuilt the overlay '
          'is the stutter a desktop host feels while reaching for the bar',
    );

    await tester.pump(_quiet);
    await tester.pumpAndSettle();

    expect(_opacity(tester), 0.0, reason: 'a quiet pointer still ends it');
    expect(builds() - revealed, 1, reason: 'the fade is the only state change in there');
  });

  testWidgets('moving through a deadline buys one window, then falls', (tester) async {
    final (mouse, inside, builds) = await _start(tester);

    final revealed = builds();

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(inside + Offset(3.0 + i, 3));
    }

    expect(_opacity(tester), 1.0, reason: 'still moving at t=2s, so still up');
    expect(builds() - revealed, 0, reason: 'a re-arm is a timer swap, not a rebuild');

    // The last report was at t=2s; the window it was marking expired at 2.4s
    // and bought one more, which expires at 3s with nothing left to mark it.
    await tester.pump(_quiet);
    await tester.pumpAndSettle();

    expect(_opacity(tester), 0.0, reason: 'two quiet windows end it, not a hundred timers');
    expect(builds() - revealed, 1);
  });
}
