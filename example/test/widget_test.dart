import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

const _kSearchJson =
    '{"total_count":1,"incomplete_results":false,"items":['
    '{"id":1,"name":"flutter","full_name":"flutter/flutter",'
    '"description":"Flutter SDK","html_url":"https://github.com/flutter/flutter",'
    '"stargazers_count":160000,"language":"Dart",'
    '"owner":{"login":"flutter",'
    '"avatar_url":"https://avatars.githubusercontent.com/u/14101776?v=4"}}]}';

const _kTransparent1x1PngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+8n8AAAAASUVORK5CYII=';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;
  @override
  bool autoUncompress = true;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) {}

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    callback,
  ) {}

  @override
  set keyLog(Function(String line)? callback) {}

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? callback,
  ) {}

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    callback,
  ) {}

  @override
  set findProxy(String Function(Uri url)? callback) {}

  @override
  void close({bool force = false}) {}

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {}

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) {}

  Future<HttpClientRequest> _open(String method, Uri url) async =>
      _MockHttpClientRequest(method, url);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _open(method, Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _open(method, url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _open('GET', Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _open('GET', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _open('POST', Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _open('POST', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _open('PUT', Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _open('PUT', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _open('DELETE', Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _open('DELETE', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _open('HEAD', Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _open('HEAD', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _open('PATCH', Uri.http('$host:$port', path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _open('PATCH', url);
}

class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest(this.method, this.uri);

  @override
  final String method;

  @override
  final Uri uri;

  @override
  bool bufferOutput = true;

  @override
  int contentLength = -1;

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse(uri);

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  List<Cookie> get cookies => <Cookie>[];

  @override
  Future<HttpClientResponse> get done async => _MockHttpClientResponse(uri);

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _MockHttpClientResponse(this.uri);

  final Uri uri;

  bool get _isImageRequest {
    final path = uri.path.toLowerCase();
    return uri.host.contains('avatars.githubusercontent.com') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp');
  }

  late final List<int> _payload = _isImageRequest
      ? base64Decode(_kTransparent1x1PngBase64)
      : utf8.encode(_kSearchJson);

  Stream<List<int>> get _body => Stream<List<int>>.value(_payload);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  final int statusCode = 200;

  @override
  final String reasonPhrase = 'OK';

  @override
  late final int contentLength = _payload.length;

  @override
  late final HttpHeaders headers = _MockHttpHeaders()
    ..add(
      HttpHeaders.contentTypeHeader,
      _isImageRequest ? 'image/png' : 'application/json; charset=utf-8',
    );

  @override
  final bool isRedirect = false;

  @override
  final List<RedirectInfo> redirects = const <RedirectInfo>[];

  @override
  final bool persistentConnection = true;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  List<Cookie> get cookies => <Cookie>[];

  @override
  Future<Socket> detachSocket() => throw UnimplementedError();

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => throw UnimplementedError();
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = <String, List<String>>{};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final key = preserveHeaderCase ? name : name.toLowerCase();
    _headers.putIfAbsent(key, () => <String>[]).add(value.toString());
  }

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];

  @override
  void clear() => _headers.clear();

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach(action);
  }

  @override
  void noFolding(String name) {}

  @override
  void remove(String name, Object value) {
    _headers[name.toLowerCase()]?.remove(value.toString());
  }

  @override
  void removeAll(String name) => _headers.remove(name.toLowerCase());

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final key = preserveHeaderCase ? name : name.toLowerCase();
    _headers[key] = <String>[value.toString()];
  }

  @override
  String? value(String name) {
    final values = _headers[name.toLowerCase()];
    return (values == null || values.isEmpty) ? null : values.first;
  }

  @override
  bool chunkedTransferEncoding = false;

  @override
  int contentLength = -1;

  @override
  ContentType? contentType;

  @override
  DateTime? date;

  @override
  DateTime? expires;

  @override
  bool persistentConnection = true;

  @override
  DateTime? ifModifiedSince;

  @override
  String? host;

  @override
  int? port;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    HttpOverrides.global = _MockHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('throttle switch does not throw build-time setState', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: UseRequestShowcaseApp()),
    );
    await _pumpFrames(tester);

    final level2Button = find.textContaining('Level 2 · 搜索频率控制（防抖 / 节流）');
    if (level2Button.evaluate().isNotEmpty) {
      await tester.ensureVisible(level2Button.first);
      await tester.tap(level2Button.first, warnIfMissed: false);
      await _pumpFrames(tester);
    }

    final throttle = find.text('Throttle');
    expect(throttle, findsWidgets);
    await tester.ensureVisible(throttle.first);
    await tester.tap(throttle.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.takeException(), isNull);
  });
}
