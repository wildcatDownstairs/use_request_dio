import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);

  group('Debouncer contract', () {
    test('maxWait forces execution during continuous calls', () async {
      final stopwatch = Stopwatch()..start();
      var callCount = 0;
      final debouncer = Debouncer<int>(
        duration: const Duration(milliseconds: 120),
        maxWait: const Duration(milliseconds: 180),
      );

      final first = debouncer.call(() async {
        callCount += 1;
        return stopwatch.elapsedMilliseconds;
      });
      final firstCancelled = expectLater(
        first,
        throwsA(isA<DebounceCancelledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      final second = debouncer.call(() async {
        callCount += 1;
        return stopwatch.elapsedMilliseconds;
      });
      final secondCancelled = expectLater(
        second,
        throwsA(isA<DebounceCancelledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      final third = debouncer.call(() async {
        callCount += 1;
        return stopwatch.elapsedMilliseconds;
      });

      await firstCancelled;
      await secondCancelled;
      final elapsed = await third;
      expect(callCount, 1);
      expect(elapsed, greaterThanOrEqualTo(150));
      expect(elapsed, lessThan(260));
    });

    test(
      'later calls do not cancel an already running leading future',
      () async {
        final releaseFirst = Completer<void>();
        final firstStarted = Completer<void>();
        final debouncer = Debouncer<String>(
          duration: const Duration(milliseconds: 80),
          leading: true,
          trailing: true,
        );

        final first = debouncer.call(() async {
          firstStarted.complete();
          await releaseFirst.future;
          return 'first';
        });

        await firstStarted.future;

        final second = debouncer.call(() async => 'second');

        await Future<void>.delayed(const Duration(milliseconds: 100));
        releaseFirst.complete();

        expect(await first, 'first');
        expect(await second, 'second');
      },
    );

    test(
      'leading without trailing can start a new cycle after duration',
      () async {
        final debouncer = Debouncer<String>(
          duration: const Duration(milliseconds: 60),
          leading: true,
          trailing: false,
        );

        expect(await debouncer.call(() async => 'first'), 'first');

        await expectLater(
          debouncer.call(() async => 'second'),
          throwsA(isA<DebounceCancelledException>()),
        );

        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(await debouncer.call(() async => 'third'), 'third');
      },
    );
  });

  group('Throttler contract', () {
    test(
      'leading=false delays the first execution until the throttle window ends',
      () async {
        final stopwatch = Stopwatch()..start();
        var callCount = 0;
        final throttler = Throttler<int>(
          duration: const Duration(milliseconds: 80),
          leading: false,
          trailing: true,
        );

        final future = throttler.call(() async {
          callCount += 1;
          return stopwatch.elapsedMilliseconds;
        });

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(callCount, 0);

        final elapsed = await future;
        expect(callCount, 1);
        expect(elapsed, greaterThanOrEqualTo(70));
      },
    );

    test('trailing resolves with the latest queued action', () async {
      final throttler = Throttler<String>(
        duration: const Duration(milliseconds: 80),
      );
      final executed = <String>[];

      final first = throttler.call(() async {
        executed.add('A');
        return 'A';
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = throttler.call(() async {
        executed.add('B');
        return 'B';
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final third = throttler.call(() async {
        executed.add('C');
        return 'C';
      });

      expect(await first, 'A');
      expect(await second, 'C');
      expect(await third, 'C');
      expect(executed, <String>['A', 'C']);
    });

    test(
      'maxWait prevents trailing calls from being deferred forever',
      () async {
        final stopwatch = Stopwatch()..start();
        var callCount = 0;
        final throttler = Throttler<int>(
          duration: const Duration(milliseconds: 160),
          leading: false,
          trailing: true,
          maxWait: const Duration(milliseconds: 90),
        );

        final first = throttler.call(() async {
          callCount += 1;
          return stopwatch.elapsedMilliseconds;
        });

        await Future<void>.delayed(const Duration(milliseconds: 40));
        final second = throttler.call(() async {
          callCount += 1;
          return stopwatch.elapsedMilliseconds;
        });

        await Future<void>.delayed(const Duration(milliseconds: 40));
        final third = throttler.call(() async {
          callCount += 1;
          return stopwatch.elapsedMilliseconds;
        });

        final elapsed = await third;
        expect(await first, elapsed);
        expect(await second, elapsed);
        expect(callCount, 1);
        expect(elapsed, lessThan(140));
      },
    );
  });

  group('Retry contract', () {
    test('cancel stops retry backoff immediately', () async {
      final stopwatch = Stopwatch()..start();
      final executor = RetryExecutor<void>(
        config: const RetryConfig(
          maxRetries: 3,
          retryInterval: Duration(milliseconds: 180),
        ),
      );
      var attempts = 0;

      final future = executor.execute(() async {
        attempts += 1;
        throw DioException(
          requestOptions: RequestOptions(path: '/retry'),
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      executor.cancel();

      await expectLater(future, throwsA(isA<RetryCancelledException>()));
      expect(attempts, 1);
      expect(stopwatch.elapsedMilliseconds, lessThan(160));
    });

    test('external cancelToken also interrupts retry backoff', () async {
      final stopwatch = Stopwatch()..start();
      final cancelToken = CancelToken();
      final executor = RetryExecutor<void>(
        config: const RetryConfig(
          maxRetries: 3,
          retryInterval: Duration(milliseconds: 180),
        ),
      );
      var attempts = 0;

      final future = executor.execute(() async {
        attempts += 1;
        throw DioException(
          requestOptions: RequestOptions(path: '/retry'),
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      }, cancelToken: cancelToken);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      cancelToken.cancel('user cancelled');

      await expectLater(future, throwsA(isA<RetryCancelledException>()));
      expect(attempts, 1);
      expect(stopwatch.elapsedMilliseconds, lessThan(160));
    });
  });

  group('Cache and options contract', () {
    test('pending cache overwrite keeps the newest in-flight future', () async {
      final firstCompleter = Completer<String>();
      final secondCompleter = Completer<String>();

      setPendingCache<String>('same-key', firstCompleter.future);
      setPendingCache<String>('same-key', secondCompleter.future);

      firstCompleter.complete('first');
      await Future<void>.delayed(Duration.zero);

      expect(getPendingCache<String>('same-key'), same(secondCompleter.future));

      secondCompleter.complete('second');
      await Future<void>.delayed(Duration.zero);

      expect(getPendingCache<String>('same-key'), isNull);
    });

    test('UseRequestOptions.copyWith can explicitly clear nullable fields', () {
      final cancelToken = CancelToken();
      final reconnectStream = Stream<bool>.empty();
      final options = UseRequestOptions<String, int>(
        defaultParams: 1,
        refreshDeps: const [1],
        refreshDepsAction: () {},
        cacheTime: const Duration(minutes: 5),
        staleTime: const Duration(minutes: 1),
        reconnectStream: reconnectStream,
        cancelToken: cancelToken,
        fetchKey: (value) => 'fetch-$value',
      );

      final cleared = options.copyWith(
        defaultParams: null,
        refreshDeps: null,
        refreshDepsAction: null,
        cacheTime: null,
        staleTime: null,
        reconnectStream: null,
        cancelToken: null,
        fetchKey: null,
      );

      expect(cleared.defaultParams, isNull);
      expect(cleared.refreshDeps, isNull);
      expect(cleared.refreshDepsAction, isNull);
      expect(cleared.cacheTime, isNull);
      expect(cleared.staleTime, isNull);
      expect(cleared.reconnectStream, isNull);
      expect(cleared.cancelToken, isNull);
      expect(cleared.fetchKey, isNull);
    });
  });
}
