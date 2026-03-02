import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

class _RequiredParamHookProbe extends HookWidget {
  const _RequiredParamHookProbe({required this.service, required this.dep});

  final Future<String> Function(int) service;
  final int dep;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int>(
      service,
      options: UseRequestOptions(refreshDeps: [dep]),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${request.loading}|${request.data ?? 'null'}'),
    );
  }
}

class _NoParamReconnectProbe extends HookWidget {
  const _NoParamReconnectProbe({
    required this.service,
    required this.reconnectStream,
  });

  final Future<String> Function() service;
  final Stream<bool> reconnectStream;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, dynamic>(
      (_) => service(),
      options: UseRequestOptions(
        refreshOnReconnect: true,
        reconnectStream: reconnectStream,
      ),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${request.loading}|${request.data ?? 'null'}'),
    );
  }
}

class _NoParamPollingProbe extends HookWidget {
  const _NoParamPollingProbe({required this.service});

  final Future<String> Function() service;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, dynamic>(
      (_) => service(),
      options: UseRequestOptions(
        pollingInterval: const Duration(milliseconds: 20),
      ),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${request.loading}|${request.data ?? 'null'}'),
    );
  }
}

class _NoParamFocusProbe extends HookWidget {
  const _NoParamFocusProbe({required this.service});

  final Future<String> Function() service;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, dynamic>(
      (_) => service(),
      options: const UseRequestOptions(refreshOnFocus: true),
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text('${request.loading}|${request.data ?? 'null'}'),
    );
  }
}

class _ManualCancelProbe extends HookWidget {
  const _ManualCancelProbe({required this.service});

  final Future<String> Function(int) service;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int>(
      service,
      options: const UseRequestOptions(manual: true),
    );

    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Text(
              '${request.loading}|${request.loadingMore}|${request.data ?? 'null'}',
            ),
            TextButton(
              onPressed: () => request.run(1),
              child: const Text('run'),
            ),
            TextButton(onPressed: request.cancel, child: const Text('cancel')),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreCancelProbe extends HookWidget {
  const _LoadMoreCancelProbe({required this.service});

  final Future<String> Function(int) service;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int>(
      service,
      options: UseRequestOptions(
        manual: true,
        loadMoreParams: (lastParams, _) => lastParams + 1,
        dataMerger: (_, next) => next,
      ),
    );

    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Text(
              '${request.loading}|${request.loadingMore}|${request.data ?? 'null'}',
            ),
            TextButton(
              onPressed: () => request.run(1),
              child: const Text('run'),
            ),
            TextButton(
              onPressed: request.loadMore,
              child: const Text('loadMore'),
            ),
            TextButton(onPressed: request.cancel, child: const Text('cancel')),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUp(clearAllCache);

  testWidgets(
    'non-nullable auto request without params does not throw or fire request',
    (tester) async {
      var callCount = 0;

      Future<String> service(int value) async {
        callCount += 1;
        return 'v$value';
      }

      await tester.pumpWidget(
        _RequiredParamHookProbe(service: service, dep: 1),
      );
      await tester.pump();

      expect(callCount, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        _RequiredParamHookProbe(service: service, dep: 2),
      );
      await tester.pump();

      expect(callCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('null-param reconnect refresh works', (tester) async {
    final controller = StreamController<bool>.broadcast();
    var callCount = 0;

    Future<String> service() async {
      callCount += 1;
      return 'v$callCount';
    }

    await tester.pumpWidget(
      _NoParamReconnectProbe(
        service: service,
        reconnectStream: controller.stream,
      ),
    );
    await tester.pump();

    expect(callCount, 1);
    expect(find.text('false|v1'), findsOneWidget);

    controller.add(true);
    await tester.pump();
    await tester.pump();

    expect(callCount, 2);
    expect(find.text('false|v2'), findsOneWidget);

    await controller.close();
  });

  testWidgets('null-param polling works after initial auto run', (
    tester,
  ) async {
    var callCount = 0;

    Future<String> service() async {
      callCount += 1;
      return 'v$callCount';
    }

    await tester.pumpWidget(_NoParamPollingProbe(service: service));
    await tester.pump();

    expect(callCount, 1);

    await tester.pump(const Duration(milliseconds: 70));
    await tester.pump();

    expect(callCount, greaterThan(1));
    expect(find.text('false|v$callCount'), findsOneWidget);
  });

  testWidgets('null-param focus refresh works', (tester) async {
    var callCount = 0;

    Future<String> service() async {
      callCount += 1;
      return 'v$callCount';
    }

    await tester.pumpWidget(_NoParamFocusProbe(service: service));
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

  testWidgets('cancel clears normal loading state', (tester) async {
    final completer = Completer<String>();

    Future<String> service(int _) => completer.future;

    await tester.pumpWidget(_ManualCancelProbe(service: service));

    await tester.tap(find.text('run'));
    await tester.pump();
    expect(find.text('true|false|null'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await tester.pump();
    expect(find.text('false|false|null'), findsOneWidget);

    completer.complete('done');
    await tester.pump();
  });

  testWidgets('cancel clears loadMore loading state', (tester) async {
    final page2Completer = Completer<String>();

    Future<String> service(int page) async {
      if (page == 1) return 'page-1';
      return page2Completer.future;
    }

    await tester.pumpWidget(_LoadMoreCancelProbe(service: service));

    await tester.tap(find.text('run'));
    await tester.pump();
    await tester.pump();
    expect(find.text('false|false|page-1'), findsOneWidget);

    await tester.tap(find.text('loadMore'));
    await tester.pump();
    expect(find.text('false|true|page-1'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await tester.pump();
    expect(find.text('false|false|page-1'), findsOneWidget);

    page2Completer.complete('page-2');
    await tester.pump();
  });
}
