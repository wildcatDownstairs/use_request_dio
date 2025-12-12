import 'dart:collection';

// ============================================================================
// RequestCacheEntry - 缓存条目
// ============================================================================

/// 请求缓存条目
///
/// 存储缓存的数据及其时间戳，用于判断缓存是否过期。
///
/// ## 示例
///
/// ```dart
/// final entry = RequestCacheEntry<User>(
///   data: user,
///   timestamp: DateTime.now(),
/// );
///
/// // 检查缓存年龄
/// final age = DateTime.now().difference(entry.timestamp);
/// print('缓存已存在 ${age.inSeconds} 秒');
/// ```
class RequestCacheEntry<T> {
  /// 缓存的数据
  final T? data;

  /// 缓存创建/更新的时间戳
  final DateTime timestamp;

  RequestCacheEntry({
    required this.data,
    required this.timestamp,
  });
}

// ============================================================================
// PendingRequestEntry - 进行中的请求条目
// ============================================================================

/// 进行中的请求条目（用于请求去重）
///
/// 当多个相同的请求同时发起时，后续请求可以复用第一个请求的 Future，
/// 避免重复发送网络请求。
///
/// ## 工作原理
///
/// ```
/// 请求 A (cacheKey: "user-1") -> 创建 Future，存入 pending
/// 请求 B (cacheKey: "user-1") -> 发现 pending 中有相同 key，复用 Future
/// 请求 C (cacheKey: "user-1") -> 同样复用
/// Future 完成 -> 从 pending 移除，结果存入 cache
/// 请求 A、B、C 都得到相同结果，但只发了一次网络请求
/// ```
class PendingRequestEntry<T> {
  /// 进行中的请求 Future
  final Future<T> future;

  /// 请求开始的时间戳
  final DateTime timestamp;

  PendingRequestEntry({
    required this.future,
    required this.timestamp,
  });
}

// ============================================================================
// RequestCache - 请求缓存管理器
// ============================================================================

/// 请求缓存管理器（静态单例）
///
/// 提供内存级别的请求缓存功能，支持：
/// - 数据缓存：存储请求结果，避免重复请求
/// - 请求去重：相同请求同时发起时，复用同一个 Future
/// - 过期管理：支持设置缓存有效期
///
/// ## 缓存数据
///
/// ```dart
/// // 存储缓存
/// RequestCache.set<User>('user-1', user);
///
/// // 获取缓存（带过期检查）
/// final entry = RequestCache.get<User>(
///   'user-1',
///   cacheTime: Duration(minutes: 5),
/// );
///
/// if (entry != null) {
///   print('缓存命中: ${entry.data}');
/// } else {
///   print('缓存未命中或已过期');
/// }
/// ```
///
/// ## 请求去重
///
/// ```dart
/// // 检查是否有进行中的相同请求
/// final pending = RequestCache.getPending<User>('user-1');
///
/// if (pending != null) {
///   // 复用进行中的请求
///   return pending;
/// }
///
/// // 没有进行中的请求，发起新请求
/// final future = fetchUser(1);
/// RequestCache.setPending<User>('user-1', future);
/// return future;
/// ```
///
/// ## 注意事项
///
/// - 这是一个静态单例，整个应用共享同一个缓存
/// - 缓存存储在内存中，应用重启后会清空
/// - 对于需要持久化的缓存，请使用 SharedPreferences 或数据库
class RequestCache {
  /// 缓存数据存储（key -> 缓存条目）
  static final Map<String, RequestCacheEntry<dynamic>> _store = HashMap();

  /// 进行中的请求存储（key -> 请求条目）
  static final Map<String, PendingRequestEntry<dynamic>> _pending = HashMap();

  /// 获取缓存数据
  ///
  /// [key] 缓存键
  /// [cacheTime] 缓存有效期，超过后返回 null
  ///
  /// 返回缓存条目，如果不存在或已过期则返回 null。
  ///
  /// ```dart
  /// // 获取 5 分钟内的缓存
  /// final entry = RequestCache.get<User>(
  ///   'user-1',
  ///   cacheTime: Duration(minutes: 5),
  /// );
  /// ```
  static RequestCacheEntry<T>? get<T>(String key, {Duration? cacheTime}) {
    final entry = _store[key];

    // 缓存不存在
    if (entry == null) return null;

    // 检查是否过期
    if (cacheTime != null) {
      final age = DateTime.now().difference(entry.timestamp);
      if (age > cacheTime) {
        // 缓存已过期，移除并返回 null
        _store.remove(key);
        return null;
      }
    }

    // 类型转换并返回
    return entry as RequestCacheEntry<T>?;
  }

