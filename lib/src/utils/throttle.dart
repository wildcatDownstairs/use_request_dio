import 'dart:async';

// ============================================================================
// Throttler - 节流器
// ============================================================================

/// 节流工具类
///
/// 在指定时间内最多执行一次，适用于：
/// - 滚动加载：滚动过程中限制加载频率
/// - 按钮防重复点击：防止用户快速多次点击
/// - 实时搜索：限制请求频率避免服务器压力
/// - 窗口大小调整：限制重新计算布局的频率
///
/// ## 工作原理
///
/// ```
/// 调用时间线：  |--A--B--C--|--D--|--E--|
///              0  100 200   500   700   900 (毫秒)
///
/// throttleInterval = 400ms, leading = true, trailing = true:
/// - A 调用（0ms）：立即执行（leading），开始节流窗口
/// - B 调用（100ms）：在节流窗口内，保存为待执行
/// - C 调用（200ms）：在节流窗口内，替换 B 为待执行
/// - 400ms：节流窗口结束，执行 C（trailing）
/// - D 调用（500ms）：立即执行（新的 leading）
/// - E 调用（700ms）：在节流窗口内，保存为待执行
/// - 900ms：节流窗口结束，执行 E（trailing）
///
/// 结果：执行了 A, C, D, E（跳过了 B）
/// ```
///
/// ## 与防抖的区别
///
/// | 特性 | 防抖 (Debounce) | 节流 (Throttle) |
/// |------|----------------|-----------------|
/// | 执行时机 | 等待静默期后执行 | 固定间隔执行 |
/// | 持续调用 | 永远不执行（直到停止） | 定期执行 |
/// | 适用场景 | 搜索输入 | 滚动加载 |
///
/// ## 基础用法
///
/// ```dart
/// final throttler = Throttler<void>(
///   duration: Duration(seconds: 1),
/// );
///
/// // 滚动监听
/// scrollController.addListener(() {
///   throttler.call(() async {
///     await loadMoreData();
///   });
/// });
/// ```
///
/// ## Leading 模式
///
/// ```dart
/// // 首次调用立即执行，后续被节流
/// final throttler = Throttler<void>(
///   duration: Duration(seconds: 1),
///   leading: true,
///   trailing: false,
/// );
/// ```
///
/// ## Trailing 模式
///
/// ```dart
/// // 节流窗口结束后执行最后一次调用
/// final throttler = Throttler<void>(
///   duration: Duration(seconds: 1),
///   leading: false,
///   trailing: true,
/// );
/// ```
class Throttler<T> {
  /// 节流间隔
  final Duration duration;

  /// 是否在首次调用时立即执行（leading edge）
  ///
  /// - `true`（默认）：首次调用立即执行
  /// - `false`：等待节流间隔后执行
  final bool leading;

  /// 是否在间隔结束后执行最后一次调用（trailing edge）
  ///
  /// - `true`（默认）：间隔结束后执行最后一次调用
  /// - `false`：丢弃节流窗口内的调用
  final bool trailing;

  /// 最大等待时间
  ///
  /// 即使持续有新调用，也会在此时间后强制执行。
  /// 用于确保某些操作不会被无限推迟。
  final Duration? maxWait;

  /// 上次执行时间
  DateTime? _lastExecutionTime;

  /// Trailing 定时器
  Timer? _trailingTimer;

  /// 待执行的 action
  Future<T> Function()? _pendingAction;

  /// 待执行的 Completer
  Completer<T>? _pendingCompleter;

  /// 首次调用时间（用于 maxWait 计算）
  DateTime? _firstCallTime;

  Throttler({
    required this.duration,
    this.leading = true,
    this.trailing = true,
    this.maxWait,
  });

