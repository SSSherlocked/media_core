import 'package:flutter_test/flutter_test.dart';

import 'package:media_core/identity/source_id.dart';
import 'package:media_core/preload/preload_manager.dart';
import 'package:media_core/preload/preload_request.dart';

void main() {
  group('PreloadManager ledger', () {
    test('a completed preload stops counting as held memory', () {
      final manager = PreloadManager()
        ..add(PreloadRequest(sourceId: SourceId('a')))
        ..add(PreloadRequest(sourceId: SourceId('b')));

      expect(manager.count, 2);

      manager.complete(manager.next()!);

      // The ledger feeds a shared memory account that other modules read when
      // deciding what to shed, so a finished task left behind reports a
      // stream nobody is holding.
      expect(manager.count, 1);
      expect(manager.currentMetrics.completed, 1);
      expect(manager.currentMetrics.total, 2);
    });

    test('a failed preload stops counting as held memory', () {
      final manager = PreloadManager()
        ..add(PreloadRequest(sourceId: SourceId('a')))
        ..add(PreloadRequest(sourceId: SourceId('b')));

      manager.fail(manager.next()!);

      expect(manager.count, 1);
      expect(manager.currentMetrics.failed, 1);
    });

    test('a cancelled preload stops counting as held memory', () {
      final manager = PreloadManager()
        ..add(PreloadRequest(sourceId: SourceId('a')))
        ..add(PreloadRequest(sourceId: SourceId('b')));

      manager.cancel(manager.next()!);

      expect(manager.count, 1);
      expect(manager.currentMetrics.cancelled, 1);
    });

    test('adding the same source twice keeps one entry', () {
      final manager = PreloadManager()
        ..add(PreloadRequest(sourceId: SourceId('a')))
        ..add(PreloadRequest(sourceId: SourceId('a')));

      expect(manager.count, 1);
    });

    test('metrics are published as the ledger changes', () async {
      final manager = PreloadManager()..add(PreloadRequest(sourceId: SourceId('a')));
      final published = <int>[];
      final subscription = manager.metrics.listen((m) => published.add(m.total));

      manager.complete(manager.next()!);
      await Future<void>.delayed(Duration.zero);

      expect(published, isNotEmpty);
      expect(manager.count, 0);

      await subscription.cancel();
    });
  });
}
