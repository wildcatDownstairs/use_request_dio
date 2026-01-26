import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

import 'demo/use_request_demo_page.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'use_request Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const UseRequestDemoPage(),
    );
  }
}

/// NOTE (pub.dev Example tab)
///
/// pub.dev usually renders the Example tab from `example/lib/main.dart`.
/// The demo app below uses multiple files, so we also include a minimal
/// self-contained snippet here to make the usage visible.
class PubDevQuickStartSnippet extends HookWidget {
  const PubDevQuickStartSnippet({super.key});

  @override
  Widget build(BuildContext context) {
    // Use HttpRequestConfig + DioHttpAdapter to avoid importing Dio directly.
    final http = useMemoized(
      () => DioHttpAdapter.withBaseUrl('https://jsonplaceholder.typicode.com'),
    );
    final service = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        http,
        transformer: (res) => (res.data as Map).cast<String, dynamic>(),
      ),
      [http],
    );

    final req = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: UseRequestOptions(
        manual: false,
        defaultParams: HttpRequestConfig.get('/users/1'),
      ),
    );

    if (req.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (req.error != null) {
      return Center(child: Text('Error: ${req.error}'));
    }

    final name = (req.data?['name'] ?? '').toString();
    return Center(child: Text('User: $name'));
  }
}
