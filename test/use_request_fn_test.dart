import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

/// 闭包模式探针：筛选值 [filter] 由外部传入，service 闭包直接捕获，
/// refreshDeps 只声明触发时机。对应"列表筛选 tab 切换"场景。
class _ClosureModeProbe extends HookWidget {
  const _ClosureModeProbe({required this.filter, required this.log});

  final int filter;
  final List<int> log;

  @override
  Widget build(BuildContext context) {
    final request = useRequestFn<String>(
      () async {
        log.add(filter);
        return 'result-$filter';
      },
      options: UseRequestOptions(refreshDeps: <Object?>[filter]),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(request.data ?? 'null'),
    );
  }
}

/// refresh() 探针：无 refreshDeps（rebuild 不自动请求），把最新一帧的
/// request 通过 [onBuild] 暴露出去，测试可显式调用 refresh()。
class _RefreshProbe extends HookWidget {
  const _RefreshProbe({
    required this.tag,
    required this.log,
    required this.onBuild,
  });

  final int tag;
  final List<int> log;
  final void Function(UseRequestResult<String, Null> request) onBuild;

  @override
  Widget build(BuildContext context) {
    final request = useRequestFn<String>(() async {
      log.add(tag);
      return 'result-$tag';
    });
    onBuild(request);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(request.data ?? 'null'),
    );
  }
}

void main() {
  testWidgets('useRequestFn: refreshDeps 变化时闭包读到最新筛选值（回归今天的 tab 切换缺陷）', (
    tester,
  ) async {
    final log = <int>[];

    await tester.pumpWidget(_ClosureModeProbe(filter: 1, log: log));
    await tester.pumpAndSettle();
    expect(log, [1]);
    expect(find.text('result-1'), findsOneWidget);

    // 切换筛选：若走"复用上一次参数"的旧语义，闭包模式也必须拿到新值 2。
    await tester.pumpWidget(_ClosureModeProbe(filter: 2, log: log));
    await tester.pumpAndSettle();
    expect(log, [1, 2], reason: 'refreshDeps 变化后必须用最新闭包重新请求');
    expect(find.text('result-2'), findsOneWidget);

    // 依赖没变时不应重复请求。
    await tester.pumpWidget(_ClosureModeProbe(filter: 2, log: log));
    await tester.pumpAndSettle();
    expect(log, [1, 2]);
  });

  testWidgets('useRequestFn: refresh() 走的是最新一帧闭包，而非挂载时的旧闭包', (
    tester,
  ) async {
    final log = <int>[];
    late UseRequestResult<String, Null> latest;
    void capture(UseRequestResult<String, Null> r) => latest = r;

    // 挂载：自动请求一次，闭包 tag=1
    await tester.pumpWidget(_RefreshProbe(tag: 1, log: log, onBuild: capture));
    await tester.pumpAndSettle();
    expect(log, [1]);

    // 显式 refresh()：复用上一次参数（null），但闭包仍是 tag=1
    latest.refresh();
    await tester.pumpAndSettle();
    expect(log, [1, 1], reason: 'refresh() 应重新执行闭包');

    // rebuild 到 tag=2（无 refreshDeps，不会自动请求）
    await tester.pumpWidget(_RefreshProbe(tag: 2, log: log, onBuild: capture));
    await tester.pumpAndSettle();
    expect(log, [1, 1], reason: '没有 refreshDeps，rebuild 不应触发请求');

    // 关键断言：refresh() 必须走 tag=2 的新闭包，而不是挂载时捕获的 tag=1。
    // 这正是 serviceRef 每帧更新所要守住的 stale-closure 边界。
    latest.refresh();
    await tester.pumpAndSettle();
    expect(log, [1, 1, 2], reason: 'refresh() 必须使用最新一帧闭包');
  });
}
