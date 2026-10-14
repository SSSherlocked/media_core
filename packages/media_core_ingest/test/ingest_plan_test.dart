import 'package:flutter_test/flutter_test.dart';
import 'package:media_core_ingest/media_core_ingest.dart';

void main() {
  group('ingest plan', () {
    test('a source without declared needs goes straight to the player', () {
      final plan = resolveIngestPlan(needs: const <IngestNeed>{});
      expect(plan.strategy, IngestStrategy.direct);
      expect(plan.isDirect, isTrue);
      expect(plan.needs, isEmpty);
    });

    test('relative or absolute-path children are rewritten over loopback', () {
      for (final need in <IngestNeed>[
        IngestNeed.relativeChildren,
        IngestNeed.absolutePathChildren,
        IngestNeed.childToken,
        IngestNeed.sessionCookies,
      ]) {
        final plan = resolveIngestPlan(needs: <IngestNeed>{need});
        expect(plan.strategy, IngestStrategy.manifestRelay, reason: need.name);
        expect(plan.needs, <IngestNeed>{need});
      }
    });

    test('a manifest rewrite is pointless for a non-manifest source', () {
      final plan = resolveIngestPlan(needs: const <IngestNeed>{IngestNeed.relativeChildren}, sourceIsManifest: false);
      expect(plan.strategy, IngestStrategy.direct);
    });

    test('expiring URLs and unparsable containers go through FFmpeg', () {
      expect(resolveIngestPlan(needs: const <IngestNeed>{IngestNeed.expiringUrl}).strategy, IngestStrategy.ffmpegRelay);
      expect(
        resolveIngestPlan(needs: const <IngestNeed>{IngestNeed.legacyContainer}).strategy,
        IngestStrategy.ffmpegRelay,
      );
      // FFmpeg wins over a rewrite when both are declared: it produces a local
      // playlist anyway, which makes the rewrite unnecessary.
      expect(
        resolveIngestPlan(needs: const <IngestNeed>{IngestNeed.legacyContainer, IngestNeed.childToken}).strategy,
        IngestStrategy.ffmpegRelay,
      );
    });

    test('a plan reports the needs it was built from', () {
      final plan = resolveIngestPlan(needs: const <IngestNeed>{IngestNeed.expiringUrl});
      expect(plan.toString(), contains('ffmpegRelay'));
      expect(plan.toString(), contains('expiringUrl'));
    });
  });
}
