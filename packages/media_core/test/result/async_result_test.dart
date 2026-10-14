import 'package:flutter_test/flutter_test.dart';
import 'package:media_core/error/player_error_code.dart';
import 'package:media_core/identity/request_id.dart';
import 'package:media_core/result/async_result.dart';
import 'package:media_core/result/operation_result.dart';
import 'package:media_core/result/result_error.dart';

ResultError sampleError() => const ResultError(code: PlayerErrorCode.unknown, message: 'boom');

void main() {
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

    test('carries request identity', () {
      final result = AsyncResult<int>.success(1, requestId: RequestId('r1'));
      expect(result.requestId?.value, 'r1');
    });

    test('fromOperationResult infers status', () {
      final inner = OperationResult<int>.success(1);
      final result = AsyncResult<int>.fromOperationResult(inner);
      expect(result.status, AsyncResultStatus.success);

      final failing = OperationResult<int>.failure(sampleError());
      final failed = AsyncResult<int>.fromOperationResult(failing);
      expect(failed.status, AsyncResultStatus.failure);
    });

    test('equality is value based', () {
      const a = AsyncResult<int>.idle();
      const b = AsyncResult<int>.idle();
      expect(a, b);
    });
  });
}
