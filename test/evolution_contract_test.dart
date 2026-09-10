import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:use_request/use_request.dart';

class _HookPollingProbe extends HookWidget {
  const _HookPollingProbe();

  @override
  Widget build(BuildContext context) {
    final request = useRequestFn(
      () async => 'done',
      options: const UseRequestOptions(
        pollingInterval: Duration(minutes: 1),
        pollingWhenHidden: false,
      ),
    );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(request.isPolling.toString()),
    );
  }
}

void main() {
  setUp(clearAllCache);

  for (final mutatePending in [false, true]) {
    test(
      'shared loadMore merges once with pending mutate=$mutatePending',
      () async {
        final pending = Completer<List<int>>();
        var calls = 0;
        final options = UseRequestOptions<List<int>, int>(
          manual: true,
          defaultParams: 1,
          initialData: [1],
          cacheKey: (page) => 'page-$page',
          dataMerger: (old, next) => [...?old, ...next],
        );
        final first = UseRequestNotifier<List<int>, int>(
          service: (_) {
            calls++;
            return pending.future;
          },
          options: options,
        );
        final second = UseRequestNotifier<List<int>, int>(
          service: (_) {
            calls++;
            return pending.future;
          },
          options: options,
        );
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        final a = first.runAsync(2, isLoadMore: true);
        final b = second.runAsync(2, isLoadMore: true);
        if (mutatePending) first.mutate((_) => [1, 9]);
        pending.complete([2]);
        await Future.wait([a, b]);
        final expected = mutatePending ? [1, 9, 2] : [1, 2];
        expect(calls, 1);
        expect(first.currentState.data, expected);
        expect(second.currentState.data, expected);
        expect(getCache<List<int>>('page-2')?.data, expected);
      },
    );
  }

  test('same cacheKey syncs mutate and clear across mounted instances', () {
    final options = UseRequestOptions<String, int>(
      manual: true,
      defaultParams: 1,
      cacheKey: (value) => 'item-$value',
    );
    final first = UseRequestNotifier<String, int>(
      service: (value) async => 'network-$value',
      options: options,
    );
    final second = UseRequestNotifier<String, int>(
      service: (value) async => 'network-$value',
      options: options,
    );

    first.mutate((_) => 'local');
    expect(second.state.data, 'local');

    first.mutate((_) => null);
    expect(second.state.data, isNull);

    first.dispose();
    second.dispose();
  });

  test('cache subscription follows the active key', () async {
    final options = UseRequestOptions<String, int>(
      manual: true,
      defaultParams: 1,
      cacheKey: (value) => 'item-$value',
    );
    final first = UseRequestNotifier<String, int>(
      service: (value) async => 'network-$value',
      options: options,
    );
    final second = UseRequestNotifier<String, int>(
      service: (value) async => 'network-$value',
      options: options,
    );

    await second.runAsync(2);
    first.mutate((_) => 'item-1-mutated');

    expect(second.state.data, 'network-2');
    first.dispose();
    second.dispose();
  });

  test(
    'mutate sync keeps another instance loading while request is pending',
    () {
      final pending = Completer<String>();
      final options = UseRequestOptions<String, int>(
        manual: true,
        defaultParams: 1,
        cacheKey: (value) => 'item-$value',
      );
      final first = UseRequestNotifier<String, int>(
        service: (_) => pending.future,
        options: options,
      );
      final second = UseRequestNotifier<String, int>(
        service: (_) => pending.future,
        options: options,
      );

      second.run(1);
      expect(second.state.loading, isTrue);
      first.mutate((_) => 'optimistic');
      expect(second.state.data, 'optimistic');
      expect(second.state.loading, isTrue);

      first.dispose();
      second.dispose();
    },
  );

  test('mutating data to null keeps the pending request active', () async {
    final pending = Completer<String>();
    final notifier = UseRequestNotifier<String, int>(
      service: (_) => pending.future,
      options: UseRequestOptions(
        manual: true,
        cacheKey: (_) => 'nullable-mutation',
      ),
    );

    final future = notifier.runAsync(1);
    notifier.mutate((_) => null);

    expect(notifier.currentState.loading, isTrue);
    expect(getPendingCache<String>('nullable-mutation'), isNotNull);
    pending.complete('done');
    expect(await future, 'done');
    notifier.dispose();
  });

  test(
    'clearing cache prevents a late pending result from refilling it',
    () async {
      final pending = Completer<String>();
      final notifier = UseRequestNotifier<String, int>(
        service: (_) => pending.future,
        options: UseRequestOptions(
          manual: true,
          cacheKey: (value) => 'item-$value',
        ),
      );

      final future = notifier.runAsync(1);
      clearCacheEntry('item-1');
      pending.complete('late');

      expect(await future, 'late');
      expect(notifier.state.data, isNull);
      expect(getCache<String>('item-1'), isNull);
      notifier.dispose();
    },
  );

  testWidgets('clearing cache cancels delayed loading', (tester) async {
    final pending = Completer<String>();
    final notifier = UseRequestNotifier<String, int>(
      service: (_) => pending.future,
      options: UseRequestOptions(
        manual: true,
        cacheKey: (_) => 'delayed-loading',
        loadingDelay: const Duration(milliseconds: 20),
      ),
    );

    final future = notifier.runAsync(1);
    clearCacheEntry('delayed-loading');
    await tester.pump(const Duration(milliseconds: 30));

    expect(notifier.currentState.loading, isFalse);
    pending.complete('done');
    expect(await future, 'done');
    notifier.dispose();
  });

  test('ready turning false suppresses a same-frame deps request', () async {
    var calls = 0;
    final notifier = UseRequestNotifier<String, int>(
      service: (_) async {
        calls++;
        return 'done';
      },
      options: const UseRequestOptions(defaultParams: 1, refreshDeps: [0]),
    );
    await Future<void>.delayed(Duration.zero);

    notifier.updateOptions(
      const UseRequestOptions(defaultParams: 1, ready: false, refreshDeps: [1]),
    );

    expect(calls, 1);
    notifier.dispose();
  });

  test('custom shouldRetry supports ordinary Future errors', () async {
    var attempts = 0;
    final notifier = UseRequestNotifier<String, int>(
      service: (_) async {
        attempts++;
        if (attempts < 3) throw StateError('temporary');
        return 'done';
      },
      options: UseRequestOptions(
        manual: true,
        retryCount: 2,
        retryInterval: Duration.zero,
        shouldRetry: (error) => error is StateError,
      ),
    );

    expect(await notifier.runAsync(1), 'done');
    expect(attempts, 3);
    notifier.dispose();
  });

  test('custom shouldRetry cannot retry Dio cancellation', () async {
    var attempts = 0;
    final notifier = UseRequestNotifier<String, int>(
      service: (_) async {
        attempts++;
        throw DioException(
          requestOptions: RequestOptions(path: '/cancelled'),
          type: DioExceptionType.cancel,
        );
      },
      options: UseRequestOptions(
        manual: true,
        retryCount: 2,
        retryInterval: Duration.zero,
        shouldRetry: (_) => true,
      ),
    );

    await expectLater(notifier.runAsync(1), throwsA(isA<DioException>()));
    expect(attempts, 1);
    notifier.dispose();
  });

  test('last cached consumer cancel stops ordinary Future retry', () async {
    var attempts = 0;
    final notifier = UseRequestNotifier<String, int>(
      service: (_) async {
        attempts++;
        throw StateError('temporary');
      },
      options: UseRequestOptions(
        manual: true,
        cacheKey: (_) => 'ordinary-retry',
        retryCount: 1,
        retryInterval: const Duration(milliseconds: 20),
        shouldRetry: (_) => true,
      ),
    );

    notifier.run(1);
    await Future<void>.delayed(Duration.zero);
    notifier.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(attempts, 1);
    notifier.dispose();
  });

  test(
    'disposing one shared Dio consumer keeps the source token alive',
    () async {
      final pending = Completer<String>();
      CancelToken? sourceToken;
      Future<String> service(HttpRequestConfig config) {
        sourceToken ??= config.cancelToken;
        return pending.future;
      }

      final options = UseRequestOptions<String, HttpRequestConfig>(
        manual: true,
        cacheKey: (_) => 'shared-dio',
      );
      final first = UseRequestNotifier<String, HttpRequestConfig>(
        service: service,
        options: options,
      );
      final second = UseRequestNotifier<String, HttpRequestConfig>(
        service: service,
        options: options,
      );
      const params = HttpRequestConfig(path: '/shared');

      final firstFuture = first.runAsync(params);
      final secondFuture = second.runAsync(params);
      first.dispose();

      expect(sourceToken?.isCancelled, isFalse);
      pending.complete('done');
      expect(await firstFuture, 'done');
      expect(await secondFuture, 'done');
      expect(second.state.data, 'done');
      second.dispose();
    },
  );

  test('pending mutate keeps Dio ownership until every consumer exits', () {
    final pending = Completer<String>();
    CancelToken? sourceToken;
    Future<String> service(HttpRequestConfig config) {
      sourceToken ??= config.cancelToken;
      return pending.future;
    }

    final options = UseRequestOptions<String, HttpRequestConfig>(
      manual: true,
      cacheKey: (_) => 'shared-dio-mutate',
    );
    final first = UseRequestNotifier<String, HttpRequestConfig>(
      service: service,
      options: options,
    );
    final second = UseRequestNotifier<String, HttpRequestConfig>(
      service: service,
      options: options,
    );
    const params = HttpRequestConfig(path: '/shared');

    first.run(params);
    second.run(params);
    first.mutate((_) => 'optimistic');
    first.dispose();
    expect(sourceToken?.isCancelled, isFalse);

    second.dispose();
    expect(sourceToken?.isCancelled, isTrue);
  });

  testWidgets('focus cooldown does not suppress polling resume', (
    tester,
  ) async {
    var calls = 0;
    final notifier = UseRequestNotifier<String, Null>(
      service: (_) async => 'v${++calls}',
      options: const UseRequestOptions(
        pollingInterval: Duration(minutes: 1),
        pollingWhenHidden: false,
        refreshOnFocus: true,
        focusTimespan: Duration(minutes: 1),
      ),
    );
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(notifier.isPolling, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final afterFirstFocus = calls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, afterFirstFocus);
    expect(notifier.isPolling, isTrue);
    notifier.dispose();
  });

  testWidgets('hook isPolling follows background pause and focus resume', (
    tester,
  ) async {
    await tester.pumpWidget(const _HookPollingProbe());
    await tester.pump();
    expect(find.text('true'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.scheduleForcedFrame();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('false'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('true'), findsOneWidget);
  });
}
