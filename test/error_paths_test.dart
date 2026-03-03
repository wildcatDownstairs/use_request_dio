import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);

  group('Error handling paths', () {
    test('DioException.connectionTimeout is captured in state.error', () async {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async {
          throw DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.connectionTimeout,
            error: 'timeout',
          );
        },
        options: const UseRequestOptions(manual: true),
      );

      try {
        await notifier.runAsync(1);
      } catch (_) {}

      expect(notifier.currentState.error, isA<DioException>());
      expect(
        (notifier.currentState.error as DioException).type,
        DioExceptionType.connectionTimeout,
      );

      notifier.dispose();
    });

    test('generic Exception is captured in state.error', () async {
      final error = Exception('generic failure');
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => throw error,
        options: const UseRequestOptions(manual: true),
      );

      try {
        await notifier.runAsync(1);
      } catch (_) {}

      expect(notifier.currentState.error, error);

      notifier.dispose();
    });

    test('onSuccess callback throwing does not prevent onFinally or cache write', () async {
      var finallyCalled = false;
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'result-$p',
        options: UseRequestOptions(
          manual: true,
          cacheKey: (p) => 'err-onsuccess-$p',
          onSuccess: (data, params) => throw Exception('onSuccess boom'),
          onFinally: (params, data, error) => finallyCalled = true,
        ),
      );

      await notifier.runAsync(1);

      expect(finallyCalled, true);
      // Cache should still be written
      final cached = RequestCache.get<String>('err-onsuccess-1');
      expect(cached?.data, 'result-1');

      notifier.dispose();
    });

    test('onError callback throwing does not prevent onFinally', () async {
      var finallyCalled = false;
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => throw Exception('service error'),
        options: UseRequestOptions(
          manual: true,
          onError: (error, params) => throw Exception('onError boom'),
          onFinally: (params, data, error) => finallyCalled = true,
        ),
      );

      try {
        await notifier.runAsync(1);
      } catch (_) {}

      expect(finallyCalled, true);

      notifier.dispose();
    });

    test('onFinally callback throwing does not propagate', () async {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'result-$p',
        options: UseRequestOptions(
          manual: true,
          onFinally: (params, data, error) => throw Exception('onFinally boom'),
        ),
      );

      // Should complete normally without propagating onFinally exception
      final result = await notifier.runAsync(1);
      expect(result, 'result-1');
      expect(notifier.currentState.data, 'result-1');

      notifier.dispose();
    });
  });
}
