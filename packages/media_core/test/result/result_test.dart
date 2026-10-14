import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/result/result.dart';
import 'package:media_core/result/result_error.dart';

ResultError sampleError() => const ResultError(code: PlayerErrorCode.unknown, message: 'boom');

void main() {
  group('Result', () {
    test('success carries value', () {
      const result = Result<int>.success(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.value, 42);
    });

    test('failure carries error', () {
      final result = Result<int>.failure(sampleError());
      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.error, isA<ResultError>());
    });

    test('value throws on failure and error throws on success', () {
      final failure = Result<int>.failure(sampleError());
      expect(() => failure.value, throwsStateError);

      const success = Result<int>.success(1);
      expect(() => success.error, throwsStateError);
    });

    test('map transforms success values', () {
      const result = Result<int>.success(2);
      final mapped = result.map((value) => value * 10);
      expect(mapped.value, 20);
    });

    test('map keeps failure untouched', () {
      final error = sampleError();
      final result = Result<int>.failure(error);
      final mapped = result.map((value) => value * 10);
      expect(mapped.isFailure, isTrue);
      expect(mapped.error, same(error));
    });

    test('mapError transforms failure errors', () {
      const result = Result<int>.failure(ResultError(code: PlayerErrorCode.unknown, message: 'a'));
      final mapped = result.mapError((error) => ResultError(code: error.code, message: 'b'));
      expect(mapped.error.message, 'b');
    });

    test('fold selects branch by status', () {
      const success = Result<int>.success(1);
      expect(success.fold(onSuccess: (v) => 'ok $v', onFailure: (_) => 'fail'), 'ok 1');

      final failure = Result<int>.failure(sampleError());
      expect(failure.fold(onSuccess: (v) => 'ok $v', onFailure: (_) => 'fail'), 'fail');
    });

    test('getOrElse returns fallback on failure', () {
      const success = Result<int>.success(7);
      expect(success.getOrElse(0), 7);

      final failure = Result<int>.failure(sampleError());
      expect(failure.getOrElse(0), 0);
    });

    test('equality is value based', () {
      expect(const Result<int>.success(1), const Result<int>.success(1));
      expect(const Result<int>.success(1), isNot(const Result<int>.success(2)));
    });
  });
}
