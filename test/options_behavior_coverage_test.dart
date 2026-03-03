import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

class _PollingVisibilityProbe extends HookWidget {
  const _PollingVisibilityProbe({
    required this.service,
    required this.pollingWhenHidden,
  });

  final Future<String> Function() service;
  final bool pollingWhenHidden;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, dynamic>(
      (_) => service(),
      options: UseRequestOptions(
        pollingInterval: const Duration(milliseconds: 20),
        pollingWhenHidden: pollingWhenHidden,
      ),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${request.loading}|${request.data ?? 'null'}'),
    );
  }
}

class _LoadingDelayProbe extends HookWidget {
  const _LoadingDelayProbe({required this.service, required this.delay});

  final Future<String> Function(int) service;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int>(
      service,
      options: UseRequestOptions(
        manual: false,
        defaultParams: 1,
        loadingDelay: delay,
      ),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${request.loading}|${request.data ?? 'null'}'),
    );
  }
}

class _TimeoutHookProbe extends HookWidget {
  const _TimeoutHookProbe({required this.onSeen});

  final void Function(HttpRequestConfig config) onSeen;

  @override
  Widget build(BuildContext context) {
    useRequest<String, HttpRequestConfig>(
      (config) async {
        onSeen(config);
        return 'ok';
      },
      options: UseRequestOptions(
        manual: false,
        defaultParams: HttpRequestConfig.get('/hook-timeout-default'),
        connectTimeout: const Duration(milliseconds: 111),
        receiveTimeout: const Duration(milliseconds: 222),
        sendTimeout: const Duration(milliseconds: 333),
      ),
    );

    return const Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.shrink(),
    );
  }
}

DioException _retryableError() {
  return DioException(
    requestOptions: RequestOptions(path: '/retry'),
    type: DioExceptionType.connectionError,
    error: 'offline',
  );
}

