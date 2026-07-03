import 'package:dio/dio.dart';

/// 创建一个与多个外部 [CancelToken] 关联的内部令牌。
///
/// 任一外部令牌取消时，内部令牌都会同步取消；内部令牌取消时不会反向取消
/// 外部令牌。这样 `useRequest.cancel()` 始终可以取消内部令牌，同时调用方仍可
/// 通过 options 或单次请求配置中的令牌主动取消请求。
CancelToken createLinkedCancelToken([
  CancelToken? external,
  CancelToken? additionalExternal,
]) {
  final internal = CancelToken();

  for (final token in {external, additionalExternal}.whereType<CancelToken>()) {
    token.whenCancel.then((_) {
      if (!internal.isCancelled) {
        internal.cancel('Cancelled by linked token');
      }
    });
  }

  return internal;
}
