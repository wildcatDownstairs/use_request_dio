import 'dart:async';

// ============================================================================
// PollingController - 轮询控制器
// ============================================================================

/// 轮询控制器
///
/// 按固定间隔重复执行异步任务，适用于：
/// - 实时数据刷新：股票价格、聊天消息、通知
/// - 状态监控：任务进度、系统状态
/// - 定时同步：后台数据同步
///
/// ## 基础用法
///
/// ```dart
/// final polling = PollingController<StockPrice>(
///   interval: Duration(seconds: 5),
///   action: () => fetchStockPrice('AAPL'),
///   onSuccess: (price) => updateUI(price),
///   onError: (error) => showError(error),
/// );
///
/// // 开始轮询
/// polling.start();
///
/// // 暂停轮询（可恢复）
/// polling.pause();
///
/// // 恢复轮询
/// polling.resume();
///
/// // 停止轮询（彻底停止）
/// polling.stop();
/// ```
///
/// ## 条件轮询
///
/// ```dart
/// final polling = PollingController<TaskStatus>(
///   interval: Duration(seconds: 2),
///   action: () => checkTaskStatus(taskId),
///   shouldPoll: () => !isTaskCompleted,  // 任务完成后停止
///   onSuccess: (status) {
///     if (status.isCompleted) {
///       polling.stop();
///     }
///   },
/// );
/// ```
///
/// ## 与应用生命周期集成
///
/// ```dart
/// class _MyWidgetState extends State<MyWidget> with WidgetsBindingObserver {
///   late PollingController<Data> _polling;
///
///   @override
///   void initState() {
///     super.initState();
///     WidgetsBinding.instance.addObserver(this);
///     _polling = PollingController(
///       interval: Duration(seconds: 10),
///       action: () => fetchData(),
///     );
///     _polling.start();
///   }
///
///   @override
///   void didChangeAppLifecycleState(AppLifecycleState state) {
///     if (state == AppLifecycleState.paused) {
///       _polling.pause();  // 后台时暂停
///     } else if (state == AppLifecycleState.resumed) {
///       _polling.resume();  // 前台时恢复
///     }
///   }
///
///   @override
///   void dispose() {
///     WidgetsBinding.instance.removeObserver(this);
///     _polling.dispose();
///     super.dispose();
///   }
/// }
/// ```
///
/// ## 状态图
///
/// ```
///                    start()
///     [已停止] ──────────────────> [运行中]
///        ^                           │
///        │ stop()                    │ pause()
///        │                           v
///        └─────────────────────── [已暂停]
///                                    │
///                                    │ resume()
///                                    v
///                                [运行中]
/// ```
class PollingController<T> {
  /// 轮询间隔
  final Duration interval;

  /// 轮询执行的异步操作
  final Future<T> Function() action;

  /// 轮询前的条件检查
  ///
  /// 返回 `false` 时跳过本次轮询，但不会停止轮询。
  /// 用于实现条件性轮询。
  ///
  /// ```dart
  /// shouldPoll: () => isUserLoggedIn && hasNetworkConnection
  /// ```
  final bool Function()? shouldPoll;

  /// 轮询成功回调
  final void Function(T result)? onSuccess;

  /// 轮询失败回调
  final void Function(dynamic error)? onError;

  /// 定时器
  Timer? _timer;

  /// 是否正在运行（已启动且未停止）
  bool _isRunning = false;

  /// 是否已暂停
  bool _isPaused = false;

  PollingController({
    required this.interval,
    required this.action,
    this.shouldPoll,
    this.onSuccess,
    this.onError,
  });

  /// 开始轮询
  ///
  /// 如果已经在运行，调用无效。
  /// 开始后会在 [interval] 后执行第一次轮询。
  ///
  /// ```dart
  /// polling.start();
  /// ```
  void start() {
    // 防止重复启动
    if (_isRunning) return;

    _isRunning = true;
    _isPaused = false;
    _scheduleNext();
  }

