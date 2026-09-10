import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: RequestExamples());
}

class RequestExamples extends HookWidget {
  const RequestExamples({super.key});

  @override
  Widget build(BuildContext context) {
    final automatic = useRequestFn(() async => 'Automatic request completed');
    final manual = useRequest<String, int>(
      (id) async => 'Loaded user $id',
      options: const UseRequestOptions(manual: true),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('useRequest minimal example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(automatic.loading ? 'Loading…' : automatic.data ?? 'No data'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => manual.run(42),
              child: const Text('Load user 42'),
            ),
            if (manual.data case final data?) Text(data),
          ],
        ),
      ),
    );
  }
}
