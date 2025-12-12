import 'package:flutter_test/flutter_test.dart';
import 'package:use_request/use_request.dart';

void main() {
  test('Debouncer cancels previous pending future', () async {
    final debouncer = Debouncer<String>(
      duration: const Duration(milliseconds: 30),
    );

    final f1 = debouncer.call(() async {
      await Future.delayed(const Duration(milliseconds: 10));
      return 'a';
    });

    // Supersede quickly.
    final f2 = debouncer.call(() async {
      await Future.delayed(const Duration(milliseconds: 5));
      return 'b';
    });

    await expectLater(f1, throwsA(isA<DebounceCancelledException>()));
    expect(await f2, 'b');
  });
}

