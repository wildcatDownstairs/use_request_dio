import 'cache.dart';

/// 简单的缓存策略辅助：基于 cacheKey 进行去重和 SWR 再验证。
///
/// ## SWR 行为说明
///
/// - 同时配置 `cacheTime` 和 `staleTime`：缓存在 `staleTime` 内被视为新鲜（直接返回，不后台刷新），
///   超过 `staleTime` 后视为陈旧（返回缓存数据同时后台刷新），超过 `cacheTime` 后缓存完全失效。
/// - 只配 `cacheTime` 不配 `staleTime`：缓存在有效期内始终可用，且始终在后台刷新（等同于 staleTime=0）。
/// - 只配 `staleTime` 不配 `cacheTime`：缓存永不过期，`staleTime` 控制何时后台刷新。
class CacheCoordinator<T> {
  final String cacheKey;
  final Duration? cacheTime;
  final Duration? staleTime;

  CacheCoordinator({required this.cacheKey, this.cacheTime, this.staleTime});

  /// 返回缓存数据（如果存在且未过期）。
  ///
  /// 无论数据是否陈旧，只要在 `cacheTime` 有效期内就返回（SWR 语义：stale-while-revalidate）。
  T? getFresh() {
    final entry = getCache<T>(cacheKey, cacheTime: cacheTime);
    if (entry == null) return null;
    return entry.data;
  }

  /// 是否陈旧，需要后台再验证。
  ///
  /// - 如果配置了 `staleTime`，数据年龄超过 `staleTime` 即视为陈旧。
  /// - 如果只配了 `cacheTime` 没配 `staleTime`，缓存始终视为陈旧（等同于 staleTime=0），
  ///   这样每次都会后台刷新，符合 SWR "stale-while-revalidate" 的默认语义。
  bool shouldRevalidate() {
    final entry = getCache<T>(cacheKey, cacheTime: cacheTime);
    if (entry == null) return true;
    if (staleTime == null) return true; // 无 staleTime → 始终后台刷新
    final age = DateTime.now().difference(entry.timestamp);
    return age > staleTime!;
  }

  void set(T data) => setCache<T>(cacheKey, data);
}
