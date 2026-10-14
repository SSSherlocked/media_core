import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/core/player_error.dart';
import 'package:media_core/error/player_error_category.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/identity/player_id.dart';
import 'package:media_core/identity/session_id.dart';

void main() {
  group('PlayerError', () {
    test('carries code, message and context', () {
      final error = PlayerError(
        code: PlayerErrorCode.backendOpenFailed,
        message: 'open failed',
        playerId: PlayerId('p1'),
        sessionId: SessionId('s1'),
      );

      expect(error.code, PlayerErrorCode.backendOpenFailed);
      expect(error.message, 'open failed');
      expect(error.hasPlayer, isTrue);
      expect(error.hasSession, isTrue);
      expect(error.hasContext, isTrue);
    });

    test('empty error has no context', () {
      const error = PlayerError(code: PlayerErrorCode.unknown, message: 'boom');
      expect(error.hasContext, isFalse);
      expect(error.hasCause, isFalse);
      expect(error.hasMetadata, isFalse);
    });

    test('effectiveCategory falls back to classifier', () {
      const error = PlayerError(code: PlayerErrorCode.networkTimeout, message: 'timeout');
      expect(error.category, isNull);
      expect(error.effectiveCategory, PlayerErrorCategory.timeout);
      expect(error.isTimeout, isTrue);
    });

    test('explicit category overrides classification', () {
      const error = PlayerError(
        code: PlayerErrorCode.unknown,
        message: 'custom',
        category: PlayerErrorCategory.network,
      );
      expect(error.effectiveCategory, PlayerErrorCategory.network);
      expect(error.isNetworkRelated, isTrue);
    });

    test('relation helpers classify by code and category', () {
      const network = PlayerError(code: PlayerErrorCode.networkUnavailable, message: 'offline');
      expect(network.isNetworkRelated, isTrue);

      const source = PlayerError(code: PlayerErrorCode.sourceInvalid, message: 'bad source');
      expect(source.isSourceRelated, isTrue);

      const backend = PlayerError(code: PlayerErrorCode.backendFatal, message: 'fatal');
      expect(backend.isBackendRelated, isTrue);

      const cancelled = PlayerError(code: PlayerErrorCode.cancelled, message: 'cancelled');
      expect(cancelled.isCancellation, isTrue);
      expect(cancelled.isUnknown, isFalse);
    });

    test('unknown code is unknown', () {
      const error = PlayerError(code: PlayerErrorCode.unknown, message: '?');
      expect(error.isUnknown, isTrue);
    });

    test('equality is value based', () {
      const a = PlayerError(code: PlayerErrorCode.timeout, message: 't');
      const b = PlayerError(code: PlayerErrorCode.timeout, message: 't');
      expect(a, b);

      const c = PlayerError(code: PlayerErrorCode.timeout, message: 'other');
      expect(a, isNot(c));
    });
  });

  group('PlayerErrorCode', () {
    test('distinct codes have distinct values', () {
      expect(PlayerErrorCode.unknown.value, isNot(PlayerErrorCode.timeout.value));
      expect(PlayerErrorCode.backendOpenFailed.value, isNotEmpty);
    });

    test('factory helpers resolve codes', () {
      expect(PlayerErrorCode.fromValue(PlayerErrorCode.network.value), PlayerErrorCode.network);
      expect(PlayerErrorCode.tryFromValue('no-such-code'), isNull);
      expect(PlayerErrorCode.fromValue('no-such-code'), PlayerErrorCode.unknown);
      expect(() => PlayerErrorCode.fromJson(1), throwsFormatException);
    });
  });
}
