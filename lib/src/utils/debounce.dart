import 'dart:async';

// ============================================================================
// Debouncer - 防抖器
// ============================================================================

/// 防抖工具类
///
/// 在指定时间内多次调用只执行最后一次，适用于：
/// - 搜索输入框：用户停止输入后才发起搜索
/// - 窗口大小调整：调整完成后才重新布局
/// - 按钮防抖：防止快速多次点击
///
/// ## 工作原理
///
/// ```
/// 调用时间线：  |--A--B--C--|----D----|
///              0  100 200   500      1000 (毫秒)
///
/// debounceInterval = 300ms:
/// - A 调用：设置 300ms 定时器
/// - B 调用：取消 A 的定时器，设置新的 300ms 定时器
/// - C 调用：取消 B 的定时器，设置新的 300ms 定时器
/// - 500ms：C 的定时器触发，执行 C
/// - D 调用：设置 300ms 定时器
/// - 1300ms：D 的定时器触发，执行 D
///
/// 结果：只执行了 C 和 D
/// ```
///
/// ## 基础用法
///
/// ```dart
/// final debouncer = Debouncer<String>(
///   duration: Duration(milliseconds: 500),
/// );
///
/// // 在搜索输入框的 onChange 中
/// void onSearchChanged(String text) {
///   debouncer.call(() async {
///     final results = await searchApi(text);
///     setState(() => searchResults = results);
///     return text;
///   });
/// }
/// ```
///
/// ## Leading 模式
///
/// ```dart
/// // 首次调用立即执行，后续调用被防抖
/// final debouncer = Debouncer<void>(
///   duration: Duration(seconds: 1),
///   leading: true,
///   trailing: false,
/// );
///
/// // 快速点击按钮，只有第一次会立即执行
/// debouncer.call(() async {
///   await submitForm();
/// });
/// ```
///
/// ## MaxWait 限制
///
/// ```dart
/// // 即使持续有新调用，也会在 maxWait 后强制执行
/// final debouncer = Debouncer<void>(
///   duration: Duration(milliseconds: 500),
///   maxWait: Duration(seconds: 3),  // 最多等待 3 秒
/// );
/// ```
class Debouncer<T> {
  /// 防抖延迟时间
  final Duration duration;

  /// 是否在首次调用时立即执行（leading edge）
  ///
  /// - `false`（默认）：等待 [duration] 后执行
  /// - `true`：首次调用立即执行，后续调用被防抖
  final bool leading;

  /// 是否在延迟结束后执行（trailing edge）
  ///
  /// - `true`（默认）：延迟结束后执行最后一次调用
  /// - `false`：不执行延迟后的调用（通常与 `leading: true` 配合）
  final bool trailing;

  /// 最大等待时间
  ///
  /// 即使持续有新调用，也会在此时间后强制执行一次。
  /// 用于防止某些操作永远不执行的情况。
  final Duration? maxWait;

  /// 防抖定时器
  Timer? _timer;

  /// 最大等待定时器
  Timer? _maxWaitTimer;

  /// 等待中的 Completer
  Completer<T>? _pendingCompleter;

  /// 最后一次传入的 action
  Future<T> Function()? _lastAction;

  /// 是否已触发过 leading 调用
  bool _hasLeadingCalled = false;

  Debouncer({
    required this.duration,
    this.leading = false,
    this.trailing = true,
    this.maxWait,
  });

  /// 执行防抖包装后的异步函数
  ///
  /// [action] 要执行的异步函数
  ///
  /// 返回 Future，在实际执行后完成。如果被取消，会抛出 [DebounceCancelledException]。
  ///
  /// ## 示例
  ///
  /// ```dart
  /// try {
  ///   final result = await debouncer.call(() async {
  ///     return await searchApi(query);
  ///   });
  ///   print('搜索结果: $result');
  /// } on DebounceCancelledException {
  ///   print('搜索被取消（有新的搜索请求）');
  /// }
  /// ```
  Future<T> call(Future<T> Function() action) {
    // 每次新调用都会重置 debounce 窗口，但不应该重置整个 maxWait 周期。
    _timer?.cancel();

    // Leading 模式：首次调用立即执行
    final shouldCallLeading = leading && !_hasLeadingCalled;
    if (shouldCallLeading) {
      _hasLeadingCalled = true;
      _scheduleWindowTimer();
      _startMaxWaitTimerIfNeeded();
      return action();
    }

    if (!trailing) {
      _scheduleWindowTimer();
      _startMaxWaitTimerIfNeeded();
      return Future.error(DebounceCancelledException());
    }

    // 取消上一次排队中的 trailing 调用，避免 runAsync await 悬挂。
    // 注意：这里只取消“尚未执行”的 trailing future，不能影响已经开始执行的 leading future。
    final previousCompleter = _pendingCompleter;
    if (previousCompleter != null && !previousCompleter.isCompleted) {
      previousCompleter.completeError(DebounceCancelledException());
    }

    // 保存最后的 action
    _lastAction = action;

    // 创建新的 Completer 等待执行
    final completer = Completer<T>();
    _pendingCompleter = completer;
    _scheduleWindowTimer();
    _startMaxWaitTimerIfNeeded();
    return completer.future;
  }

