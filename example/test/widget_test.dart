// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('Example app renders demo home', (WidgetTester tester) async {
    // The example app uses Riverpod; provide a ProviderScope.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    // Basic smoke assertions for the demo home page.
    expect(find.text('useRequest'), findsOneWidget);
    expect(find.text('功能演示'), findsOneWidget);
    expect(find.text('基础用法'), findsWidgets);
  });
}
