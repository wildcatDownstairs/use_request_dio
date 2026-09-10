import 'package:flutter_test/flutter_test.dart';
import 'package:use_request_example/main.dart';

void main() {
  testWidgets('runs automatic and explicit-params examples', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('Automatic request completed'), findsOneWidget);

    await tester.tap(find.text('Load user 42'));
    await tester.pump();
    expect(find.text('Loaded user 42'), findsOneWidget);
  });
}
