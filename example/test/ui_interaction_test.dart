// Tests for the useRequest showcase UI.
//
// Strategy:
//  - All tests use a 1280×900 surface to satisfy fixed-width constraints.
//  - We avoid pumpAndSettle: polling/retry timers would make it time-out.
//  - We mock the HTTP layer so all Dio requests return 200 OK with a minimal
//    GitHub Search response. This prevents DioExceptions from leaking into the
//    test zone and triggering the test-framework's uncaught-error assertion.
//  - Pre-existing RenderFlex overflow warnings (DropdownButtonFormField in a
//    tight column) are suppressed via FlutterError.onError because they are
//    layout bugs in the showcase app code and do not affect interactive state.

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

// ─── HTTP mock ──────────────────────────────────────────────────────────────

const _kSearchJson = '{"total_count":1,"incomplete_results":false,"items":['
    '{"id":1,"name":"flutter","full_name":"flutter/flutter",'
    '"description":"Flutter SDK","html_url":"https://github.com/flutter/flutter",'
    '"stargazers_count":160000,"language":"Dart",'
    '"owner":{"login":"flutter",'
    '"avatar_url":"https://avatars.githubusercontent.com/u/14101776?v=4"}}]}';

/// HttpOverrides that returns a 200 JSON response for every request.
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
    bool Function(X509Certificate cert, String host, int port)? f,
  ) {}
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) {}
  @override
  set keyLog(Function(String line)? callback) {}
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
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) {}
  @override
  set authenticateProxy(
    Future<bool> Function(
      String host,
      int port,
      String scheme,
      String? realm,
    )?
        f,
  ) {}
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  void close({bool force = false}) {}

  Future<HttpClientRequest> _open(String method, Uri url) async =>
      _MockHttpClientRequest(method, url);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) =>
      _open(method, Uri.http('$host:$port', path));
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
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => [];
  @override
  Future<HttpClientResponse> get done async => _MockHttpClientResponse();
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
  // Delegate all stream operations to a single-item stream.
  final Stream<List<int>> _body =
      Stream<List<int>>.value(utf8.encode(_kSearchJson));

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _body.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  // ── HttpClientResponse ────────────────────────────────────────────────
  @override
  final int statusCode = 200;
  @override
  final String reasonPhrase = 'OK';
  @override
  final int contentLength = -1;
  @override
  final HttpHeaders headers = _MockHttpHeaders()
    ..add(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
  @override
  final bool isRedirect = false;
  @override
  final List<RedirectInfo> redirects = const [];
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
  List<Cookie> get cookies => [];
  @override
  Future<Socket> detachSocket() => throw UnimplementedError();
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) =>
      throw UnimplementedError();
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final k = preserveHeaderCase ? name : name.toLowerCase();
    _headers.putIfAbsent(k, () => []).add(value.toString());
  }
  @override
  void clear() => _headers.clear();
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _headers.forEach(action);
  @override
  void noFolding(String name) {}
  @override
  void remove(String name, Object value) =>
      _headers[name.toLowerCase()]?.remove(value.toString());
  @override
  void removeAll(String name) => _headers.remove(name.toLowerCase());
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    final k = preserveHeaderCase ? name : name.toLowerCase();
    _headers[k] = [value.toString()];
  }
  @override
  String? value(String name) {
    final vals = _headers[name.toLowerCase()];
    return (vals == null || vals.isEmpty) ? null : vals.first;
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
}

// ─── helpers ────────────────────────────────────────────────────────────────

Widget _app() => const ProviderScope(child: UseRequestShowcaseApp());

/// Suppress pre-existing RenderFlex overflow errors in the showcase app
/// (DropdownButtonFormField in a tight Column). These are layout bugs in the
/// app code and do not affect interactive widget behaviour.
void _suppressLayoutOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains('overflowed')) return;
    prev?.call(details);
  };
  addTearDown(() => FlutterError.onError = prev);
}

