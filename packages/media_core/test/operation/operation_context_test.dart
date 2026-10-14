import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/identity/generation_id.dart';
import 'package:media_core/identity/operation_id.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/identity/session_id.dart';
import 'package:media_core/identity/slot_id.dart';
import 'package:media_core/identity/source_id.dart';
import 'package:media_core/operation/operation_context.dart';

void main() {
  final full = OperationContext(
    playerId: PlayerId('player-1'),
    sessionId: SessionId('session-1'),
    slotId: SlotId('slot-1'),
    sourceId: SourceId('source-1'),
    requestId: RequestId('request-1'),
    operationId: OperationId('operation-1'),
    generationId: GenerationId('generation-1'),
    lineId: 'line-1',
    quality: '1080p',
    uri: 'https://example.test/media.m3u8',
    platform: 'android',
    backend: 'media_kit',
    adapter: 'MediaKitPlayerAdapter',
    description: 'switch source',
    reason: 'user gesture',
    parameters: const <String, Object?>{'bitrate': 4200},
    metadata: const <String, Object?>{'trace': 'abc'},
  );

  /// One case per `withoutX()` helper: the field it must drop and how to read
  /// that field back.
  final cases =
      <
        ({
          String helper,
          String field,
          Object? Function(OperationContext context) read,
          OperationContext Function(OperationContext context) apply,
        })
      >[
        (helper: 'withoutPlayerId', field: 'playerId', read: (c) => c.playerId, apply: (c) => c.withoutPlayerId()),
        (helper: 'withoutSessionId', field: 'sessionId', read: (c) => c.sessionId, apply: (c) => c.withoutSessionId()),
        (helper: 'withoutSlotId', field: 'slotId', read: (c) => c.slotId, apply: (c) => c.withoutSlotId()),
        (helper: 'withoutSourceId', field: 'sourceId', read: (c) => c.sourceId, apply: (c) => c.withoutSourceId()),
        (helper: 'withoutRequestId', field: 'requestId', read: (c) => c.requestId, apply: (c) => c.withoutRequestId()),
        (
          helper: 'withoutOperationId',
          field: 'operationId',
          read: (c) => c.operationId,
          apply: (c) => c.withoutOperationId(),
        ),
        (
          helper: 'withoutGenerationId',
          field: 'generationId',
          read: (c) => c.generationId,
          apply: (c) => c.withoutGenerationId(),
        ),
        (helper: 'withoutLineId', field: 'lineId', read: (c) => c.lineId, apply: (c) => c.withoutLineId()),
        (helper: 'withoutQuality', field: 'quality', read: (c) => c.quality, apply: (c) => c.withoutQuality()),
        (helper: 'withoutUri', field: 'uri', read: (c) => c.uri, apply: (c) => c.withoutUri()),
        (helper: 'withoutPlatform', field: 'platform', read: (c) => c.platform, apply: (c) => c.withoutPlatform()),
        (helper: 'withoutBackend', field: 'backend', read: (c) => c.backend, apply: (c) => c.withoutBackend()),
        (helper: 'withoutAdapter', field: 'adapter', read: (c) => c.adapter, apply: (c) => c.withoutAdapter()),
        (
          helper: 'withoutDescription',
          field: 'description',
          read: (c) => c.description,
          apply: (c) => c.withoutDescription(),
        ),
        (helper: 'withoutReason', field: 'reason', read: (c) => c.reason, apply: (c) => c.withoutReason()),
      ];

  group('OperationContext clearing', () {
    test('the fixture carries every field a helper can clear', () {
      for (final c in cases) {
        expect(c.read(full), isNotNull, reason: 'A missing ${c.field} makes ${c.helper}() vacuous.');
      }
    });

    test('every helper drops only its own field', () {
      for (final cleared in cases) {
        final next = cleared.apply(full);

        for (final kept in cases) {
          expect(
            kept.read(next),
            kept.field == cleared.field ? isNull : kept.read(full),
            reason: '${cleared.helper}() handling of ${kept.field}.',
          );
        }

        expect(next.parameters, full.parameters, reason: '${cleared.helper}() and parameters.');
        expect(next.metadata, full.metadata, reason: '${cleared.helper}() and metadata.');
      }
    });

    test('cleared() drops several fields in one copy', () {
      final next = full.cleared(playerId: true, uri: true, reason: true);

      expect(next.playerId, isNull);
      expect(next.uri, isNull);
      expect(next.reason, isNull);
      expect(next.operationId, full.operationId);
    });

    test('cleared() with no flags returns an equal context', () {
      expect(full.cleared(), full);
    });

    test('a cleared field can be set again', () {
      final next = full.withoutPlayerId().copyWith(playerId: PlayerId('player-2'));

      expect(next.playerId, PlayerId('player-2'));
      expect(next.sessionId, full.sessionId);
    });
  });

  group('OperationContext copyWith', () {
    test('omitted arguments keep the current value', () {
      final next = full.copyWith(description: 'retry');

      expect(next.description, 'retry');
      expect(next.playerId, full.playerId);
      expect(next.reason, full.reason);
    });
  });
}
