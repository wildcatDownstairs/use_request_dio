import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';

// ============================================================================
// RetryConfig - 重试配置
// ============================================================================

/// 重试配置类
///
/// 定义重试行为的各项参数，包括最大重试次数、重试间隔、重试条件等。
///
/// ## 示例
///
/// ```dart
/// // 基础配置：最多重试 3 次，间隔 1 秒
/// final config = RetryConfig(
///   maxRetries: 3,
///   retryInterval: Duration(seconds: 1),
/// );
///
/// // 指数退避：1s -> 2s -> 4s -> 8s
/// final exponentialConfig = RetryConfig(
///   maxRetries: 4,
///   retryInterval: Duration(seconds: 1),
///   exponential: true,
/// );
///
/// // 自定义重试条件：仅重试特定状态码
/// final customConfig = RetryConfig(
///   maxRetries: 3,
///   shouldRetry: (error) {
///     if (error is DioException) {
///       final statusCode = error.response?.statusCode;
///       return statusCode == 429 || (statusCode != null && statusCode >= 500);
///     }
///     return false;
///   },
/// );
/// ```
class RetryConfig {
  /// 最大重试次数（不含首次请求）
  ///
  /// 例如设为 3 表示：首次请求 + 最多 3 次重试 = 最多 4 次请求
  final int maxRetries;

  /// 重试间隔（基础值）
  ///
  /// 当 [exponential] 为 `false` 时，每次重试使用固定间隔。
  /// 当 [exponential] 为 `true` 时，作为指数退避的基础值。
  final Duration retryInterval;

  /// 自定义重试条件判断函数
  ///
  /// 返回 `true` 表示应该重试该错误。
  /// 如果为 `null`，使用默认策略（网络错误和 5xx 服务器错误）。
  ///
  /// ```dart
  /// shouldRetry: (error) {
  ///   if (error is DioException) {
  ///     // 仅重试 429 (Too Many Requests) 和 5xx 错误
  ///     final statusCode = error.response?.statusCode;
  ///     return statusCode == 429 || (statusCode != null && statusCode >= 500);
  ///   }
  ///   return false;
  /// }
  /// ```
  final bool Function(dynamic error)? shouldRetry;

  /// 是否使用指数退避策略
  ///
  /// - `false`（默认）：固定间隔，每次重试等待 [retryInterval]
  /// - `true`：指数退避，等待时间按 2^n 增长
  ///
  /// 指数退避计算公式：`retryInterval * 2^(attempt-1)`
  ///
  /// 示例（retryInterval = 1s）：
  /// - 第 1 次重试：1s * 2^0 = 1s
  /// - 第 2 次重试：1s * 2^1 = 2s
  /// - 第 3 次重试：1s * 2^2 = 4s
  /// - 第 4 次重试：1s * 2^3 = 8s
  final bool exponential;

  const RetryConfig({
    this.maxRetries = 3,
    this.retryInterval = const Duration(seconds: 1),
    this.shouldRetry,
    this.exponential = false,
  });
}

// ============================================================================
// RetryExecutor - 重试执行器
// ============================================================================

/// 失败自动重试执行器
///
/// 封装重试逻辑，支持指数退避、自定义重试条件、取消等功能。
///
/// ## 基础用法
///
/// ```dart
/// final executor = RetryExecutor<String>(
///   config: RetryConfig(maxRetries: 3),
/// );
///
/// try {
///   final result = await executor.execute(() async {
///     final response = await dio.get('/api/data');
///     return response.data;
///   });
///   print('Success: $result');
/// } catch (e) {
///   print('Failed after retries: $e');
/// }
/// ```
///
/// ## 带回调的重试
///
/// ```dart
/// final result = await executor.execute(
///   () => fetchData(),
///   onRetry: (attempt, error) {
///     print('重试第 $attempt 次，原因: $error');
///   },
/// );
/// ```
///
/// ## 支持取消
///
/// ```dart
/// final cancelToken = CancelToken();
///
/// // 在其他地方取消
/// cancelToken.cancel('User cancelled');
///
/// try {
///   await executor.execute(
///     () => fetchData(),
///     cancelToken: cancelToken,
///   );
/// } on RetryCancelledException {
///   print('重试被取消');
/// }
/// ```
class RetryExecutor<T> {
  /// 重试配置
  final RetryConfig config;

