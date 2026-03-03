typedef PageParamBuilder<TParams, TData> =
    TParams Function(int page, int pageSize, TParams? origin);
typedef PageHasMore<TData> = bool Function(TData? data);
typedef PageDataMerger<TData> = TData Function(TData? previous, TData next);

/// 提供基于 page/pageSize 的辅助生成器
class PaginationHelpers {
  /// 默认的 hasMore：如果数据实现了长度属性且长度 < pageSize，则视为没有更多
  static bool defaultHasMore<TData>(TData? data, int pageSize) {
    if (data == null) return true;
    if (data is List) {
      return data.length >= pageSize;
    }
    return true;
  }

  /// 默认的 dataMerger：如果是 List 则拼接，否则返回新值
  /// 注意：泛型 List 合并需要外部传入正确类型化的 merger 以避免类型丢失
  static TData defaultMerger<TData>(TData? previous, TData next) {
    if (previous == null) return next;
    if (previous is List && next is List) {
      final merged = List.of(previous)..addAll(next);
      return merged as TData;
    }
    return next;
  }

  /// 根据 page/pageSize 生成 loadMoreParams
  ///
  /// 注意：此辅助方法通过内部计数器追踪当前页码。
  /// 每次调用返回的函数时，页码递增。
  ///
  /// 可选传入 [shouldReset] 来定义何时重置为 [startPage]。
  /// 典型场景：切换筛选条件或手动刷新后，下一次 loadMore 需要从第一页重新开始计数。
  static TParams Function(TParams lastParams, TData? data)
  pageParams<TParams, TData>({
    required int pageSize,
    required PageParamBuilder<TParams, TData> builder,
    int startPage = 1,
    bool Function(TParams lastParams, TData? data)? shouldReset,
  }) {
    int currentPage = startPage;
    return (lastParams, data) {
      if (shouldReset?.call(lastParams, data) ?? false) {
        currentPage = startPage;
      }
      currentPage++;
      return builder(currentPage, pageSize, lastParams);
    };
  }
}
