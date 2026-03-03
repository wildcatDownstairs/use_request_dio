import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);

  group('PaginationHelpers.pageParams', () {
    test('increments page on each call starting from startPage', () {
      final pages = <int>[];
      final paramBuilder = PaginationHelpers.pageParams<Map<String, int>, String>(
        pageSize: 20,
        startPage: 1,
        builder: (page, pageSize, origin) {
          pages.add(page);
          return {'page': page, 'pageSize': pageSize};
        },
      );

      // Each call should increment the page
      paramBuilder({'page': 1, 'pageSize': 20}, null);
      paramBuilder({'page': 2, 'pageSize': 20}, null);
      paramBuilder({'page': 3, 'pageSize': 20}, null);

      expect(pages, [2, 3, 4]);
    });
  });

  group('loadMore with hasMore=false', () {
    test('returns error when hasMore is false', () async {
      final notifier = UseRequestNotifier<List<int>, int>(
        service: (p) async => [1, 2, 3],
        options: UseRequestOptions(
          manual: true,
          loadMoreParams: (lastParams, data) => lastParams + 1,
          dataMerger: (prev, next) => [...?prev, ...next],
          hasMore: (data) => false,
        ),
      );

      await notifier.runAsync(1);

      // hasMore should be false after the first request
      expect(notifier.currentState.hasMore, false);

      // loadMore should fail since hasMore is false
      expect(notifier.loadMoreAsync(), throwsA(isA<StateError>()));

      notifier.dispose();
    });
  });

  group('loadMore increments loadingMore flag', () {
    test('loadingMore is true during loadMore request', () async {
      final completer = Completer<List<int>>();
      final notifier = UseRequestNotifier<List<int>, int>(
        service: (p) {
          if (p == 1) return Future.value([1, 2, 3]);
          return completer.future;
        },
        options: UseRequestOptions(
          manual: true,
          loadMoreParams: (lastParams, data) => lastParams + 1,
          dataMerger: (prev, next) => [...?prev, ...next],
          hasMore: (data) => true,
        ),
      );

      await notifier.runAsync(1);
      expect(notifier.currentState.loadingMore, false);

      final loadFuture = notifier.loadMoreAsync();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.currentState.loadingMore, true);
      expect(notifier.currentState.loading, false);

      completer.complete([4, 5, 6]);
      await loadFuture;

      expect(notifier.currentState.loadingMore, false);

      notifier.dispose();
    });
  });
}
