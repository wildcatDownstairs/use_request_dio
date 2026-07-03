// P0 缺陷回归测试
//
// 覆盖四项已修复的严重缺陷：
// 1. 内联构造、未重写 == 的 defaultParams 导致自动请求无限循环
// 2. 配置 cacheKey 的请求失败时产生 Zone 未处理异步异常
// 3. cancel() 未真正取消传给 Dio 的 CancelToken
// 4. UseRequestBuilder 的 options 更新（ready / refreshDeps）不生效
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:use_request/use_request.dart';

/// 故意不重写 == / hashCode，模拟 HttpRequestConfig 等常见参数对象
class _NoEqualityParams {
  final int page;
  _NoEqualityParams(this.page);
}

void main() {
  setUp(clearAllCache);

  group('BUG-1 内联 defaultParams 自动请求循环', () {
    testWidgets('无 == 的参数对象内联构造时，自动请求只发一次', (tester) async {
      var callCount = 0;

      Future<String> service(_NoEqualityParams? p) async {
        callCount += 1;
        return 'data-${p?.page}';
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              // options 与 defaultParams 均在 build 中内联构造
              final result = useRequest<String, _NoEqualityParams?>(
                service,
                options: UseRequestOptions(defaultParams: _NoEqualityParams(1)),
              );
              return Text(result.data ?? 'loading');
            },
          ),
        ),
      );

      // 多跑几帧：若 effect 依赖 defaultParams，会在这里持续发请求
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(callCount, 1);
      expect(find.text('data-1'), findsOneWidget);
    });
  });

  group('BUG-2 pending 缓存的失败请求', () {
    test('失败的 pending 请求不产生未处理异步异常，且清理 pending 条目', () async {
      Object? unhandled;
      await runZonedGuarded(
        () async {
          final completer = Completer<String>();
          setPendingCache<String>('p0-bug2', completer.future);
          // 模拟 fetchData 中真正 await 该 future 的调用方
          unawaited(completer.future.then((_) {}, onError: (_) {}));
          completer.completeError(StateError('boom'));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        },
        (e, s) {
          unhandled = e;
        },
      );

      expect(unhandled, isNull);
      // 失败后 pending 条目应被清理
      expect(getPendingCache<String>('p0-bug2'), isNull);
    });

    test('成功的 pending 请求同样清理 pending 条目', () async {
      final completer = Completer<String>();
      setPendingCache<String>('p0-bug2-ok', completer.future);
      completer.complete('ok');
      await Future<void>.delayed(Duration.zero);
      expect(getPendingCache<String>('p0-bug2-ok'), isNull);
    });
  });

  group('BUG-3 cancel() 接通 Dio CancelToken', () {
    testWidgets('Hook 版：service 收到注入的 token，cancel() 会取消它', (tester) async {
      CancelToken? received;
      final gate = Completer<String>();
      late UseRequestResult<String, HttpRequestConfig> result;

      Future<String> service(HttpRequestConfig config) {
        received = config.cancelToken;
        return gate.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useRequest<String, HttpRequestConfig>(
                service,
                options: const UseRequestOptions(manual: true),
              );
              return Text(result.data ?? 'idle');
            },
          ),
        ),
      );

      result.run(HttpRequestConfig.get('/slow'));
      await tester.pump();

      expect(received, isNotNull, reason: '内部 token 应注入到 HttpRequestConfig');
      expect(received!.isCancelled, isFalse);

      result.cancel();
      expect(received!.isCancelled, isTrue);

      // 迟到的响应不应更新状态
      gate.complete('late');
      await tester.pump();
      expect(find.text('idle'), findsOneWidget);
    });

    testWidgets('Hook 版：显式 token 与 result.cancel() 都能取消请求', (tester) async {
      final userToken = CancelToken();
      CancelToken? received;
      late UseRequestResult<String, HttpRequestConfig> result;
      final gate = Completer<String>();

      Future<String> service(HttpRequestConfig config) {
        received = config.cancelToken;
        return gate.future;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useRequest<String, HttpRequestConfig>(
                service,
                options: const UseRequestOptions(manual: true),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      result.run(HttpRequestConfig(path: '/x', cancelToken: userToken));
      await tester.pump();

      expect(received, isNotNull);
      expect(identical(received, userToken), isFalse);

      result.cancel();
      expect(received!.isCancelled, isTrue);
      expect(userToken.isCancelled, isFalse, reason: '内部取消不应让外部 token 永久失效');

      gate.complete('late');
      await tester.pump();
    });

    testWidgets('Hook 版：显式 token 主动取消会传递到内部 token', (tester) async {
      final userToken = CancelToken();
      CancelToken? received;
      final gate = Completer<String>();
      late UseRequestResult<String, HttpRequestConfig> result;

      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useRequest<String, HttpRequestConfig>((config) {
                received = config.cancelToken;
                return gate.future;
              }, options: const UseRequestOptions(manual: true));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      result.run(HttpRequestConfig(path: '/x', cancelToken: userToken));
      await tester.pump();

      userToken.cancel('external');
      await tester.pump();
      expect(received!.isCancelled, isTrue);

      gate.complete('late');
      await tester.pump();
    });

    test('Riverpod 版：notifier.cancel() 取消注入的 token，迟到结果不进状态', () async {
      CancelToken? received;
      final gate = Completer<String>();

      final notifier = UseRequestNotifier<String, HttpRequestConfig>(
        service: (config) {
          received = config.cancelToken;
          return gate.future;
        },
        options: const UseRequestOptions(manual: true),
      );

      notifier.run(HttpRequestConfig.get('/slow'));
      await Future<void>.delayed(Duration.zero);

      expect(received, isNotNull);
      notifier.cancel();
      expect(received!.isCancelled, isTrue);

      gate.complete('late');
      await Future<void>.delayed(Duration.zero);
      expect(notifier.currentState.data, isNull);

      notifier.dispose();
    });

    test('相同 cacheKey 的并发调用复用 pending 时不会取消底层请求', () async {
      var callCount = 0;
      CancelToken? received;
      final gate = Completer<String>();
      final notifier = UseRequestNotifier<String, HttpRequestConfig>(
        service: (config) {
          callCount++;
          received = config.cancelToken;
          return gate.future;
        },
        options: UseRequestOptions(
          manual: true,
          cacheKey: (config) => config.path,
        ),
      );

      final first = notifier.runAsync(HttpRequestConfig.get('/same'));
      await Future<void>.delayed(Duration.zero);
      final second = notifier.runAsync(HttpRequestConfig.get('/same'));
      await Future<void>.delayed(Duration.zero);

      expect(callCount, 1);
      expect(received!.isCancelled, isFalse);

      gate.complete('ok');
      expect(await first, 'ok');
      expect(await second, 'ok');
      notifier.dispose();
    });
  });

  group('BUG-4 UseRequestBuilder 的 options 更新传播', () {
    testWidgets('通过 options 切换 ready 生效', (tester) async {
      var callCount = 0;
      Future<String> service(int v) async {
        callCount += 1;
        return 'R$v';
      }

      Widget build(bool ready) => ProviderScope(
        child: MaterialApp(
          home: UseRequestBuilder<String, int>(
            service: service,
            options: UseRequestOptions(defaultParams: 1, ready: ready),
            builder: (context, state, notifier) => Text(state.data ?? 'idle'),
          ),
        ),
      );

      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(callCount, 0);
      expect(find.text('idle'), findsOneWidget);

      await tester.pumpWidget(build(true));
      await tester.pump();
      expect(callCount, 1);
      expect(find.text('R1'), findsOneWidget);

      // ready 再切回 false 不应触发新请求
      await tester.pumpWidget(build(false));
      await tester.pump();
      expect(callCount, 1);
    });

    testWidgets('通过 options 变更 refreshDeps 触发刷新，未变更不触发', (tester) async {
      var callCount = 0;
      Future<String> service(int v) async {
        callCount += 1;
        return 'D$v-$callCount';
      }

      Widget build(int dep) => ProviderScope(
        child: MaterialApp(
          home: UseRequestBuilder<String, int>(
            service: service,
            options: UseRequestOptions(defaultParams: 1, refreshDeps: [dep]),
            builder: (context, state, notifier) => Text(state.data ?? 'idle'),
          ),
        ),
      );

      await tester.pumpWidget(build(1));
      await tester.pump();
      expect(callCount, 1);

      // deps 未变化（新 List 实例、相同内容）：不触发
      await tester.pumpWidget(build(1));
      await tester.pump();
      expect(callCount, 1);

      // deps 变化：触发一次刷新
      await tester.pumpWidget(build(2));
      await tester.pump();
      expect(callCount, 2);
      expect(find.text('D1-2'), findsOneWidget);
    });
  });
}
