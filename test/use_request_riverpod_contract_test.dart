import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:use_request/use_request.dart';

class _RiverpodBuilderProbe<TData, TParams> extends StatelessWidget {
  const _RiverpodBuilderProbe({super.key, required this.service, this.options, this.serviceKey});

  final Service<TData, TParams> service;
  final UseRequestOptions<TData, TParams>? options;
  final Object? serviceKey;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: UseRequestBuilder<TData, TParams>(
          service: service,
          serviceKey: serviceKey,
          options: options,
          builder: (context, state, notifier) {
            return Text('${state.loading}|${state.data ?? 'null'}');
          },
        ),
      ),
    );
  }
}

/// 这个测试组件专门覆盖 UseRequestMixin 的首帧初始化行为。
///
/// mixin 版和 Builder 版都要在 widget 第一次 build 之前拿到 notifier 的当前 state，
/// 否则即便缓存已经命中，页面首帧还是会渲染默认值。
class _RiverpodMixinProbe extends ConsumerStatefulWidget {
  const _RiverpodMixinProbe({required this.service, required this.options});

  final Future<String> Function(int) service;
  final UseRequestOptions<String, int> options;

  @override
  ConsumerState<_RiverpodMixinProbe> createState() =>
      _RiverpodMixinProbeState();
}

class _RiverpodMixinProbeState extends ConsumerState<_RiverpodMixinProbe>
    with UseRequestMixin<String, int> {
  @override
  void initState() {
    super.initState();
    initUseRequest(ref: ref, service: widget.service, options: widget.options);
  }

  @override
  void dispose() {
    disposeUseRequest();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${state.loading}|${state.data ?? 'null'}'),
    );
  }
}