  /// 执行节流包装后的异步函数
  ///
  /// [action] 要执行的异步函数
  /// [trailing] 可选覆盖实例的 trailing 设置
  ///
  /// 返回 Future，在实际执行后完成。如果被节流丢弃，会抛出 [ThrottleCancelledException]。
  ///
  /// ## 示例
  ///
  /// ```dart
  /// try {
  ///   final result = await throttler.call(() async {
  ///     return await loadMoreData();
  ///   });
  ///   print('加载完成: $result');
  /// } on ThrottleCancelledException {
  ///   print('调用被节流丢弃');
  /// }
  /// ```
  Future<T> call(Future<T> Function() action, {bool? trailing}) async {
    final now = DateTime.now();
    final useTrailing = trailing ?? this.trailing;

    // 首次调用记录时间
    _firstCallTime ??= now;

    // 计算距离上次执行的时间
    final elapsedSinceLast = _lastExecutionTime == null
        ? duration  // 首次调用，视为已过节流间隔
        : now.difference(_lastExecutionTime!);

    // 计算距离首次调用的时间
    final elapsedSinceFirst = now.difference(_firstCallTime!);

    // 判断是否可以执行 leading
    final canRunLeading = leading && (_lastExecutionTime == null || elapsedSinceLast >= duration);

    // maxWait 强制执行：超过最大等待时间，立即执行
    if (maxWait != null && elapsedSinceFirst >= maxWait!) {
      _firstCallTime = now;
      _lastExecutionTime = now;
      return action();
    }

    // Leading 立即执行：首次调用或已过节流间隔
    if (canRunLeading) {
      _lastExecutionTime = now;
      return action();
    }

    // 仍处于节流窗口内
    if (useTrailing) {
      // 保存待执行的 action
      _pendingAction = action;

      // 创建或复用 Completer
      if (_pendingCompleter == null || _pendingCompleter!.isCompleted) {
        _pendingCompleter = Completer<T>();
      }

      // 计算剩余等待时间
      final remaining = duration - elapsedSinceLast;

      // 重新设置 trailing 定时器
      _trailingTimer?.cancel();
      _trailingTimer = Timer(remaining, _executeTrailing);

      return _pendingCompleter!.future;
    } else {
      // trailing=false 时静默丢弃本次调用
      return Future.error(ThrottleCancelledException());
    }
  }

  /// 执行 trailing 调用
  void _executeTrailing() async {
    final action = _pendingAction;
    final completer = _pendingCompleter;

    if (action != null && completer != null && !completer.isCompleted) {
      // 更新执行时间
      _lastExecutionTime = DateTime.now();
      _firstCallTime = _lastExecutionTime;
      _pendingAction = null;

      try {
        final result = await action();
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      }
    }
  }

  /// 取消待执行的节流尾调用
  ///
  /// 取消后，等待中的 Future 会抛出 [ThrottleCancelledException]。
  ///
  /// ```dart
  /// throttler.cancel();
  /// ```
  void cancel() {
    _trailingTimer?.cancel();
    _trailingTimer = null;
    _pendingAction = null;

    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.completeError(ThrottleCancelledException());
    }
    _pendingCompleter = null;
  }

  /// 重置节流状态
  ///
  /// 清除上次执行时间，下次调用将被视为首次调用。
  ///
  /// ```dart
  /// throttler.reset();  // 重置后立即可以执行
  /// ```
  void reset() {
    _lastExecutionTime = null;
    _firstCallTime = null;
    cancel();
  }

  /// 释放资源
  ///
  /// 清理定时器和状态。
  void dispose() {
    cancel();
  }

  /// 当前是否处于节流中
  ///
  /// 如果上次执行后还未过节流间隔，返回 `true`。
  ///
  /// ```dart
  /// if (throttler.isThrottled) {
  ///   print('当前处于节流状态');
  /// }
  /// ```
  bool get isThrottled {
    if (_lastExecutionTime == null) return false;
    return DateTime.now().difference(_lastExecutionTime!) < duration;
  }
}

// ============================================================================
// ThrottleCancelledException - 节流取消异常
// ============================================================================

/// 节流取消异常
///
/// 当调用被节流丢弃时抛出（trailing=false 时）。
///
/// ## 处理示例
///
/// ```dart
/// try {
///   await throttler.call(() => loadData());
/// } on ThrottleCancelledException {
///   // 被节流丢弃，忽略即可
/// }
/// ```
class ThrottleCancelledException implements Exception {
  @override
  String toString() => 'ThrottleCancelledException: Call was throttled';
}

// ============================================================================
// createThrottler - 工厂函数
// ============================================================================

/// 创建节流器（工厂函数）
///
/// 便捷方法，等同于直接调用 `Throttler` 构造函数。
///
/// ## 示例
///
/// ```dart
/// final throttler = createThrottler<void>(
///   Duration(seconds: 1),
///   leading: true,
///   trailing: true,
/// );
/// ```
Throttler<T> createThrottler<T>(
  Duration duration, {
  bool leading = true,
  bool trailing = true,
  Duration? maxWait,
}) {
  return Throttler<T>(
    duration: duration,
    leading: leading,
    trailing: trailing,
    maxWait: maxWait,
  );
}