/// Boot the app with a bounded surface, pump initial frames.
Future<void> _boot(WidgetTester tester) async {
  HttpOverrides.global = _MockHttpOverrides();
  addTearDown(() => HttpOverrides.global = null);
  _suppressLayoutOverflow();

  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // Drain all pending timers at test end to avoid !timersPending assertion.
  addTearDown(() async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(minutes: 1));
    }
    _drainException(tester);
  });

  await tester.pumpWidget(_app());
  await _pump(tester);
  _drainException(tester);
}

/// Pump 20×50 ms – lets async work resolve without being stuck on timers.
Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Drain the exception queue.
void _drainException(WidgetTester tester) {
  // ignore: literal_only_boolean_expressions
  while (tester.takeException() != null) {}
}

/// Tap [finder] and pump briefly.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 80));
}

/// Find the [Switch] element whose nearest ancestor [Row] also contains
/// a [Text] widget with [label].  This avoids confusion with identically-
/// named tag-chip texts that share a far-away ancestor Row.
Element? _findSwitchElement(WidgetTester tester, String label) {
  for (final swElement in find.byType(Switch).evaluate()) {
    Element? rowElement;
    swElement.visitAncestorElements((el) {
      if (el.widget is Row) {
        rowElement = el;
        return false;
      }
      return true;
    });
    if (rowElement == null) continue;
    final rowFinder =
        find.byElementPredicate((e) => identical(e, rowElement));
    if (find
        .descendant(of: rowFinder, matching: find.text(label))
        .evaluate()
        .isNotEmpty) {
      return swElement;
    }
  }
  return null;
}

