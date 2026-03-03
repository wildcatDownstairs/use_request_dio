import 'package:flutter_test/flutter_test.dart';

import 'package:use_request/use_request.dart';

void main() {
  setUp(clearAllCache);

  tearDown(() {
    RequestCache.maxSize = 256;
  });

  group('LRU eviction', () {
    test('evicts oldest entry when maxSize exceeded', () {
      RequestCache.maxSize = 3;
      RequestCache.set<String>('a', 'alpha');
      RequestCache.set<String>('b', 'bravo');
      RequestCache.set<String>('c', 'charlie');
      expect(RequestCache.length, 3);

      // Adding a 4th entry should evict the oldest ('a')
      RequestCache.set<String>('d', 'delta');
      expect(RequestCache.length, 3);
      expect(RequestCache.get<String>('a'), isNull);
      expect(RequestCache.get<String>('b')?.data, 'bravo');
      expect(RequestCache.get<String>('c')?.data, 'charlie');
      expect(RequestCache.get<String>('d')?.data, 'delta');
    });
  });

  group('Type safety', () {
    test('returns null when stored type does not match requested type', () {
      RequestCache.set<String>('typed', 'hello');
      final result = RequestCache.get<int>('typed');
      expect(result, isNull);
    });
  });

  group('removeWhere', () {
    test('removes entries matching prefix', () {
      RequestCache.set<String>('user-1', 'alice');
      RequestCache.set<String>('user-2', 'bob');
      RequestCache.set<String>('post-1', 'first post');
      RequestCache.set<String>('post-2', 'second post');
      expect(RequestCache.length, 4);

      RequestCache.removeWhere((key) => key.startsWith('user-'));
      expect(RequestCache.length, 2);
      expect(RequestCache.get<String>('user-1'), isNull);
      expect(RequestCache.get<String>('user-2'), isNull);
      expect(RequestCache.get<String>('post-1')?.data, 'first post');
      expect(RequestCache.get<String>('post-2')?.data, 'second post');
    });
  });

  group('Cache length tracking', () {
    test('length reflects number of stored entries', () {
      expect(RequestCache.length, 0);
      RequestCache.set<String>('x', 'val');
      expect(RequestCache.length, 1);
      RequestCache.set<String>('y', 'val2');
      expect(RequestCache.length, 2);
      RequestCache.remove('x');
      expect(RequestCache.length, 1);
      RequestCache.clear();
      expect(RequestCache.length, 0);
    });
  });

  group('CacheCoordinator staleTime/cacheTime', () {
    test('fresh data is not revalidated within staleTime', () async {
      final coordinator = CacheCoordinator<String>(
        cacheKey: 'stale-test',
        staleTime: const Duration(milliseconds: 50),
      );

      coordinator.set('fresh-data');
      expect(coordinator.getFresh(), 'fresh-data');
      expect(coordinator.shouldRevalidate(), false);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(coordinator.shouldRevalidate(), true);
    });

    test('without staleTime but with cacheTime, shouldRevalidate is always true (SWR)', () {
      final coordinator = CacheCoordinator<String>(
        cacheKey: 'swr-test',
        cacheTime: const Duration(minutes: 5),
      );

      coordinator.set('some-data');
      expect(coordinator.getFresh(), 'some-data');
      // No staleTime → always revalidate (SWR default behavior)
      expect(coordinator.shouldRevalidate(), true);
    });
  });
}
