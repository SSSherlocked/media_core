import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/result/async_result.dart';
import 'package:media_core/result/operation_result.dart';
import 'package:media_core/result/result_error.dart';

ResultError sampleError() => const ResultError(code: PlayerErrorCode.unknown, message: 'boom');

void main() {
  group('OperationResult', () {
    test('success wraps a success result', () {
      final result = OperationResult<int>.success(3, operation: 'load');
      expect(result.isSuccess, isTrue);
      expect(result.value, 3);
      expect(result.operation, 'load');
    });

    test('failure wraps a failure result', () {
      final result = OperationResult<int>.failure(sampleError(), operation: 'load');
      expect(result.isFailure, isTrue);
      expect(result.error.message, 'boom');
    });

    test('carries request and generation identity', () {
      final result = OperationResult<int>.success(1, requestId: RequestId('r1'));
      expect(result.requestId?.value, 'r1');
    });

    test('duration is optional metadata', () {
      final result = OperationResult<int>.success(1, duration: const Duration(milliseconds: 5));
      expect(result.duration, const Duration(milliseconds: 5));
    });
  });

  group('AsyncResult', () {
    test('idle has no operation result', () {
      const result = AsyncResult<int>.idle();
      expect(result.status, AsyncResultStatus.idle);
      expect(result.operationResult, isNull);
    });

    test('running reports running status', () {
      const result = AsyncResult<int>.running(operation: 'open');
      expect(result.status, AsyncResultStatus.running);
      expect(result.operation, 'open');
    });

    test('success delegates to wrapped operation result', () {
      final result = AsyncResult<int>.success(9, operation: 'open');
      expect(result.status, AsyncResultStatus.success);
      expect(result.operationResult, isNotNull);
      expect(result.operationResult!.value, 9);
    });

    test('failure delegates to wrapped operation result', () {
      final result = AsyncResult<int>.failure(sampleError(), operation: 'open');
      expect(result.status, AsyncResultStatus.failure);
      expect(result.operationResult!.error.message, 'boom');
    });

    test('fromOperationResult infers status', () {
      final inner = OperationResult<int>.success(1);
      final result = AsyncResult<int>.fromOperationResult(inner);
      expect(result.status, AsyncResultStatus.success);

      final failing = OperationResult<int>.failure(sampleError());
      final failed = AsyncResult<int>.fromOperationResult(failing);
      expect(failed.status, AsyncResultStatus.failure);
    });
  });
}
