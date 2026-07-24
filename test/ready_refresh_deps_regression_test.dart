import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:use_request/use_request.dart';

class _ParameterModeProbe extends HookWidget {
  const _ParameterModeProbe({required this.requestId, required this.calls});

  final int? requestId;
  final List<int?> calls;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int?>(
      (id) async {
        calls.add(id);
        return 'result-$id';
      },
      options: UseRequestOptions(
        ready: requestId != null,
        defaultParams: requestId,
        refreshDeps: <Object?>[requestId],
      ),
    );

    return MaterialApp(home: Text(request.data ?? 'loading'));
  }
}

class _ClosureModeProbe extends HookWidget {
  const _ClosureModeProbe({
    required this.requestId,
    required this.ready,
    required this.calls,
  });

  final int? requestId;
  final bool ready;
  final List<int?> calls;

  @override
  Widget build(BuildContext context) {
    final request = useRequestFn<String>(
      () async {
        calls.add(requestId);
        return 'result-$requestId';
      },
      options: UseRequestOptions(
        ready: ready,
        refreshDeps: <Object?>[requestId],
      ),
    );

    return MaterialApp(home: Text(request.data ?? 'loading'));
  }
}

class _RefreshDepsActionProbe extends HookWidget {
  const _RefreshDepsActionProbe({
    required this.requestId,
    required this.serviceCalls,
    required this.actionCalls,
  });

  final int? requestId;
  final List<int?> serviceCalls;
  final List<int?> actionCalls;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int?>(
      (id) async {
        serviceCalls.add(id);
        return 'result-$id';
      },
      options: UseRequestOptions(
        ready: requestId != null,
        defaultParams: requestId,
        refreshDeps: <Object?>[requestId],
        refreshDepsAction: () => actionCalls.add(requestId),
      ),
    );

    return MaterialApp(home: Text(request.data ?? 'loading'));
  }
}

void main() {
  group('ready 与 refreshDeps 协同', () {
    testWidgets('参数模式同帧变更只请求一次', (tester) async {
      final calls = <int?>[];

      await tester.pumpWidget(
        _ParameterModeProbe(requestId: null, calls: calls),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.pumpWidget(_ParameterModeProbe(requestId: 42, calls: calls));
      await tester.pumpAndSettle();

      expect(calls, [42]);
    });

    testWidgets('闭包模式先暂存依赖变更，再恢复 ready 时只请求一次', (tester) async {
      final calls = <int?>[];

      await tester.pumpWidget(
        _ClosureModeProbe(requestId: null, ready: false, calls: calls),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.pumpWidget(
        _ClosureModeProbe(requestId: 42, ready: false, calls: calls),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);

      await tester.pumpWidget(
        _ClosureModeProbe(requestId: 42, ready: true, calls: calls),
      );
      await tester.pumpAndSettle();

      expect(calls, [42]);
    });

    testWidgets('自定义依赖动作与 ready 同帧变化时不会额外自动请求', (tester) async {
      final serviceCalls = <int?>[];
      final actionCalls = <int?>[];

      await tester.pumpWidget(
        _RefreshDepsActionProbe(
          requestId: null,
          serviceCalls: serviceCalls,
          actionCalls: actionCalls,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _RefreshDepsActionProbe(
          requestId: 42,
          serviceCalls: serviceCalls,
          actionCalls: actionCalls,
        ),
      );
      await tester.pumpAndSettle();

      expect(actionCalls, [42]);
      expect(serviceCalls, isEmpty);
    });

    test('Riverpod 同次更新 ready 与 refreshDeps 只请求一次', () async {
      final calls = <int>[];
      final notifier = UseRequestNotifier<String, int>(
        service: (id) async {
          calls.add(id);
          return 'result-$id';
        },
        options: const UseRequestOptions(
          ready: false,
          defaultParams: 42,
          refreshDeps: [null],
        ),
      );

      notifier.updateOptions(
        const UseRequestOptions(
          ready: true,
          defaultParams: 42,
          refreshDeps: [42],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, [42]);
      notifier.dispose();
    });
  });
}
