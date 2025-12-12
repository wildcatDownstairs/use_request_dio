import 'dart:async';

/// loading 延迟控制器
/// 用于避免非常快速的请求出现闪烁式的 loading
class LoadingDelayController {
  final Duration delay;
  Timer? _timer;
  bool _shouldShowLoading = false;
  final void Function(bool loading) onLoadingChange;

  LoadingDelayController({required this.delay, required this.onLoadingChange});

  /// 开始请求（在延迟后显示 loading）
  void startLoading() {
    _shouldShowLoading = true;
    _timer?.cancel();

    _timer = Timer(delay, () {
      if (_shouldShowLoading) {
        onLoadingChange(true);
      }
    });
  }

  /// 立即结束 loading
  void endLoading() {
    _shouldShowLoading = false;
    _timer?.cancel();
    _timer = null;
    onLoadingChange(false);
  }

  /// 取消待触发的 loading 状态变化
  void cancel() {
    _shouldShowLoading = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 释放资源
  void dispose() {
    cancel();
  }

  /// 是否处于等待显示 loading 的计时中
  bool get isWaitingToShowLoading => _timer?.isActive ?? false;
}

/// 包装一个异步操作，自动处理 loading 延迟
Future<T> executeWithLoadingDelay<T>({
  required Future<T> Function() action,
  required Duration delay,
  required void Function(bool loading) onLoadingChange,
}) async {
  final controller = LoadingDelayController(
    delay: delay,
    onLoadingChange: onLoadingChange,
  );

  controller.startLoading();

  try {
    final result = await action();
    controller.endLoading();
    return result;
  } catch (e) {
    controller.endLoading();
    rethrow;
  }
}
