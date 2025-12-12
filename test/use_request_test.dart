import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  test('package exports core symbols', () {
    expect(useRequest, isNotNull);
    expect(const UseRequestOptions<void, void>(), isA<UseRequestOptions<void, void>>());
  });
}