void main() {
  setUp(clearAllCache);

  test('riverpod no-param auto request runs on initialization', () async {
    var callCount = 0;

    Future<String> service(dynamic _) async {
      callCount += 1;
      return 'v$callCount';
    }

    final notifier = UseRequestNotifier<String, dynamic>(
      service: service,
      options: const UseRequestOptions(),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(callCount, 1);
    expect(notifier.state.data, 'v1');

    notifier.dispose();
  });

  test(
    'riverpod refreshDeps does not duplicate initial auto request',
    () async {
      var callCount = 0;

      Future<String> service(int value) async {
        callCount += 1;
        return 'v$value';
      }

      final notifier = UseRequestNotifier<String, int>(
        service: service,
        options: const UseRequestOptions(defaultParams: 1, refreshDeps: [1]),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(callCount, 1);
      expect(notifier.state.data, 'v1');

      notifier.dispose();
    },
  );

  test('riverpod setReady replays pending refreshDeps only once', () async {
    var callCount = 0;

    Future<String> service(int value) async {
      callCount += 1;
      return 'v$value';
    }

    final notifier = UseRequestNotifier<String, int>(
      service: service,
      options: const UseRequestOptions(defaultParams: 1, ready: false),
    );

    notifier.refreshDeps(const [2]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(callCount, 0);

    notifier.setReady(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(callCount, 1);
    expect(notifier.state.data, 'v1');

    notifier.dispose();
  });

  test(
    'riverpod no-param polling keeps working after initial auto run',
    () async {
      var callCount = 0;

      Future<String> service(dynamic _) async {
        callCount += 1;
        return 'v$callCount';
      }

      final notifier = UseRequestNotifier<String, dynamic>(
        service: service,
        options: const UseRequestOptions(
          pollingInterval: Duration(milliseconds: 20),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(callCount, greaterThan(1));
      expect(notifier.state.data, 'v$callCount');

      notifier.dispose();
    },
  );

  test('riverpod no-param reconnect refresh still works', () async {
    final controller = StreamController<bool>.broadcast();
    var callCount = 0;

    Future<String> service(dynamic _) async {
      callCount += 1;
      return 'v$callCount';
    }

    final notifier = UseRequestNotifier<String, dynamic>(
      service: service,
      options: UseRequestOptions(
        refreshOnReconnect: true,
        reconnectStream: controller.stream,
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(callCount, 1);

    controller.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(callCount, 2);
    expect(notifier.state.data, 'v2');

    notifier.dispose();
    await controller.close();
  });

  testWidgets('riverpod no-param focus refresh still works', (tester) async {
    var callCount = 0;

    Future<String> service(dynamic _) async {
      callCount += 1;
      return 'v$callCount';
    }

    await tester.pumpWidget(
      _RiverpodBuilderProbe<String, dynamic>(
        service: service,
        options: const UseRequestOptions(refreshOnFocus: true),
      ),
    );
    await tester.pump();

    expect(callCount, 1);
    expect(find.text('false|v1'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(callCount, 2);
    expect(find.text('false|v2'), findsOneWidget);
  });

  testWidgets('UseRequestBuilder reads fresh cache on first frame', (
    tester,
  ) async {
    setCache<String>('builder-1', 'cached');
    var callCount = 0;

    Future<String> service(int value) async {
      callCount += 1;
      return 'v$value';
    }

    await tester.pumpWidget(
      _RiverpodBuilderProbe<String, int>(
        service: service,
        options: UseRequestOptions(
          defaultParams: 1,
          cacheKey: (value) => 'builder-$value',
          staleTime: const Duration(minutes: 1),
          cacheTime: const Duration(minutes: 5),
        ),
      ),
    );

    expect(find.text('false|cached'), findsOneWidget);
    expect(callCount, 0);
  });

  testWidgets('UseRequestMixin reads fresh cache on first frame', (
    tester,
  ) async {
    setCache<String>('mixin-1', 'cached');
    var callCount = 0;

    Future<String> service(int value) async {
      callCount += 1;
      return 'v$value';
    }

    await tester.pumpWidget(
      ProviderScope(
        child: _RiverpodMixinProbe(
          service: service,
          options: UseRequestOptions(
            defaultParams: 1,
            cacheKey: (value) => 'mixin-$value',
            staleTime: const Duration(minutes: 1),
            cacheTime: const Duration(minutes: 5),
          ),
        ),
      ),
    );

    expect(find.text('false|cached'), findsOneWidget);
    expect(callCount, 0);
  });

  testWidgets(
    'UseRequestBuilder rebuilds notifier when service or options change',
    (tester) async {
      var serviceACallCount = 0;
      var serviceBCallCount = 0;

      Future<String> serviceA(int value) async {
        serviceACallCount += 1;
        return 'A$value';
      }

      Future<String> serviceB(int value) async {
        serviceBCallCount += 1;
        return 'B$value';
      }

      await tester.pumpWidget(
        _RiverpodBuilderProbe<String, int>(
          key: const ValueKey('request-builder'),
          service: serviceA,
          serviceKey: 'A',
          options: const UseRequestOptions(defaultParams: 1),
        ),
      );
      await tester.pump();

      expect(find.text('false|A1'), findsOneWidget);
      expect(serviceACallCount, 1);
      expect(serviceBCallCount, 0);

      await tester.pumpWidget(
        _RiverpodBuilderProbe<String, int>(
          key: const ValueKey('request-builder'),
          service: serviceB,
          serviceKey: 'B',
          options: const UseRequestOptions(defaultParams: 2),
        ),
      );
      await tester.pump();

      expect(find.text('false|B2'), findsOneWidget);
      expect(serviceACallCount, 1);
      expect(serviceBCallCount, 1);
    },
  );

  testWidgets(
    'updateOptions preserves data state while updating utility params',
    (tester) async {
      var callCount = 0;
      Future<String> service(int value) async {
        callCount += 1;
        return 'V$value';
      }

      // 首次渲染，不带防抖
      await tester.pumpWidget(
        _RiverpodBuilderProbe<String, int>(
          key: const ValueKey('update-opts'),
          service: service,
          options: const UseRequestOptions(defaultParams: 1),
        ),
      );
      await tester.pump();

      expect(find.text('false|V1'), findsOneWidget);
      expect(callCount, 1);

      // 更新 options（增加防抖），不应丢失已有数据
      await tester.pumpWidget(
        _RiverpodBuilderProbe<String, int>(
          key: const ValueKey('update-opts'),
          service: service,
          options: const UseRequestOptions(
            defaultParams: 1,
            debounceInterval: Duration(milliseconds: 500),
          ),
        ),
      );
      await tester.pump();

      // 数据仍在（未被销毁重建）
      expect(find.text('false|V1'), findsOneWidget);
      // 未触发新请求
      expect(callCount, 1);
    },
  );
}
