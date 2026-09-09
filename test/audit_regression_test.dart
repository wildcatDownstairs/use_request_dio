import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:dio/dio.dart';
import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);
  test('null params mutate must update cache', () async {
    final n = UseRequestNotifier<String, Null>(
      service: (_) async => 'old',
      options: UseRequestOptions(manual: true, cacheKey: (_) => 'null-key'),
    );
    addTearDown(n.dispose);
    await n.runAsync(null);
    n.mutate((_) => 'new');
    expect(getCache<String>('null-key')?.data, 'new');
    n.mutate((_) => null);
    expect(getCache<String>('null-key'), isNull);
  });
  test('dynamic options reject simultaneous rate controls', () {
    final n = UseRequestNotifier<String, int>(
      service: (_) async => '',
      options: const UseRequestOptions(manual: true),
    );
    addTearDown(n.dispose);
    final previousOptions = n.options;
    expect(
      () => n.updateOptions(
        const UseRequestOptions(
          manual: true,
          debounceInterval: Duration(seconds: 1),
          throttleInterval: Duration(seconds: 1),
        ),
      ),
      throwsArgumentError,
    );
    expect(n.options, same(previousOptions));
  });
  test('adapter preserves Dio validateStatus', () async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          h.resolve(Response(requestOptions: o, data: o.validateStatus(418)));
        },
      ),
    );
    final response = await DioHttpAdapter(dio: dio).get<bool>('/probe');
    expect(response.data, true);
    dio.close();
  });
  test(
    'adapter merges base and request options with explicit overrides',
    () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://example.com',
          headers: {'base': 'yes'},
          queryParameters: {'base': 1},
          followRedirects: false,
          maxRedirects: 2,
        ),
      );
      addTearDown(dio.close);
      late RequestOptions captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            captured = o;
            h.resolve(Response<String>(requestOptions: o, data: 'ok'));
          },
        ),
      );
      await DioHttpAdapter(dio: dio).request<String>(
        HttpRequestConfig(
          path: '/probe',
          method: HttpMethod.post,
          headers: {'request': 'yes'},
          queryParameters: {'page': 2},
          connectTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 4),
          contentType: 'text/plain',
          extra: Options(
            headers: {'extra': 'yes'},
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 9),
            validateStatus: (status) => status == 418,
          ),
        ),
      );
      expect(captured.headers, containsPair('base', 'yes'));
      expect(captured.headers, containsPair('request', 'yes'));
      expect(captured.headers, containsPair('extra', 'yes'));
      expect(captured.queryParameters, {'base': 1, 'page': 2});
      expect(captured.followRedirects, false);
      expect(captured.maxRedirects, 2);
      expect(captured.validateStatus(418), true);
      expect(captured.validateStatus(200), false);
      expect(captured.connectTimeout, const Duration(seconds: 3));
      expect(captured.sendTimeout, const Duration(seconds: 4));
      expect(captured.receiveTimeout, const Duration(seconds: 9));
      expect(captured.contentType, 'text/plain');
    },
  );
  testWidgets('Builder invokes updated service without losing state', (
    tester,
  ) async {
    late UseRequestNotifier<String, int> n;
    Widget build(String tag) => UseRequestBuilder<String, int>(
      service: (_) async => tag,
      options: const UseRequestOptions(manual: true),
      builder: (_, s, notifier) {
        n = notifier;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(build('old'));
    await n.runAsync(1);
    await tester.pump();
    final previousNotifier = n;
    await tester.pumpWidget(build('new'));
    expect(n, same(previousNotifier));
    expect(n.currentState.data, 'old');
    expect(await n.runAsync(1), 'new');
  });
  testWidgets('closure mutate must update cache', (tester) async {
    late UseRequestResult<String, Null> r;
    await tester.pumpWidget(
      HookBuilder(
        builder: (_) {
          r = useRequestFn(
            () async => 'old',
            options: UseRequestOptions(
              manual: true,
              cacheKey: (_) => 'hook-null',
            ),
          );
          return const SizedBox();
        },
      ),
    );
    await r.runAsync(null);
    await tester.pump();
    r.mutate((_) => 'new');
    expect(getCache<String>('hook-null')?.data, 'new');
    r.mutate((_) => null);
    expect(getCache<String>('hook-null'), isNull);
  });
}
