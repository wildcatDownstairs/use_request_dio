// P1/P2 缺陷回归测试
//
// 覆盖以下已修复缺陷：
// BUG-5  refreshDeps 刷新应优先使用最近一次请求参数（对齐 ahooks refresh 语义）
// BUG-6  refresh()/loadMore() 在从未请求过时不得同步抛出
// BUG-7  cancel() 应取消排队中的防抖调用
// BUG-8  请求失败不清除仍在有效期内的缓存（SWR 语义）
// BUG-9  轮询回调应使用最新一帧的 options（stale closure）
// BUG-10 Throttler maxWait 立即执行分支不得双重执行排队中的 trailing
// BUG-11 TData 可空时 service 返回 null 应清空 data 而非保留旧值
// BUG-12 fresh 缓存命中时观察者 onRequest/onFinally 应配对
// BUG-13 HttpRequestConfig 值语义相等
// BUG-17 isPolling 派生自轮询控制器真实状态
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:use_request/use_request.dart';

class _CountingObserver extends UseRequestObserver {
  int requests = 0;
  int finallys = 0;

  @override
  void onRequest(String key, Object? params) => requests++;

  @override
  void onFinally(String key, Object? params) => finallys++;
}

void main() {
  setUp(clearAllCache);
  tearDown(() => UseRequestObserver.instance = null);

  group('BUG-5 refreshDeps 使用最近一次参数刷新', () {
    testWidgets('Hook 版：run(5) 后依赖变化，以 5 而非 defaultParams 刷新', (tester) async {
      final calls = <int>[];
      late UseRequestResult<String, int> result;

      Widget build(int dep) => MaterialApp(
        home: HookBuilder(
          builder: (context) {
            result = useRequest<String, int>(
              (p) async {
                calls.add(p);
                return 'V$p';
              },
              options: UseRequestOptions(defaultParams: 1, refreshDeps: [dep]),
            );
            return Text(result.data ?? 'idle');
          },
        ),
      );

      await tester.pumpWidget(build(1));
      await tester.pump();
      expect(calls, [1]);

      result.run(5);
      await tester.pump();
      expect(calls, [1, 5]);

      await tester.pumpWidget(build(2));
      await tester.pump();
      expect(calls, [1, 5, 5]);
    });

    test('Riverpod 版：refreshDeps 触发时复用最近一次参数', () async {
      final calls = <int>[];
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async {
          calls.add(p);
          return 'V$p';
        },
        options: const UseRequestOptions(defaultParams: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, [1]);

      await notifier.runAsync(5);
      notifier.refreshDeps([99]);
      await Future<void>.delayed(Duration.zero);

      expect(calls, [1, 5, 5]);
      notifier.dispose();
    });
  });

  group('BUG-6 未请求过时 refresh()/loadMore() 不同步抛出', () {
    testWidgets('Hook 版', (tester) async {
      late UseRequestResult<String, int> result;
      await tester.pumpWidget(
        MaterialApp(
          home: HookBuilder(
            builder: (context) {
              result = useRequest<String, int>(
                (p) async => 'V$p',
                options: UseRequestOptions(
                  manual: true,
                  loadMoreParams: (last, data) => last + 1,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(() => result.refresh(), returnsNormally);
      expect(() => result.loadMore!(), returnsNormally);
      await tester.pump();
    });

    test('Riverpod 版', () async {
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'V$p',
        options: UseRequestOptions(
          manual: true,
          loadMoreParams: (last, data) => last + 1,
        ),
      );

      expect(() => notifier.refresh(), returnsNormally);
      expect(() => notifier.loadMore(), returnsNormally);
      await Future<void>.delayed(Duration.zero);
      notifier.dispose();
    });
  });

  group('BUG-7 cancel() 取消排队中的防抖调用', () {
    test('防抖窗口内 cancel 后不再发出请求', () async {
      var callCount = 0;
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async {
          callCount++;
          return 'V$p';
        },
        options: const UseRequestOptions(
          manual: true,
          debounceInterval: Duration(milliseconds: 100),
        ),
      );

      notifier.run(1);
      notifier.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(callCount, 0);
      notifier.dispose();
    });
  });

  group('BUG-8 失败不清除有效缓存', () {
    test('后台再验证失败后，缓存中仍保留旧数据', () async {
      var calls = 0;
      final notifier = UseRequestNotifier<String, int>(
        service: (p) async {
          calls++;
          if (calls > 1) throw Exception('revalidate failed');
          return 'ok';
        },
        options: UseRequestOptions(
          manual: true,
          cacheKey: (p) => 'bug8-$p',
          cacheTime: const Duration(minutes: 1),
        ),
      );

      await notifier.runAsync(1);
      expect(getCache<String>('bug8-1')?.data, 'ok');

      // 第二次：命中缓存后台再验证，服务失败
      try {
        await notifier.runAsync(1);
      } catch (_) {}

      expect(notifier.currentState.error, isNotNull);
      expect(
        getCache<String>('bug8-1')?.data,
        'ok',
        reason: 'SWR 语义：再验证失败不应抹掉仍在有效期内的缓存',
      );
      notifier.dispose();
    });
  });

  group('BUG-9/17 轮询使用最新 options，isPolling 派生自控制器', () {
    testWidgets('rebuild 后轮询触发的请求使用新的 onSuccess', (tester) async {
      final tags = <String>[];
      late UseRequestResult<String, int> result;

      Widget build(String tag) => MaterialApp(
        home: HookBuilder(
          builder: (context) {
            result = useRequest<String, int>(
              (p) async => 'v',
              options: UseRequestOptions(
                defaultParams: 1,
                pollingInterval: const Duration(milliseconds: 100),
                onSuccess: (data, params) => tags.add(tag),
              ),
            );
            return Text(result.data ?? 'idle');
          },
        ),
      );

      await tester.pumpWidget(build('old'));
      await tester.pump();
      expect(tags, ['old']);

      // rebuild：onSuccess 不在轮询 effect keys 中，控制器不会重建
      await tester.pumpWidget(build('new'));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(tags.last, 'new', reason: '轮询应使用最新一帧的 onSuccess');
      expect(result.isPolling, isTrue);

      // 卸载以清理轮询定时器
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('BUG-10 Throttler maxWait 立即执行分支', () {
    test('不双重执行排队中的 trailing，等待者共享本次结果', () async {
      final executed = <int>[];
      final throttler = Throttler<int>(
        duration: const Duration(milliseconds: 100),
        maxWait: const Duration(milliseconds: 30),
      );

      final f1 = throttler.call(() async {
        executed.add(1);
        return 1;
      });
      final f2 = throttler.call(() async {
        executed.add(2);
        return 2;
      });

      // 同步阻塞 40ms：模拟事件循环繁忙，maxWait 已过期但旧定时器回调尚未运行
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 40) {}

      final f3 = throttler.call(() async {
        executed.add(3);
        return 3;
      });

      expect(await f1, 1);
      expect(await f3, 3);
      expect(await f2, 3, reason: '排队等待者应共享 maxWait 立即执行的结果');

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(executed, [1, 3], reason: '旧的 trailing action 不应再被执行');
      throttler.dispose();
    });
  });

  group('BUG-11 可空 TData 的 null 结果', () {
    test('service 合法返回 null 时清空 data，而非保留旧值', () async {
      var returnNull = false;
      final notifier = UseRequestNotifier<String?, int>(
        service: (p) async => returnNull ? null : 'v',
        options: const UseRequestOptions(manual: true),
      );

      await notifier.runAsync(1);
      expect(notifier.currentState.data, 'v');

      returnNull = true;
      await notifier.runAsync(1);
      expect(notifier.currentState.data, isNull);
      notifier.dispose();
    });
  });

  group('BUG-12 观察者事件配对', () {
    test('fresh 缓存命中同样补发 onFinally', () async {
      final observer = _CountingObserver();
      UseRequestObserver.instance = observer;

      final notifier = UseRequestNotifier<String, int>(
        service: (p) async => 'v',
        options: UseRequestOptions(
          manual: true,
          cacheKey: (p) => 'bug12-$p',
          staleTime: const Duration(minutes: 1),
        ),
      );

      await notifier.runAsync(1); // 真实请求
      await notifier.runAsync(1); // fresh 缓存命中，不发网络请求

      expect(observer.requests, 2);
      expect(observer.finallys, observer.requests);
      notifier.dispose();
    });
  });

  group('BUG-13 HttpRequestConfig 值语义', () {
    test('相同请求语义的实例相等，cancelToken/回调不参与比较', () {
      final a = HttpRequestConfig.get('/a', queryParameters: {'p': 1});
      final b = HttpRequestConfig.get('/a', queryParameters: {'p': 1});
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      expect(HttpRequestConfig.get('/a'), isNot(HttpRequestConfig.get('/b')));
      expect(
        HttpRequestConfig.get('/a', queryParameters: {'p': 1}),
        isNot(HttpRequestConfig.get('/a', queryParameters: {'p': 2})),
      );

      expect(
        HttpRequestConfig(path: '/a', cancelToken: CancelToken()),
        HttpRequestConfig(path: '/a', cancelToken: CancelToken()),
      );
    });
  });
}