  /// 停止轮询（彻底停止）
  ///
  /// 停止后需要调用 [start] 重新开始。
  /// 与 [pause] 不同，stop 会重置所有状态。
  ///
  /// ```dart
  /// polling.stop();
  /// ```
  void stop() {
    _isRunning = false;
    _isPaused = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 暂停轮询（可恢复）
  ///
  /// 暂停后可以通过 [resume] 恢复。
  /// 适用于应用进入后台等场景。
  ///
  /// ```dart
  /// polling.pause();
  /// ```
  void pause() {
    // 未运行时不能暂停
    if (!_isRunning) return;

    _isPaused = true;
    _timer?.cancel();
    _timer = null;
  }

  /// 恢复轮询
  ///
  /// 从暂停状态恢复轮询。
  /// 如果未暂停，调用无效。
  ///
  /// ```dart
  /// polling.resume();
  /// ```
  void resume() {
    // 必须是运行中且已暂停才能恢复
    if (!_isRunning || !_isPaused) return;

    _isPaused = false;
    _scheduleNext();
  }

  /// 立即执行一次，然后继续轮询
  ///
  /// 取消当前的等待定时器，立即执行 action，
  /// 执行完成后重新开始计时。
  ///
  /// ```dart
  /// // 用户主动刷新，立即执行
  /// polling.executeNow();
  /// ```
  Future<void> executeNow() async {
    // 未运行时不执行
    if (!_isRunning) return;

    // 取消当前定时器
    _timer?.cancel();

    // 立即执行
    await _execute();

    // 如果仍在运行且未暂停，重新开始定时
    if (_isRunning && !_isPaused) {
      _scheduleNext();
    }
  }

  /// 安排下一次轮询
  void _scheduleNext() {
    // 检查状态
    if (!_isRunning || _isPaused) return;

    // 取消现有定时器
    _timer?.cancel();

    // 设置新定时器
    _timer = Timer(interval, () async {
      await _execute();

      // 执行完成后继续安排下一次
      if (_isRunning && !_isPaused) {
        _scheduleNext();
      }
    });
  }

  /// 执行轮询操作
  Future<void> _execute() async {
    // 检查状态
    if (!_isRunning || _isPaused) return;

    // 检查是否应该执行
    if (shouldPoll != null && !shouldPoll!()) {
      return;  // 条件不满足，跳过本次但不停止轮询
    }

    try {
      // 执行操作
      final result = await action();
      // 成功回调
      onSuccess?.call(result);
    } catch (e) {
      // 失败回调
      onError?.call(e);
    }
  }

  /// 释放资源
  ///
  /// 停止轮询并清理定时器。
  /// 通常在组件销毁时调用。
  ///
  /// ```dart
  /// @override
  /// void dispose() {
  ///   polling.dispose();
  ///   super.dispose();
  /// }
  /// ```
  void dispose() {
    stop();
  }

  /// 当前是否在轮询中（运行且未暂停）
  ///
  /// ```dart
  /// if (polling.isRunning) {
  ///   print('轮询进行中');
  /// }
  /// ```
  bool get isRunning => _isRunning && !_isPaused;

  /// 当前是否已暂停
  ///
  /// ```dart
  /// if (polling.isPaused) {
  ///   print('轮询已暂停');
  /// }
  /// ```
  bool get isPaused => _isPaused;
}

// ============================================================================
// createPolling - 工厂函数
// ============================================================================

/// 创建轮询控制器（工厂函数）
///
/// 便捷方法，等同于直接调用 `PollingController` 构造函数。
///
/// ## 示例
///
/// ```dart
/// final polling = createPolling<Data>(
///   interval: Duration(seconds: 5),
///   action: () => fetchData(),
///   onSuccess: (data) => updateUI(data),
///   onError: (e) => handleError(e),
/// );
///
/// polling.start();
/// ```
PollingController<T> createPolling<T>({
  required Duration interval,
  required Future<T> Function() action,
  bool Function()? shouldPoll,
  void Function(T result)? onSuccess,
  void Function(dynamic error)? onError,
}) {
  return PollingController<T>(
    interval: interval,
    action: action,
    shouldPoll: shouldPoll,
    onSuccess: onSuccess,
    onError: onError,
  );
}