  /// 设置缓存数据
  ///
  /// [key] 缓存键
  /// [data] 要缓存的数据
  ///
  /// 存储数据并记录当前时间戳。如果有相同 key 的 pending 请求，会自动清除。
  ///
  /// ```dart
  /// RequestCache.set<User>('user-1', user);
  /// ```
  static void set<T>(String key, T data) {
    _store[key] = RequestCacheEntry<T>(
      data: data,
      timestamp: DateTime.now(),
    );
    // 请求完成后清除 pending（请求已完成，不再需要去重）
    _pending.remove(key);
  }

  /// 获取进行中的请求 Future
  ///
  /// [key] 请求键
  ///
  /// 返回进行中的 Future，如果不存在则返回 null。
  /// 用于实现请求去重：多个相同请求只发一次。
  ///
  /// ```dart
  /// final pending = RequestCache.getPending<User>('user-1');
  /// if (pending != null) {
  ///   return pending;  // 复用进行中的请求
  /// }
  /// ```
  static Future<T>? getPending<T>(String key) {
    final entry = _pending[key];
    if (entry == null) return null;

    // 类型检查
    if (entry.future is Future<T>) {
      return entry.future as Future<T>?;
    }
    return null;
  }

  /// 存储进行中的请求 Future
  ///
  /// [key] 请求键
  /// [future] 请求的 Future
  ///
  /// 存储后，其他相同 key 的请求可以通过 [getPending] 获取并复用。
  /// Future 完成（无论成功或失败）后会自动清除。
  ///
  /// ```dart
  /// final future = fetchUser(1);
  /// RequestCache.setPending<User>('user-1', future);
  ///
  /// // future 完成后会自动从 pending 中移除
  /// ```
  static void setPending<T>(String key, Future<T> future) {
    _pending[key] = PendingRequestEntry<T>(
      future: future,
      timestamp: DateTime.now(),
    );

    // 当 future 完成时自动清理（无论成功或失败）
    future.whenComplete(() => _pending.remove(key));
  }

  /// 移除指定键的缓存
  ///
  /// 同时移除数据缓存和进行中的请求。
  ///
  /// ```dart
  /// RequestCache.remove('user-1');
  /// ```
  static void remove(String key) {
    _store.remove(key);
    _pending.remove(key);
  }

  /// 清空所有缓存
  ///
  /// 移除所有数据缓存和进行中的请求。
  /// 通常在用户登出或需要强制刷新时使用。
  ///
  /// ```dart
  /// // 用户登出时清空缓存
  /// RequestCache.clear();
  /// ```
  static void clear() {
    _store.clear();
    _pending.clear();
  }
}

// ============================================================================
// 便捷函数 - Convenience Functions
// ============================================================================

/// 获取缓存数据（便捷函数）
///
/// ```dart
/// final entry = getCache<User>('user-1', cacheTime: Duration(minutes: 5));
/// if (entry != null) {
///   print('用户: ${entry.data?.name}');
/// }
/// ```
RequestCacheEntry<T>? getCache<T>(String key, {Duration? cacheTime}) =>
    RequestCache.get<T>(key, cacheTime: cacheTime);

/// 设置缓存数据（便捷函数）
///
/// ```dart
/// setCache<User>('user-1', user);
/// ```
void setCache<T>(String key, T data) => RequestCache.set<T>(key, data);

/// 清除指定键的缓存（便捷函数）
///
/// ```dart
/// clearCacheEntry('user-1');
/// ```
void clearCacheEntry(String key) => RequestCache.remove(key);

/// 清空所有缓存（便捷函数）
///
/// ```dart
/// clearAllCache();
/// ```
void clearAllCache() => RequestCache.clear();

/// 获取进行中的请求（便捷函数）
///
/// ```dart
/// final pending = getPendingCache<User>('user-1');
/// if (pending != null) {
///   return pending;  // 复用进行中的请求
/// }
/// ```
Future<T>? getPendingCache<T>(String key) => RequestCache.getPending<T>(key);

/// 存储进行中的请求（便捷函数）
///
/// ```dart
/// final future = fetchUser(1);
/// setPendingCache<User>('user-1', future);
/// ```
void setPendingCache<T>(String key, Future<T> future) =>
    RequestCache.setPending<T>(key, future);