  /// 关联的取消令牌
  CancelToken? _cancelToken;

  /// 是否已取消
  bool _isCancelled = false;

  RetryExecutor({required this.config});

  /// 执行带重试逻辑的异步函数
  ///
  /// [action] 要执行的异步函数
  /// [cancelToken] 可选的取消令牌，取消后会抛出 [RetryCancelledException]
  /// [onRetry] 每次重试时的回调，参数为 (重试次数, 错误)
  ///
  /// 返回执行成功的结果，或在重试耗尽后抛出最后一次的错误。
  ///
  /// ## 执行流程
  ///
  /// 1. 执行 action()
  /// 2. 如果成功，返回结果
  /// 3. 如果失败：
  ///    a. 检查是否已取消 → 抛出 RetryCancelledException
  ///    b. 检查是否应该重试（shouldRetry）
  ///    c. 检查是否还有剩余重试次数
  ///    d. 如果可以重试：调用 onRetry，等待间隔，跳转到步骤 1
  ///    e. 如果不能重试：抛出原始错误
  ///
  /// ## 示例
  ///
  /// ```dart
  /// final result = await executor.execute(
  ///   () async {
  ///     final response = await dio.get('/api/unstable');
  ///     if (response.statusCode != 200) {
  ///       throw DioException(
  ///         requestOptions: response.requestOptions,
  ///         response: response,
  ///       );
  ///     }
  ///     return response.data;
  ///   },
  ///   onRetry: (attempt, error) {
  ///     print('Retry #$attempt due to: $error');
  ///   },
  /// );
  /// ```
  Future<T> execute(
    Future<T> Function() action, {
    CancelToken? cancelToken,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    // 保存取消令牌引用，用于内部检查
    _cancelToken = cancelToken;
    _isCancelled = false;

    // 尝试次数计数器（从 1 开始，1 表示第一次重试）
    int attempts = 0;

    while (true) {
      attempts++;

      // 检查是否已取消（在执行前检查）
      if (_isCancelled || (cancelToken?.isCancelled ?? false)) {
        throw RetryCancelledException();
      }

      try {
        // 执行实际操作
        return await action();
      } catch (e) {
        // 执行后再次检查取消状态
        if (_isCancelled || (cancelToken?.isCancelled ?? false)) {
          throw RetryCancelledException();
        }

        // 判断是否应该重试此错误
        final shouldRetry = _shouldRetryError(e);

        // 判断是否还有剩余重试次数
        // attempts 从 1 开始，所以 attempts <= maxRetries 表示还可以重试
        final hasRemainingRetries = attempts <= config.maxRetries;

        if (shouldRetry && hasRemainingRetries) {
          // 调用重试回调
          onRetry?.call(attempts, e);

          // 计算下一次重试的等待时间
          final baseMs = config.retryInterval.inMilliseconds;

          // 指数退避因子：2^(attempts-1)，即 1, 2, 4, 8, ...
          // max(1, ...) 确保因子至少为 1
          final factor = max(1, 1 << (attempts - 1));

          // 计算实际延迟
          final nextDelay = config.exponential
              ? Duration(milliseconds: baseMs * factor)
              : config.retryInterval;

          // 等待后继续下一次重试
          await _delay(nextDelay);
          continue;
        }

        // 不应该重试或重试次数用尽，抛出原始错误
        rethrow;
      }
    }
  }

  /// 判断是否应该重试此错误
  ///
  /// 优先使用用户自定义的 [RetryConfig.shouldRetry]，
  /// 否则使用默认策略：重试网络错误和 5xx 服务器错误。
  bool _shouldRetryError(dynamic error) {
    // 如果提供了自定义判断函数，使用它
    if (config.shouldRetry != null) {
      return config.shouldRetry!(error);
    }

    // 默认重试策略：网络错误与服务端 5xx 错误
    if (error is DioException) {
      // 连接超时：无法建立连接
      // 发送超时：请求数据发送超时
      // 接收超时：等待响应超时
      // 连接错误：网络不可用等
      // 5xx 错误：服务器内部错误，通常是临时的
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          (error.response?.statusCode != null &&
              error.response!.statusCode! >= 500);
    }

    // 其他类型的错误默认不重试
    return false;
  }

  /// 等待指定时间（支持取消）
  Future<void> _delay(Duration duration) async {
    // 延迟前检查取消状态
    if (_isCancelled || (_cancelToken?.isCancelled ?? false)) {
      throw RetryCancelledException();
    }

    await Future.delayed(duration);
  }

  /// 取消当前重试
  ///
  /// 调用后，正在进行的重试会在下一个检查点抛出 [RetryCancelledException]。
  void cancel() {
    _isCancelled = true;
  }

  /// 释放资源
  ///
  /// 等同于调用 [cancel]，确保清理状态。
  void dispose() {
    cancel();
  }
}

// ============================================================================
// RetryCancelledException - 重试取消异常
// ============================================================================

/// 重试取消异常
///
/// 当重试过程被取消时抛出。可能的原因：
/// - 调用了 [RetryExecutor.cancel]
/// - 传入的 [CancelToken] 被取消
///
/// ## 处理示例
///
/// ```dart
/// try {
///   await executor.execute(() => fetchData());
/// } on RetryCancelledException {
///   print('用户取消了请求');
/// } on DioException catch (e) {
///   print('请求失败: $e');
/// }
/// ```
class RetryCancelledException implements Exception {
  @override
  String toString() => 'RetryCancelledException: Retry was cancelled';
}

// ============================================================================
// executeWithRetry - 函数式辅助
// ============================================================================

/// 执行带重试逻辑的异步函数（函数式 API）
///
/// 这是 [RetryExecutor] 的便捷封装，适用于一次性重试场景。
///
/// ## 参数
///
/// - [action] 要执行的异步函数
/// - [maxRetries] 最大重试次数，默认 3
/// - [retryInterval] 重试间隔，默认 1 秒
/// - [shouldRetry] 自定义重试条件，默认重试网络错误和 5xx
/// - [cancelToken] 取消令牌
/// - [onRetry] 重试回调
/// - [exponential] 是否使用指数退避，默认 false
///
/// ## 基础示例
///
/// ```dart
/// final data = await executeWithRetry(
///   () => dio.get('/api/data').then((r) => r.data),
///   maxRetries: 3,
/// );
/// ```
///
/// ## 指数退避示例
///
/// ```dart
/// final data = await executeWithRetry(
///   () => dio.get('/api/data').then((r) => r.data),
///   maxRetries: 5,
///   retryInterval: Duration(seconds: 1),
///   exponential: true,  // 1s -> 2s -> 4s -> 8s -> 16s
///   onRetry: (attempt, error) {
///     print('重试 $attempt/5');
///   },
/// );
/// ```
///
/// ## 自定义重试条件
///
/// ```dart
/// final data = await executeWithRetry(
///   () => dio.get('/api/data').then((r) => r.data),
///   shouldRetry: (error) {
///     // 仅重试 429 和 503 错误
///     if (error is DioException) {
///       final code = error.response?.statusCode;
///       return code == 429 || code == 503;
///     }
///     return false;
///   },
/// );
/// ```
///
/// ## 带取消支持
///
/// ```dart
/// final cancelToken = CancelToken();
///
/// // 5 秒后取消
/// Timer(Duration(seconds: 5), () => cancelToken.cancel());
///
/// try {
///   final data = await executeWithRetry(
///     () => dio.get('/api/slow'),
///     cancelToken: cancelToken,
///   );
/// } on RetryCancelledException {
///   print('请求已取消');
/// }
/// ```
Future<T> executeWithRetry<T>(
  Future<T> Function() action, {
  int maxRetries = 3,
  Duration retryInterval = const Duration(seconds: 1),
  bool Function(dynamic error)? shouldRetry,
  CancelToken? cancelToken,
  void Function(int attempt, dynamic error)? onRetry,
  bool exponential = false,
}) {
  // 创建配置和执行器
  final executor = RetryExecutor<T>(
    config: RetryConfig(
      maxRetries: maxRetries,
      retryInterval: retryInterval,
      shouldRetry: shouldRetry,
      exponential: exponential,
    ),
  );

  // 执行带重试的操作
  return executor.execute(action, cancelToken: cancelToken, onRetry: onRetry);
}