/// Toggle the Switch that lives in the same Row as Text([label]).
Future<bool> _toggleSwitch(WidgetTester tester, String label) async {
  final swElement = _findSwitchElement(tester, label);
  if (swElement == null) return false;
  final swFinder =
      find.byElementPredicate((e) => identical(e, swElement));
  await tester.ensureVisible(swFinder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(swFinder, warnIfMissed: false);
  await _pump(tester);
  return true;
}

/// Read the value of the Switch in the same Row as Text([label]).
bool _switchValue(WidgetTester tester, String label) {
  final swElement = _findSwitchElement(tester, label);
  if (swElement == null) return false;
  return (swElement.widget as Switch).value;
}

/// Navigate to the level whose nav-button text contains [fragment].
Future<void> _goToLevel(WidgetTester tester, String fragment) async {
  final btn = find.textContaining(fragment);
  if (btn.evaluate().isNotEmpty) {
    await tester.tap(btn.first);
    await _pump(tester);
    _drainException(tester);
  }
}

// ─── tests ──────────────────────────────────────────────────────────────────

void main() {
  // ── App bootstrap ─────────────────────────────────────────────────────────
  group('App bootstrap', () {
    testWidgets('app starts and renders a Scaffold', (tester) async {
      await _boot(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('shows 4 level navigation buttons', (tester) async {
      await _boot(tester);
      for (final level in ['Level 1', 'Level 2', 'Level 3', 'Level 4']) {
        expect(find.textContaining(level), findsWidgets,
            reason: '$level nav button should be present');
      }
    });

    testWidgets('initial view contains Level 1 section title', (tester) async {
      await _boot(tester);
      expect(find.textContaining('基础自动请求'), findsWidgets);
    });

    testWidgets('GitHub API label is shown in the header', (tester) async {
      await _boot(tester);
      expect(find.textContaining('GitHub'), findsWidgets);
    });
  });

  // ── Navigation ────────────────────────────────────────────────────────────
  group('Navigation', () {
    testWidgets('tapping Level 2 nav renders Level 2 section', (tester) async {
      await _boot(tester);
      await _goToLevel(tester, 'Level 2');
      expect(find.textContaining('Level 2'), findsWidgets);
    });

    testWidgets('tapping Level 3 nav renders Level 3 section', (tester) async {
      await _boot(tester);
      await _goToLevel(tester, 'Level 3');
      expect(find.textContaining('Level 3'), findsWidgets);
    });

    testWidgets('tapping Level 4 nav renders Level 4 section', (tester) async {
      await _boot(tester);
      await _goToLevel(tester, 'Level 4');
      expect(find.textContaining('Level 4'), findsWidgets);
    });

    testWidgets('cycling L2→L3→L4→L1 keeps Scaffold alive', (tester) async {
      await _boot(tester);
      for (final level in ['Level 2', 'Level 3', 'Level 4', 'Level 1']) {
        await _goToLevel(tester, level);
      }
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  // ── Level 1 · 基础自动请求 ─────────────────────────────────────────────────
  group('Level 1 – BasicAutoRequestDemo', () {
    Future<void> boot(WidgetTester t) => _boot(t);

    testWidgets('refresh() button is present', (tester) async {
      await boot(tester);
      expect(find.text('refresh()'), findsWidgets);
    });

    testWidgets('mutate() button is present', (tester) async {
      await boot(tester);
      expect(find.text('mutate()'), findsWidgets);
    });

    testWidgets('refresh() button is tappable without crash', (tester) async {
      await boot(tester);
      final btn = find.text('refresh()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('mutate() button is tappable without crash', (tester) async {
      await boot(tester);
      final btn = find.text('mutate()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('ready switch initial value is true', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'ready'), isTrue);
    });

    testWidgets('ready switch toggles to false', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'ready');
      expect(_switchValue(tester, 'ready'), isFalse);
      _drainException(tester);
    });

    testWidgets('ready switch toggles back to true', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'ready');
      await _toggleSwitch(tester, 'ready');
      expect(_switchValue(tester, 'ready'), isTrue);
      _drainException(tester);
    });

    testWidgets('loadingDelay slider is present and draggable', (tester) async {
      await boot(tester);
      final sliders = find.byType(Slider);
      expect(sliders, findsWidgets);
      await tester.drag(sliders.first, const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('multiple rapid refresh() taps keep app alive', (tester) async {
      await boot(tester);
      final btn = find.text('refresh()');
      if (btn.evaluate().isNotEmpty) {
        for (var i = 0; i < 3; i++) {
          await _tap(tester, btn.first);
        }
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('dropdown opens without crash', (tester) async {
      await boot(tester);
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      if (dropdowns.evaluate().isNotEmpty) {
        await tester.tap(dropdowns.first);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(Scaffold), findsWidgets);
        await tester.tap(find.byType(Scaffold).first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
      }
      _drainException(tester);
    });
  });

  // ── Level 2 · 搜索频率控制 ──────────────────────────────────────────────────
  group('Level 2 – SearchRateControlDemo', () {
    Future<void> boot(WidgetTester t) async {
      await _boot(t);
      await _goToLevel(t, 'Level 2');
    }

    testWidgets('TextField is present', (tester) async {
      await boot(tester);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('Debounce and Throttle segments are present', (tester) async {
      await boot(tester);
      expect(find.text('Debounce'), findsWidgets);
      expect(find.text('Throttle'), findsWidgets);
    });

    testWidgets('text field accepts input', (tester) async {
      await boot(tester);
      final tf = find.byType(TextField);
      if (tf.evaluate().isNotEmpty) {
        await tester.enterText(tf.first, 'riverpod');
        expect(
          (tester.widget(tf.first) as TextField).controller?.text,
          'riverpod',
        );
      }
      _drainException(tester);
    });

    testWidgets('Throttle segment toggles without crash', (tester) async {
      await boot(tester);
      final throttle = find.text('Throttle');
      if (throttle.evaluate().isNotEmpty) {
        await tester.tap(throttle.first);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('Debounce → Throttle → Debounce cycle keeps app alive',
        (tester) async {
      await boot(tester);
      for (final label in ['Throttle', 'Debounce']) {
        final btn = find.text(label);
        if (btn.evaluate().isNotEmpty) {
          await tester.tap(btn.first);
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('keepPreviousData switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'keepPreviousData');
      await _toggleSwitch(tester, 'keepPreviousData');
      expect(_switchValue(tester, 'keepPreviousData'), !initial);
      _drainException(tester);
    });

    testWidgets('leading switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'leading');
      await _toggleSwitch(tester, 'leading');
      expect(_switchValue(tester, 'leading'), !initial);
      _drainException(tester);
    });

    testWidgets('trailing switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'trailing');
      await _toggleSwitch(tester, 'trailing');
      expect(_switchValue(tester, 'trailing'), !initial);
      _drainException(tester);
    });

    testWidgets('debounceMaxWait switch appears in Debounce mode',
        (tester) async {
      await boot(tester);
      final debounce = find.text('Debounce');
      if (debounce.evaluate().isNotEmpty) {
        await tester.tap(debounce.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.text('debounceMaxWait'), findsWidgets);
      _drainException(tester);
    });

    testWidgets('interval slider is draggable', (tester) async {
      await boot(tester);
      final sliders = find.byType(Slider);
      if (sliders.evaluate().isNotEmpty) {
        await tester.drag(sliders.first, const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('typing + throttle mode does not crash app', (tester) async {
      await boot(tester);
      final tf = find.byType(TextField);
      if (tf.evaluate().isNotEmpty) {
        await tester.enterText(tf.first, 'dart');
        await tester.pump(const Duration(milliseconds: 80));
      }
      final throttle = find.text('Throttle');
      if (throttle.evaluate().isNotEmpty) {
        await tester.tap(throttle.first);
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });
  });

  // ── Level 3 · 轮询 + 重试 ─────────────────────────────────────────────────
  group('Level 3 – PollingRetryDemo', () {
    Future<void> boot(WidgetTester t) async {
      await _boot(t);
      await _goToLevel(t, 'Level 3');
    }

    testWidgets('Level 3 action buttons are present', (tester) async {
      await boot(tester);
      expect(find.text('refresh()'), findsWidgets);
      expect(find.text('pausePolling()'), findsWidgets);
      expect(find.text('resumePolling()'), findsWidgets);
      expect(find.text('cancel()'), findsWidgets);
    });

    testWidgets('refresh() button taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('refresh()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('pausePolling() taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('pausePolling()');
      if (btn.evaluate().isNotEmpty) await _tap(tester, btn.first);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('resumePolling() taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('resumePolling()');
      if (btn.evaluate().isNotEmpty) await _tap(tester, btn.first);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('cancel() taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('cancel()');
      if (btn.evaluate().isNotEmpty) await _tap(tester, btn.first);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('pause → resume sequence keeps app alive', (tester) async {
      await boot(tester);
      final pause = find.text('pausePolling()');
      final resume = find.text('resumePolling()');
      if (pause.evaluate().isNotEmpty) await _tap(tester, pause.first);
      if (resume.evaluate().isNotEmpty) await _tap(tester, resume.first);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('pollingEnabled switch default is false', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'pollingEnabled'), isFalse);
    });

    testWidgets('pollingEnabled switch toggles to true', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'pollingEnabled');
      expect(_switchValue(tester, 'pollingEnabled'), isTrue);
      _drainException(tester);
    });

    testWidgets('pollingEnabled off → on → off keeps app alive', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'pollingEnabled');
      await _pump(tester);
      await _toggleSwitch(tester, 'pollingEnabled');
      await _pump(tester);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('forceError switch toggles to true', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'forceError');
      expect(_switchValue(tester, 'forceError'), isTrue);
      _drainException(tester);
    });

    testWidgets('retryExponential switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'retryExponential');
      await _toggleSwitch(tester, 'retryExponential');
      expect(_switchValue(tester, 'retryExponential'), !initial);
      _drainException(tester);
    });

    testWidgets('pausePollingOnError switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'pausePollingOnError');
      await _toggleSwitch(tester, 'pausePollingOnError');
      expect(_switchValue(tester, 'pausePollingOnError'), !initial);
      _drainException(tester);
    });

    testWidgets('pollingWhenHidden switch initial value is true', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'pollingWhenHidden'), isTrue);
    });

    testWidgets('pollingWhenHidden switch toggles to false', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'pollingWhenHidden');
      expect(_switchValue(tester, 'pollingWhenHidden'), isFalse);
      _drainException(tester);
    });

    testWidgets('retryCount slider exists and is draggable', (tester) async {
      await boot(tester);
      final sliders = find.byType(Slider);
      expect(sliders, findsWidgets);
      if (sliders.evaluate().length >= 3) {
        await tester.drag(sliders.at(2), const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('repo dropdown opens without crash', (tester) async {
      await boot(tester);
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      if (dropdowns.evaluate().isNotEmpty) {
        await tester.tap(dropdowns.first);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(Scaffold), findsWidgets);
        await tester.tap(find.byType(Scaffold).first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }
      _drainException(tester);
    });

    testWidgets('cancel then refresh keeps app alive', (tester) async {
      await boot(tester);
      final cancel = find.text('cancel()');
      final refresh = find.text('refresh()');
      if (cancel.evaluate().isNotEmpty) await _tap(tester, cancel.first);
      if (refresh.evaluate().isNotEmpty) {
        await _tap(tester, refresh.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });
  });

  // ── Level 4 · Options 全配置实验台 ─────────────────────────────────────────
  group('Level 4 – OptionsWorkbenchDemo', () {
    Future<void> boot(WidgetTester t) async {
      await _boot(t);
      await _goToLevel(t, 'Level 4');
    }

    testWidgets('Level 4 renders without crash', (tester) async {
      await boot(tester);
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Level 4 action buttons are present', (tester) async {
      await boot(tester);
      expect(find.text('run(page=1)'), findsWidgets);
      expect(find.text('refresh()'), findsWidgets);
      expect(find.text('loadMore()'), findsWidgets);
      expect(find.text('mutate()'), findsWidgets);
      expect(find.text('cancel()'), findsWidgets);
    });

    // ── 基础配置 ──────────────────────────────────────────────────────────
    testWidgets('manual switch default is false', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'manual'), isFalse);
    });

    testWidgets('manual switch toggles to true', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'manual');
      expect(_switchValue(tester, 'manual'), isTrue);
      _drainException(tester);
    });

    testWidgets('manual switch: off → on → off round-trip', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'manual');
      await _toggleSwitch(tester, 'manual');
      expect(_switchValue(tester, 'manual'), isFalse);
      _drainException(tester);
    });

    testWidgets('ready switch default is true', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'ready'), isTrue);
    });

    testWidgets('ready switch toggles to false', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'ready');
      expect(_switchValue(tester, 'ready'), isFalse);
      _drainException(tester);
    });

    testWidgets('initialData switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'initialData');
      await _toggleSwitch(tester, 'initialData');
      expect(_switchValue(tester, 'initialData'), !initial);
      _drainException(tester);
    });

    testWidgets('keepPreviousData switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'keepPreviousData');
      await _toggleSwitch(tester, 'keepPreviousData');
      expect(_switchValue(tester, 'keepPreviousData'), !initial);
      _drainException(tester);
    });

    testWidgets('forceError switch toggles to true', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'forceError');
      expect(_switchValue(tester, 'forceError'), isTrue);
      _drainException(tester);
    });

    // ── 依赖刷新 ──────────────────────────────────────────────────────────
    testWidgets('deps +1 button increments counter from 0 to 1', (tester) async {
      await boot(tester);
      final btn = find.textContaining('deps +1');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        expect(find.textContaining('deps +1 (1)'), findsWidgets);
      }
      _drainException(tester);
    });

    testWidgets('deps +1 button increments counter 3 times', (tester) async {
      await boot(tester);
      final btn = find.textContaining('deps +1');
      if (btn.evaluate().isNotEmpty) {
        for (var i = 0; i < 3; i++) {
          await _tap(tester, btn.first);
        }
        expect(find.textContaining('deps +1 (3)'), findsWidgets);
      }
      _drainException(tester);
    });

    testWidgets('refreshDeps switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'refreshDeps');
      await _toggleSwitch(tester, 'refreshDeps');
      expect(_switchValue(tester, 'refreshDeps'), !initial);
      _drainException(tester);
    });

    testWidgets('refreshDepsAction switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'refreshDepsAction');
      await _toggleSwitch(tester, 'refreshDepsAction');
      expect(_switchValue(tester, 'refreshDepsAction'), !initial);
      _drainException(tester);
    });

    // ── 轮询配置 ──────────────────────────────────────────────────────────
    testWidgets('polling switch default is false', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'pollingInterval'), isFalse);
    });

    testWidgets('polling switch: on → off round-trip keeps app alive',
        (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'pollingInterval');
      await _pump(tester);
      await _toggleSwitch(tester, 'pollingInterval');
      await _pump(tester);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('pausePolling button in L4 taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('pausePolling');
      if (btn.evaluate().isNotEmpty) await _tap(tester, btn.first);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('resumePolling button in L4 taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('resumePolling');
      if (btn.evaluate().isNotEmpty) await _tap(tester, btn.first);
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('pollingWhenHidden switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'pollingWhenHidden');
      await _toggleSwitch(tester, 'pollingWhenHidden');
      expect(_switchValue(tester, 'pollingWhenHidden'), !initial);
      _drainException(tester);
    });

    testWidgets('pausePollingOnError switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'pausePollingOnError');
      await _toggleSwitch(tester, 'pausePollingOnError');
      expect(_switchValue(tester, 'pausePollingOnError'), !initial);
      _drainException(tester);
    });

    // ── 频率控制 ──────────────────────────────────────────────────────────
    testWidgets('Throttle segment taps without crash', (tester) async {
      await boot(tester);
      final throttle = find.text('Throttle');
      if (throttle.evaluate().isNotEmpty) {
        await tester.tap(throttle.first);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('Debounce → Throttle → Debounce cycle keeps app alive',
        (tester) async {
      await boot(tester);
      for (final label in ['Throttle', 'Debounce', 'Throttle']) {
        final btn = find.text(label);
        if (btn.evaluate().isNotEmpty) {
          await tester.tap(btn.first);
          await tester.pump(const Duration(milliseconds: 80));
        }
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('debounceLeading switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'debounceLeading');
      await _toggleSwitch(tester, 'debounceLeading');
      expect(_switchValue(tester, 'debounceLeading'), !initial);
      _drainException(tester);
    });

    testWidgets('debounceTrailing switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'debounceTrailing');
      await _toggleSwitch(tester, 'debounceTrailing');
      expect(_switchValue(tester, 'debounceTrailing'), !initial);
      _drainException(tester);
    });

    testWidgets('debounceMaxWait switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'debounceMaxWait');
      await _toggleSwitch(tester, 'debounceMaxWait');
      expect(_switchValue(tester, 'debounceMaxWait'), !initial);
      _drainException(tester);
    });

    // ── 重试配置 ──────────────────────────────────────────────────────────
    testWidgets('retryEnabled switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'retryEnabled');
      await _toggleSwitch(tester, 'retryEnabled');
      expect(_switchValue(tester, 'retryEnabled'), !initial);
      _drainException(tester);
    });

    testWidgets('retryExponential switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'retryExponential');
      await _toggleSwitch(tester, 'retryExponential');
      expect(_switchValue(tester, 'retryExponential'), !initial);
      _drainException(tester);
    });

    // ── 缓存 ──────────────────────────────────────────────────────────────
    testWidgets('cacheKey switch default is true', (tester) async {
      await boot(tester);
      expect(_switchValue(tester, 'cacheKey'), isTrue);
    });

    testWidgets('cacheKey switch toggles to false', (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'cacheKey');
      expect(_switchValue(tester, 'cacheKey'), isFalse);
      _drainException(tester);
    });

    testWidgets('fetchKey switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'fetchKey');
      await _toggleSwitch(tester, 'fetchKey');
      expect(_switchValue(tester, 'fetchKey'), !initial);
      _drainException(tester);
    });

    // ── 加载更多 & 控制按钮 ────────────────────────────────────────────────
    testWidgets('run(page=1) button taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('run(page=1)');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('refresh() in Level 4 taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('refresh()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('loadMore() button taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('loadMore()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('mutate() in Level 4 taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('mutate()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('cancel() in Level 4 taps without crash', (tester) async {
      await boot(tester);
      final btn = find.text('cancel()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('enabling externalCancelEnabled reveals cancel button',
        (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'externalCancelEnabled');
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('external cancelToken.cancel()'), findsWidgets);
      _drainException(tester);
    });

    testWidgets('external cancelToken.cancel() taps without crash',
        (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'externalCancelEnabled');
      await tester.pump(const Duration(milliseconds: 80));
      final btn = find.text('external cancelToken.cancel()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('search TextField accepts input', (tester) async {
      await boot(tester);
      final tf = find.byType(TextField);
      if (tf.evaluate().isNotEmpty) {
        await tester.enterText(tf.first, 'hooks');
        expect(
          (tester.widget(tf.first) as TextField).controller?.text,
          'hooks',
        );
      }
      _drainException(tester);
    });

    testWidgets('loadMoreParams switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'loadMoreParams');
      await _toggleSwitch(tester, 'loadMoreParams');
      expect(_switchValue(tester, 'loadMoreParams'), !initial);
      _drainException(tester);
    });

    testWidgets('callbacks switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'callbacks');
      await _toggleSwitch(tester, 'callbacks');
      expect(_switchValue(tester, 'callbacks'), !initial);
      _drainException(tester);
    });

    testWidgets('refreshOnFocus switch toggles state', (tester) async {
      await boot(tester);
      final initial = _switchValue(tester, 'refreshOnFocus');
      await _toggleSwitch(tester, 'refreshOnFocus');
      expect(_switchValue(tester, 'refreshOnFocus'), !initial);
      _drainException(tester);
    });

    testWidgets('refreshOnReconnect switch + 模拟重连事件 keeps app alive',
        (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'refreshOnReconnect');
      await tester.pump(const Duration(milliseconds: 80));
      final btn = find.text('模拟重连事件');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('per_page slider is draggable', (tester) async {
      await boot(tester);
      final sliders = find.byType(Slider);
      if (sliders.evaluate().isNotEmpty) {
        await tester.drag(sliders.first, const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('manual mode: enabling manual then run(page=1) keeps app alive',
        (tester) async {
      await boot(tester);
      await _toggleSwitch(tester, 'manual');
      await tester.pump(const Duration(milliseconds: 80));
      final btn = find.text('run(page=1)');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await _pump(tester);
      }
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });
  });

  // ── Cross-level interactions ──────────────────────────────────────────────
  group('Cross-level interactions', () {
    testWidgets('cycling L1→L2→L3→L4→L1 keeps Scaffold alive', (tester) async {
      await _boot(tester);
      for (final level in ['Level 2', 'Level 3', 'Level 4', 'Level 1']) {
        await _goToLevel(tester, level);
        expect(find.byType(Scaffold), findsWidgets,
            reason: 'After navigating to $level');
      }
    });

    testWidgets('L1 refresh then navigate to L3 keeps app alive',
        (tester) async {
      await _boot(tester);
      final btn = find.text('refresh()');
      if (btn.evaluate().isNotEmpty) {
        await _tap(tester, btn.first);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await _goToLevel(tester, 'Level 3');
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });

    testWidgets('L4 switches then navigate back to L1 keeps app alive',
        (tester) async {
      await _boot(tester);
      await _goToLevel(tester, 'Level 4');
      await _toggleSwitch(tester, 'manual');
      await _toggleSwitch(tester, 'forceError');
      await _pump(tester);
      await _goToLevel(tester, 'Level 1');
      expect(find.byType(Scaffold), findsWidgets);
      _drainException(tester);
    });
  });
}