  /// 启动/重置 debounce 窗口定时器。
  ///
  /// - 若存在排队中的 trailing 调用，窗口结束时执行最后一次；
  /// - 否则仅用于在 duration 后释放 leading 锁。
  void _scheduleWindowTimer() {
    _timer = Timer(duration, _handleWindowElapsed);
  }

  void _startMaxWaitTimerIfNeeded() {
    if (maxWait == null || _maxWaitTimer != null) return;
    _maxWaitTimer = Timer(maxWait!, _handleMaxWaitElapsed);
  }

  void _handleWindowElapsed() {
    if (trailing &&
        _pendingCompleter != null &&
        !_pendingCompleter!.isCompleted &&
        _lastAction != null) {
      _executePendingTrailing();
      return;
    }
    _resetWindow();
  }

  void _handleMaxWaitElapsed() {
    if (trailing &&
        _pendingCompleter != null &&
        !_pendingCompleter!.isCompleted &&
        _lastAction != null) {
      _executePendingTrailing();
      return;
    }
    _resetWindow();
  }

  void _resetWindow() {
    _timer?.cancel();
    _timer = null;
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    _hasLeadingCalled = false;
  }

  /// 执行当前排队中的 trailing 调用。
  ///
  /// 在真正 await action 前先重置窗口，确保 action 运行期间新的调用可以开启新周期，
  /// 而不会被旧的 debounce 状态错误阻塞。
  void _executePendingTrailing() {
    final completer = _pendingCompleter;
    final action = _lastAction;
    _pendingCompleter = null;
    _lastAction = null;
    _resetWindow();

    if (completer != null && action != null && !completer.isCompleted) {
      unawaited(_execute(action, completer));
    }
  }

  /// 执行 action 并完成 completer
  Future<void> _execute(
    Future<T> Function() action,
    Completer<T> completer,
  ) async {
    try {
      final result = await action();
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
  }

  /// 取消待执行的防抖调用
  ///
  /// 取消后，等待中的 Future 会抛出 [DebounceCancelledException]。
  ///
  /// ```dart
  /// debouncer.cancel();  // 取消待执行的调用
  /// ```
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    _hasLeadingCalled = false;

    // 通知等待中的 completer 已取消
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.completeError(DebounceCancelledException());
    }
    _pendingCompleter = null;
    _lastAction = null;
  }

  /// 释放资源
  ///
  /// 等同于 [cancel]，确保清理所有定时器和状态。
  void dispose() {
    cancel();
  }

  /// 是否存在等待中的调用
  ///
  /// ```dart
  /// if (debouncer.isPending) {
  ///   print('有待执行的调用');
  /// }
  /// ```
  bool get isPending =>
      (_timer?.isActive ?? false) ||
      (_maxWaitTimer?.isActive ?? false) ||
      (_pendingCompleter != null && !_pendingCompleter!.isCompleted);
}

// ============================================================================
// DebounceCancelledException - 防抖取消异常
// ============================================================================

/// 防抖取消异常
///
/// 当防抖调用被取消时抛出（通常是因为有新的调用）。
///
/// ## 处理示例
///
/// ```dart
/// try {
///   final result = await debouncer.call(() => searchApi(query));
///   updateResults(result);
/// } on DebounceCancelledException {
///   // 被新的搜索请求取消，忽略即可
/// }
/// ```
class DebounceCancelledException implements Exception {
  @override
  String toString() =>
      'DebounceCancelledException: Call was cancelled by a newer call';
}

// ============================================================================
// createDebouncer - 工厂函数
// ============================================================================

/// 创建防抖器（工厂函数）
///
/// 便捷方法，等同于直接调用 `Debouncer` 构造函数。
///
/// ## 示例
///
/// ```dart
/// final debouncer = createDebouncer<String>(
///   Duration(milliseconds: 500),
///   leading: false,
///   trailing: true,
/// );
/// ```
Debouncer<T> createDebouncer<T>(
  Duration duration, {
  bool leading = false,
  bool trailing = true,
  Duration? maxWait,
}) {
  return Debouncer<T>(
    duration: duration,
    leading: leading,
    trailing: trailing,
    maxWait: maxWait,
  );
}
