import 'package:flutter_test/flutter_test.dart';
import 'package:use_request/use_request.dart';

void main() {
  test('UseRequestNotifier only updates state for active key', () async {
    Future<String> service(int p) async {
      // Make p=1 slower so it resolves after p=2.
      await Future.delayed(Duration(milliseconds: p == 1 ? 40 : 5));
      return 'v$p';
    }

    final notifier = UseRequestNotifier<String, int>(
      service: service,
      options: UseRequestOptions(manual: true, fetchKey: (p) => 'k$p'),
    );

    final f1 = notifier.runAsync(1);
    await Future.delayed(const Duration(milliseconds: 1));
    final f2 = notifier.runAsync(2);

    expect(await f2, 'v2');
    expect(await f1, 'v1');

    // State should reflect the last triggered key (2).
    expect(notifier.state.data, 'v2');
  });
}
