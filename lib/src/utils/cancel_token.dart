import 'package:dio/dio.dart';

/// 创建一个与外部 CancelToken 关联的内部 CancelToken。
/// 内部 token 会在外部被取消时同步取消，但不会反向取消外部 token，
/// 避免复用外部 token 被频繁 cancel 后失效的问题。
CancelToken createLinkedCancelToken([CancelToken? external]) {
  final internal = CancelToken();

  if (external != null) {
    external.whenCancel.then((_) {
      if (!internal.isCancelled) {
        internal.cancel('Cancelled by linked token');
      }
    });
  }

  return internal;
}
