import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);

  group('State transitions', () {
    test('initial state: loading=false, data=null, error=null', () {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'result-$p',
        options: const UseRequestOptions(manual: true),
      );

      expect(notifier.currentState.loading, false);
      expect(notifier.currentState.data, isNull);
      expect(notifier.currentState.error, isNull);

      notifier.dispose();
    });

    test('after run: loading=true → success: loading=false, data=result, error=null', () async {
      final completer = Completer<String>();
      final notifier = UseRequestNotifier<String, int>(
        service: (p) => completer.future,
        options: const UseRequestOptions(manual: true),
      );

      final future = notifier.runAsync(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.currentState.loading, true);

      completer.complete('success');
      await future;

      expect(notifier.currentState.loading, false);
      expect(notifier.currentState.data, 'success');
      expect(notifier.currentState.error, isNull);

      notifier.dispose();
    });

    test('after failed run: loading=true → error: loading=false, data=null, error=exception', () async {
      final completer = Completer<String>();
      final notifier = UseRequestNotifier<String, int>(
        service: (p) => completer.future,
        options: const UseRequestOptions(manual: true),
      );

      final future = notifier.runAsync(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.currentState.loading, true);

      final error = Exception('failure');
      completer.completeError(error);

      try {
        await future;
      } catch (_) {}

      expect(notifier.currentState.loading, false);
      expect(notifier.currentState.data, isNull);
      expect(notifier.currentState.error, error);

      notifier.dispose();
    });

    test('after error then successful refresh: error clears, data updates', () async {
      var shouldFail = true;
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async {
          if (shouldFail) throw Exception('fail');
          return 'refreshed-$p';
        },
        options: const UseRequestOptions(manual: true),
      );

      try {
        await notifier.runAsync(1);
      } catch (_) {}

      expect(notifier.currentState.error, isA<Exception>());

      shouldFail = false;
      await notifier.refreshAsync();

      expect(notifier.currentState.error, isNull);
      expect(notifier.currentState.data, 'refreshed-1');

      notifier.dispose();
    });

    test('cancel during request: loading=false', () async {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return 'result-$p';
        },
        options: const UseRequestOptions(manual: true),
      );

      notifier.run(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.currentState.loading, true);

      notifier.cancel();

      expect(notifier.currentState.loading, false);

      notifier.dispose();
    });

    test('initialData: initial state has data=initialData', () {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'result-$p',
        options: const UseRequestOptions(
          manual: true,
          initialData: 'initial',
        ),
      );

      expect(notifier.currentState.data, 'initial');
      expect(notifier.currentState.loading, false);

      notifier.dispose();
    });

    test('mutate updates data and syncs to cache', () async {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'result-$p',
        options: UseRequestOptions(
          manual: true,
          cacheKey: (p) => 'mutate-test-$p',
        ),
      );

      await notifier.runAsync(5);
      expect(notifier.currentState.data, 'result-5');

      notifier.mutate((old) => 'mutated-value');
      expect(notifier.currentState.data, 'mutated-value');

      // Verify cache was updated
      final cached = RequestCache.get<String>('mutate-test-5');
      expect(cached?.data, 'mutated-value');

      notifier.dispose();
    });

    test('loadMore: loadingMore=true during request, loading stays false', () async {
      final completer = Completer<List<int>>();
      final notifier = UseRequestNotifier<List<int>, int>(
        service: (p) {
          if (p == 1) return Future.value([1, 2, 3]);
          return completer.future;
        },
        options: UseRequestOptions(
          manual: true,
          loadMoreParams: (lastParams, data) => lastParams + 1,
          dataMerger: (prev, next) => [...?prev, ...next],
          hasMore: (data) => true,
        ),
      );

      // First request
      await notifier.runAsync(1);
      expect(notifier.currentState.data, [1, 2, 3]);

      // Load more
      final loadFuture = notifier.loadMoreAsync();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.currentState.loadingMore, true);
      expect(notifier.currentState.loading, false);

      completer.complete([4, 5, 6]);
      await loadFuture;

      expect(notifier.currentState.loadingMore, false);
      expect(notifier.currentState.data, [1, 2, 3, 4, 5, 6]);

      notifier.dispose();
    });
  });
}
