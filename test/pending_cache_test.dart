import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

class _PendingHookProbe extends HookWidget {
  const _PendingHookProbe({required this.service});

  final Future<String> Function(int) service;

  @override
  Widget build(BuildContext context) {
    final request = useRequest<String, int>(
      service,
      options: UseRequestOptions(
        defaultParams: 1,
        cacheKey: (p) => 'shared-$p',
      ),
    );

    final text = '${request.loading}|${request.data ?? 'null'}';
    return Directionality(textDirection: TextDirection.ltr, child: Text(text));
  }
}

void main() {
  testWidgets(
    'hook subscriber receives pending cache result after previous widget disposes',
    (tester) async {
      final completer = Completer<String>();
      var callCount = 0;

      Future<String> service(int p) {
        callCount += 1;
        return completer.future;
      }

      await tester.pumpWidget(_PendingHookProbe(service: service));
      expect(find.text('true|null'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_PendingHookProbe(service: service));

      // The second widget should reuse the in-flight request rather than fire a
      // duplicate network call.
      expect(callCount, 1);
      expect(find.text('true|null'), findsOneWidget);

      completer.complete('done');
      await tester.pump();
      await tester.pump();

      expect(find.text('false|done'), findsOneWidget);
    },
  );

  test('riverpod subscriber receives pending cache result', () async {
    final completer = Completer<String>();
    var callCount = 0;

    Future<String> service(int p) {
      callCount += 1;
      return completer.future;
    }

    final notifierA = UseRequestNotifier<String, int>(
      service: service,
      options: UseRequestOptions(manual: true, cacheKey: (p) => 'shared-$p'),
    );
    final notifierB = UseRequestNotifier<String, int>(
      service: service,
      options: UseRequestOptions(manual: true, cacheKey: (p) => 'shared-$p'),
    );

    final futureA = notifierA.runAsync(1);
    final futureB = notifierB.runAsync(1);

    expect(callCount, 1);
    expect(notifierB.state.loading, true);

    completer.complete('done');

    expect(await futureA, 'done');
    expect(await futureB, 'done');
    expect(notifierB.state.loading, false);
    expect(notifierB.state.data, 'done');

    notifierA.dispose();
    notifierB.dispose();
  });
}
