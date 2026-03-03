import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

class _RecordingObserver extends UseRequestObserver {
  final List<String> events = [];
  final Map<String, dynamic> lastArgs = {};

  @override
  void onRequest(String key, Object? params) {
    events.add('onRequest');
    lastArgs['onRequest'] = {'key': key, 'params': params};
  }

  @override
  void onSuccess(String key, Object? data, Object? params) {
    events.add('onSuccess');
    lastArgs['onSuccess'] = {'key': key, 'data': data, 'params': params};
  }

  @override
  void onError(String key, Object error, Object? params) {
    events.add('onError');
    lastArgs['onError'] = {'key': key, 'error': error, 'params': params};
  }

  @override
  void onFinally(String key, Object? params) {
    events.add('onFinally');
    lastArgs['onFinally'] = {'key': key, 'params': params};
  }

  @override
  void onMutate(String key, Object? oldData, Object? newData) {
    events.add('onMutate');
    lastArgs['onMutate'] = {'key': key, 'oldData': oldData, 'newData': newData};
  }

  @override
  void onCancel(String key) {
    events.add('onCancel');
    lastArgs['onCancel'] = {'key': key};
  }
}

void main() {
  setUp(clearAllCache);

  late _RecordingObserver observer;

  setUp(() {
    observer = _RecordingObserver();
    UseRequestObserver.instance = observer;
  });

  tearDown(() {
    UseRequestObserver.instance = null;
  });

  test('successful request triggers onRequest, onSuccess, onFinally', () async {
    final notifier = UseRequestNotifier<String, int>(
      service: (p) async => 'result-$p',
      options: const UseRequestOptions(manual: true),
    );

    await notifier.runAsync(42);

    expect(observer.events, ['onRequest', 'onSuccess', 'onFinally']);
    expect(observer.lastArgs['onSuccess']?['data'], 'result-42');
    expect(observer.lastArgs['onSuccess']?['params'], 42);

    notifier.dispose();
  });

  test('failing request triggers onRequest, onError, onFinally', () async {
    final error = Exception('boom');
    final notifier = UseRequestNotifier<String, int>(
      service: (p) async => throw error,
      options: const UseRequestOptions(manual: true),
    );

    try {
      await notifier.runAsync(1);
    } catch (_) {}

    expect(observer.events, ['onRequest', 'onError', 'onFinally']);
    expect(observer.lastArgs['onError']?['error'], error);

    notifier.dispose();
  });

  test('mutate triggers onMutate', () async {
    final notifier = UseRequestNotifier<String, int>(
      service: (p) async => 'result-$p',
      options: UseRequestOptions(
        manual: true,
        cacheKey: (p) => 'obs-$p',
      ),
    );

    await notifier.runAsync(1);
    observer.events.clear();

    notifier.mutate((old) => 'mutated');

    expect(observer.events, contains('onMutate'));
    expect(observer.lastArgs['onMutate']?['oldData'], 'result-1');
    expect(observer.lastArgs['onMutate']?['newData'], 'mutated');

    notifier.dispose();
  });

  test('cancel triggers onCancel', () async {
    final notifier = UseRequestNotifier<String, int>(
      service: (p) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'result-$p';
      },
      options: const UseRequestOptions(manual: true),
    );

    notifier.run(1);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    notifier.cancel();

    expect(observer.events, contains('onCancel'));

    notifier.dispose();
  });

  test('null observer does not crash', () async {
    UseRequestObserver.instance = null;

    final notifier = UseRequestNotifier<String, int>(
      service: (p) async => 'result-$p',
      options: const UseRequestOptions(manual: true),
    );

    // Should not throw
    await notifier.runAsync(1);
    notifier.mutate((old) => 'changed');
    notifier.cancel();

    notifier.dispose();
  });
}
