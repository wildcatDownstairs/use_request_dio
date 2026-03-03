import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);

  group('UseRequestOptions equality', () {
    test('same scalar values with different function refs are equal', () {
      final a = UseRequestOptions<String, int>(
        manual: true,
        pollingInterval: const Duration(seconds: 5),
        onSuccess: (data, params) {},
        onError: (error, params) {},
      );
      final b = UseRequestOptions<String, int>(
        manual: true,
        pollingInterval: const Duration(seconds: 5),
        onSuccess: (data, params) {
          /* different closure */
        },
        onError: (error, params) {
          /* different closure */
        },
      );
      expect(a, equals(b));
    });

    test('different manual/ready/pollingInterval are not equal', () {
      const a = UseRequestOptions<String, int>(
        manual: true,
        ready: true,
        pollingInterval: Duration(seconds: 5),
      );
      const b = UseRequestOptions<String, int>(
        manual: false,
        ready: true,
        pollingInterval: Duration(seconds: 5),
      );
      const c = UseRequestOptions<String, int>(
        manual: true,
        ready: false,
        pollingInterval: Duration(seconds: 5),
      );
      const d = UseRequestOptions<String, int>(
        manual: true,
        ready: true,
        pollingInterval: Duration(seconds: 10),
      );
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('hashCode is consistent with equality', () {
      final a = UseRequestOptions<String, int>(
        manual: true,
        retryCount: 3,
        cacheTime: const Duration(minutes: 5),
        onSuccess: (data, params) {},
      );
      final b = UseRequestOptions<String, int>(
        manual: true,
        retryCount: 3,
        cacheTime: const Duration(minutes: 5),
        onError: (error, params) {},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('copyWith preserves equality for unchanged fields', () {
      const original = UseRequestOptions<String, int>(
        manual: true,
        pollingInterval: Duration(seconds: 5),
        retryCount: 3,
      );
      // copyWith with no changes should produce an equal object
      final copied = original.copyWith();
      expect(copied, equals(original));
    });

    test('copyWith with initialData and keepPreviousData', () {
      const original = UseRequestOptions<String, int>(
        initialData: 'hello',
        keepPreviousData: false,
      );
      final updated = original.copyWith(
        initialData: 'world',
        keepPreviousData: true,
      );
      expect(updated.initialData, 'world');
      expect(updated.keepPreviousData, true);
      // Scalar keepPreviousData changed, so they are no longer equal
      expect(original, isNot(equals(updated)));
    });
  });
}