void main() {
  setUp(clearAllCache);

  group('UseRequestOptions behavior coverage', () {
    testWidgets('pollingWhenHidden=false pauses polling while app is paused', (
      tester,
    ) async {
      var callCount = 0;

      Future<String> service() async {
        callCount += 1;
        return 'v$callCount';
      }

      await tester.pumpWidget(
        _PollingVisibilityProbe(service: service, pollingWhenHidden: false),
      );
      await tester.pump();

      expect(callCount, greaterThanOrEqualTo(1));
      final beforePause = callCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 90));
      await tester.pump();

      expect(callCount, beforePause);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(callCount, greaterThan(beforePause));
    });

    testWidgets('loadingDelay delays loading=true before delay threshold', (
      tester,
    ) async {
      final completer = Completer<String>();

      await tester.pumpWidget(
        _LoadingDelayProbe(
          service: (_) => completer.future,
          delay: const Duration(milliseconds: 80),
        ),
      );

      await tester.pump();
      expect(find.text('false|null'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('false|null'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('true|null'), findsOneWidget);

      completer.complete('done');
      await tester.pump();
      await tester.pump();
      expect(find.text('false|done'), findsOneWidget);
    });

    testWidgets('hook applies timeout defaults to HttpRequestConfig params', (
      tester,
    ) async {
      HttpRequestConfig? seen;

      await tester.pumpWidget(
        _TimeoutHookProbe(
          onSeen: (config) {
            seen = config;
          },
        ),
      );
      await tester.pump();

      expect(seen, isNotNull);
      expect(seen!.connectTimeout, const Duration(milliseconds: 111));
      expect(seen!.receiveTimeout, const Duration(milliseconds: 222));
      expect(seen!.sendTimeout, const Duration(milliseconds: 333));
    });

    test('debounceLeading/debounceTrailing affects notifier run behavior', () async {
      final calls = <int>[];
      final notifier = UseRequestNotifier<String, int>(
        service: (value) async {
          calls.add(value);
          return 'v$value';
        },
        options: const UseRequestOptions(
          manual: true,
          debounceInterval: Duration(milliseconds: 60),
          debounceLeading: true,
          debounceTrailing: false,
        ),
      );

      final first = await notifier.runAsync(1);
      expect(first, 'v1');

      await expectLater(
        notifier.runAsync(2),
        throwsA(isA<DebounceCancelledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final third = await notifier.runAsync(3);

      expect(third, 'v3');
      expect(calls, <int>[1, 3]);
      notifier.dispose();
    });

    test('debounceMaxWait forces execution during burst calls', () async {
      final calls = <int>[];
      final notifier = UseRequestNotifier<String, int>(
        service: (value) async {
          calls.add(value);
          return 'v$value';
        },
        options: const UseRequestOptions(
          manual: true,
          debounceInterval: Duration(milliseconds: 120),
          debounceMaxWait: Duration(milliseconds: 180),
        ),
      );

      final firstCancelled = expectLater(
        notifier.runAsync(1),
        throwsA(isA<DebounceCancelledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      final secondCancelled = expectLater(
        notifier.runAsync(2),
        throwsA(isA<DebounceCancelledException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      final third = notifier.runAsync(3);

      await firstCancelled;
      await secondCancelled;
      final result = await third;

      expect(result, 'v3');
      expect(calls, <int>[3]);
      notifier.dispose();
    });

    test('throttleInterval with leading=false delays first execution', () async {
      final calls = <int>[];
      final notifier = UseRequestNotifier<String, int>(
        service: (value) async {
          calls.add(value);
          return 'v$value';
        },
        options: const UseRequestOptions(
          manual: true,
          throttleInterval: Duration(milliseconds: 70),
          throttleLeading: false,
          throttleTrailing: true,
        ),
      );

      final future = notifier.runAsync(7);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, isEmpty);

      final result = await future;
      expect(result, 'v7');
      expect(calls, <int>[7]);
      notifier.dispose();
    });

    test('pausePollingOnError + pollingRetryInterval pauses then resumes', () async {
      var calls = 0;
      final notifier = UseRequestNotifier<String, int>(
        service: (_) async {
          calls += 1;
          if (calls == 2) {
            throw _retryableError();
          }
          return 'ok-$calls';
        },
        options: const UseRequestOptions(
          manual: false,
          defaultParams: 1,
          pollingInterval: Duration(milliseconds: 25),
          pausePollingOnError: true,
          pollingRetryInterval: Duration(milliseconds: 50),
        ),
      );

      // Wait for the second (polling) call to happen and fail.
      for (var i = 0; i < 20 && calls < 2; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(calls, greaterThanOrEqualTo(2));

      final afterError = calls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, afterError);

      for (var i = 0; i < 25 && calls <= afterError; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(calls, greaterThan(afterError));

      notifier.dispose();
    });

    test('retryExponential=false and onRetryAttempt callbacks are honored', () async {
      final attempts = <int>[];
      final ticks = <int>[];
      final stopwatch = Stopwatch()..start();
      var runCount = 0;

      final notifier = UseRequestNotifier<String, int>(
        service: (_) async {
          runCount += 1;
          ticks.add(stopwatch.elapsedMilliseconds);
          if (runCount <= 3) {
            throw _retryableError();
          }
          return 'ok';
        },
        options: UseRequestOptions(
          manual: true,
          retryCount: 3,
          retryInterval: const Duration(milliseconds: 35),
          retryExponential: false,
          onRetryAttempt: (attempt, error) {
            attempts.add(attempt);
          },
        ),
      );

      final result = await notifier.runAsync(1);
      expect(result, 'ok');
      expect(attempts, <int>[1, 2, 3]);

      expect(ticks.length, 4);
      final delta1 = ticks[1] - ticks[0];
      final delta2 = ticks[2] - ticks[1];
      expect(delta1, greaterThanOrEqualTo(20));
      expect(delta2, greaterThanOrEqualTo(20));

      notifier.dispose();
    });

    test('riverpod applies timeout defaults to HttpRequestConfig params', () async {
      HttpRequestConfig? seen;
      final notifier = UseRequestNotifier<String, HttpRequestConfig>(
        service: (config) async {
          seen = config;
          return 'ok';
        },
        options: UseRequestOptions(
          manual: true,
          connectTimeout: const Duration(milliseconds: 444),
          receiveTimeout: const Duration(milliseconds: 555),
          sendTimeout: const Duration(milliseconds: 666),
        ),
      );

      await notifier.runAsync(HttpRequestConfig.get('/riverpod-timeout-default'));

      expect(seen, isNotNull);
      expect(seen!.connectTimeout, const Duration(milliseconds: 444));
      expect(seen!.receiveTimeout, const Duration(milliseconds: 555));
      expect(seen!.sendTimeout, const Duration(milliseconds: 666));

      notifier.dispose();
    });
  });
}
