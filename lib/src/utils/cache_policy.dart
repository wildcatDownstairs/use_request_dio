import 'cache.dart';

/// 简单的缓存策略辅助：基于 cacheKey 进行去重和 SWR 再验证。
class CacheCoordinator<T> {
  final String cacheKey;
  final Duration? cacheTime;
  final Duration? staleTime;

  CacheCoordinator({
    required this.cacheKey,
    this.cacheTime,
    this.staleTime,
  });

  /// 返回缓存（如果存在且未过期）
  T? getFresh() {
    final entry = getCache<T>(cacheKey, cacheTime: cacheTime);
    if (entry == null) return null;
    if (staleTime == null) return entry.data;
    final age = DateTime.now().difference(entry.timestamp);
    if (age <= staleTime!) {
      return entry.data;
    }
    return entry.data; // 陈旧，但可用（SWR）
  }

  /// 是否陈旧，需要再验证
  bool shouldRevalidate() {
    if (staleTime == null) return false;
    final entry = getCache<T>(cacheKey, cacheTime: cacheTime);
    if (entry == null) return true;
    final age = DateTime.now().difference(entry.timestamp);
    return age > staleTime!;
  }

  void set(T data) => setCache<T>(cacheKey, data);
}
