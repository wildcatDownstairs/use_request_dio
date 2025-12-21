import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// 类型定义 - Type Definitions
// ============================================================================

/// Service 函数类型，负责实际的异步操作（通常是网络请求）
///
/// [TData] 返回数据类型
/// [TParams] 请求参数类型
///
/// ## 示例
///
/// ```dart
/// // 简单的 GET 请求
/// Future<User> fetchUser(int userId) async {
///   final response = await dio.get('/users/$userId');
///   return User.fromJson(response.data);
/// }
///
/// // 带查询参数的请求
/// Future<List<Post>> fetchPosts(PostQuery query) async {
///   final response = await dio.get('/posts', queryParameters: query.toJson());
///   return (response.data as List).map((e) => Post.fromJson(e)).toList();
/// }
///
/// // 使用 HttpRequestConfig（推荐）
/// Future<User> fetchUser(HttpRequestConfig config) async {
///   final response = await adapter.request(config);
///   return User.fromJson(response.data);
/// }
/// ```
typedef Service<TData, TParams> = Future<TData> Function(TParams params);

/// 请求开始前的回调
///
/// 在每次请求发起前调用，可用于：
/// - 显示加载指示器
/// - 记录请求日志
/// - 重置错误状态
///
/// ```dart
/// onBefore: (params) {
///   print('开始请求，参数: $params');
///   errorMessage.value = null;
/// }
/// ```
typedef OnBefore<TParams> = void Function(TParams params);

/// 请求成功回调
///
/// 请求成功完成后调用，可用于：
/// - 显示成功提示
/// - 触发后续操作
/// - 更新本地状态
///
/// ```dart
/// onSuccess: (data, params) {
///   showToast('加载成功');
///   analytics.logEvent('fetch_success', {'userId': params});
/// }
/// ```
typedef OnSuccess<TData, TParams> = void Function(TData data, TParams params);

/// 请求失败回调
///
/// 请求失败时调用（包括网络错误、服务器错误、业务错误等），可用于：
/// - 显示错误提示
/// - 记录错误日志
/// - 触发重试逻辑
///
/// ```dart
/// onError: (error, params) {
///   if (error is DioException) {
///     showToast('网络错误: ${error.message}');
///   } else {
///     showToast('请求失败: $error');
///   }
/// }
/// ```
typedef OnError<TParams> = void Function(dynamic error, TParams params);

/// 请求完成回调（无论成功或失败都会触发）
///
/// 请求完成后调用，可用于：
/// - 隐藏加载指示器
/// - 执行清理操作
/// - 记录请求耗时
///
/// ```dart
/// onFinally: (params, data, error) {
///   hideLoading();
///   final duration = DateTime.now().difference(startTime);
///   print('请求耗时: ${duration.inMilliseconds}ms');
/// }
/// ```
typedef OnFinally<TData, TParams> =
    void Function(TParams params, TData? data, dynamic error);

/// 重试尝试回调
///
/// 每次重试时调用，可用于：
/// - 显示重试进度
/// - 记录重试日志
///
/// ```dart
/// onRetryAttempt: (attempt, error) {
///   print('第 $attempt 次重试，原因: $error');
///   retryCount.value = attempt;
/// }
/// ```
typedef OnRetryAttempt<TParams> = void Function(int attempt, dynamic error);

// ============================================================================
// UseRequestOptions - 配置项
// ============================================================================

/// useRequest 的配置项
///
/// 提供丰富的配置选项，支持：
/// - 请求控制：手动/自动请求、依赖刷新
/// - 轮询：定时自动刷新
/// - 防抖/节流：控制请求频率
/// - 重试：失败自动重试
/// - 缓存：SWR 缓存策略
/// - 分页：加载更多支持
/// - 超时：连接/发送/接收超时
///
/// ## 基础用法
///
/// ```dart
/// // 自动请求（组件加载时立即执行）
/// final result = useRequest<User, int>(
///   fetchUser,
///   options: UseRequestOptions(
///     defaultParams: 1,
///     onSuccess: (data, _) => print('用户: ${data.name}'),
///   ),
/// );
///
/// // 手动请求（需调用 run() 触发）
/// final result = useRequest<User, int>(
///   fetchUser,
///   options: UseRequestOptions(
///     manual: true,
///   ),
/// );
/// result.run(1);
/// ```
///
/// ## 防抖搜索
///
/// ```dart
/// final result = useRequest<List<User>, String>(
///   searchUsers,
///   options: UseRequestOptions(
///     manual: true,
///     debounceInterval: Duration(milliseconds: 500),
///   ),
/// );
///
/// // 输入框 onChange
/// onChanged: (text) => result.run(text)
/// ```
///
/// ## 轮询刷新
///
/// ```dart
/// final result = useRequest<StockPrice, String>(
///   fetchStockPrice,
///   options: UseRequestOptions(
///     defaultParams: 'AAPL',
///     pollingInterval: Duration(seconds: 5),
///     pollingWhenHidden: false, // 后台时暂停
///   ),
/// );
/// ```
///
/// ## 失败重试
///
/// ```dart
/// final result = useRequest<Data, void>(
///   fetchData,
///   options: UseRequestOptions(
///     retryCount: 3,
///     retryInterval: Duration(seconds: 1),
///     retryExponential: true, // 1s -> 2s -> 4s
///     onRetryAttempt: (attempt, error) {
///       print('重试 $attempt/3');
///     },
///   ),
/// );
/// ```
///
/// ## SWR 缓存
///
/// ```dart
/// final result = useRequest<User, int>(
///   fetchUser,
///   options: UseRequestOptions(
///     cacheKey: (userId) => 'user-$userId',
///     cacheTime: Duration(minutes: 30),  // 缓存 30 分钟
///     staleTime: Duration(minutes: 5),   // 5 分钟内为新鲜数据
///   ),
/// );
/// ```
///
/// ## 分页加载
///
/// ```dart
/// final result = useRequest<List<Post>, PageParams>(
///   fetchPosts,
///   options: UseRequestOptions(
///     defaultParams: PageParams(page: 1, size: 20),
///     loadMoreParams: (last, data) => PageParams(
///       page: last.page + 1,
///       size: last.size,
///     ),
///     dataMerger: (prev, next) => [...?prev, ...next],
///     hasMore: (data) => data != null && data.length >= 20,
///   ),
/// );
///
/// // 加载更多
/// result.loadMore();
/// ```
class UseRequestOptions<TData, TParams> {
  // ---------------------------------------------------------------------------
  // 请求控制 - Request Control
  // ---------------------------------------------------------------------------

  /// 是否手动触发请求
  ///
  /// - `false`（默认）：组件加载时自动执行请求（若未提供 [defaultParams]，则传递 `null`）
  /// - `true`：需要手动调用 `run()` 或 `runAsync()` 触发请求
  ///
  /// ```dart
  /// // 自动请求
  /// useRequest(fetchUser, options: UseRequestOptions(defaultParams: 1));
  ///
  /// // 自动请求（无参/默认参数为 null）
  /// useRequest<User, dynamic>(([params]) => fetchUser());
  ///
  /// // 手动请求
  /// final result = useRequest(fetchUser, options: UseRequestOptions(manual: true));
  /// result.run(1);  // 手动触发
  /// ```
  final bool manual;

  /// 是否允许请求准备就绪
  ///
  /// 类似 ahooks 的 `ready` 选项：
  /// - `true`（默认）：正常执行请求
  /// - `false`：阻止自动请求和轮询，直到变为 `true`
  ///
  /// 适用场景：
  /// - 等待依赖数据加载完成
  /// - 等待用户登录
  /// - 条件性请求
  ///
  /// ```dart
  /// final isLoggedIn = useState(false);
  ///
  /// final result = useRequest(
  ///   fetchUserProfile,
  ///   options: UseRequestOptions(
  ///     ready: isLoggedIn.value,  // 登录后才请求
  ///   ),
  /// );
  /// ```
  final bool ready;

  /// 初始请求参数
  ///
  /// 用于自动请求时的默认参数。当 `manual: false` 时，若未提供此参数，默认传递 `null`。
  ///
  /// ```dart
  /// useRequest(fetchUser, options: UseRequestOptions(defaultParams: 1));
  /// ```
  final TParams? defaultParams;

  /// 依赖变化时自动刷新（仅 Hook 版有效）
  ///
  /// 类似 ahooks 的 `refreshDeps`，当依赖项变化时自动重新请求。
  ///
  /// ```dart
  /// final categoryId = useState(1);
  ///
  /// final result = useRequest(
  ///   fetchProducts,
  ///   options: UseRequestOptions(
  ///     defaultParams: categoryId.value,
  ///     refreshDeps: [categoryId.value],  // categoryId 变化时刷新
  ///   ),
  /// );
  /// ```
  final List<Object?>? refreshDeps;

  /// 依赖变化时触发的自定义动作
  ///
  /// 默认行为是重新执行请求，可通过此选项自定义。
  ///
  /// ```dart
  /// refreshDepsAction: () {
  ///   // 自定义刷新逻辑
  ///   result.run(newParams);
  /// }
  /// ```
  final VoidCallback? refreshDepsAction;

  // ---------------------------------------------------------------------------
  // 超时配置 - Timeout Configuration
  // ---------------------------------------------------------------------------

  /// 连接超时时间
  ///
  /// 建立 TCP 连接的最大等待时间。超时后抛出 `DioExceptionType.connectionTimeout`。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   connectTimeout: Duration(seconds: 10),
  /// )
  /// ```
  final Duration? connectTimeout;

  /// 接收超时时间
  ///
  /// 等待服务器响应数据的最大时间。超时后抛出 `DioExceptionType.receiveTimeout`。
  /// 适用于大文件下载或慢速 API。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   receiveTimeout: Duration(seconds: 30),
  /// )
  /// ```
  final Duration? receiveTimeout;

  /// 发送超时时间
  ///
  /// 发送请求数据（如文件上传）的最大时间。超时后抛出 `DioExceptionType.sendTimeout`。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   sendTimeout: Duration(minutes: 5),  // 大文件上传
  /// )
  /// ```
  final Duration? sendTimeout;

  // ---------------------------------------------------------------------------
  // 轮询配置 - Polling Configuration
  // ---------------------------------------------------------------------------

  /// 轮询间隔
  ///
  /// 设置后会按指定间隔自动重复请求。设为 `null` 禁用轮询。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   pollingInterval: Duration(seconds: 5),  // 每 5 秒刷新
  /// )
  /// ```
  final Duration? pollingInterval;

  /// 应用失焦/后台时是否继续轮询
  ///
  /// - `true`（默认）：后台时继续轮询
  /// - `false`：后台时暂停，前台时恢复
  ///
  /// 建议设为 `false` 以节省资源和流量。
  final bool pollingWhenHidden;

  /// 轮询遇到错误时是否自动暂停
  ///
  /// - `false`（默认）：出错后继续下一轮轮询
  /// - `true`：出错后暂停，需手动调用 `refresh()` 恢复
  final bool pausePollingOnError;

  /// 轮询错误重试间隔
  ///
  /// 当 [pausePollingOnError] 为 `true` 且出错时，使用此间隔尝试恢复。
  final Duration? pollingRetryInterval;

  // ---------------------------------------------------------------------------
  // 防抖配置 - Debounce Configuration
  // ---------------------------------------------------------------------------

  /// 防抖间隔
  ///
  /// 在指定时间内多次调用只执行最后一次。适用于搜索输入框等场景。
  ///
  /// **注意**：不能与 [throttleInterval] 同时设置。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   debounceInterval: Duration(milliseconds: 500),
  /// )
  /// ```
  final Duration? debounceInterval;

  /// 防抖是否触发 leading（首次立即执行）
  ///
  /// - `false`（默认）：延迟后执行
  /// - `true`：首次立即执行，后续延迟
  final bool debounceLeading;

  /// 防抖是否触发 trailing（延迟后执行）
  ///
  /// - `true`（默认）：延迟结束后执行
  /// - `false`：不执行延迟后的调用
  final bool debounceTrailing;

  /// 防抖最大等待时间
  ///
  /// 即使持续有新调用，也会在此时间后强制执行一次。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   debounceInterval: Duration(milliseconds: 500),
  ///   debounceMaxWait: Duration(seconds: 3),  // 最多等待 3 秒
  /// )
  /// ```
  final Duration? debounceMaxWait;

  // ---------------------------------------------------------------------------
  // 节流配置 - Throttle Configuration
  // ---------------------------------------------------------------------------

  /// 节流间隔
  ///
  /// 在指定时间内最多执行一次。适用于滚动加载、按钮防重复点击等场景。
  ///
  /// **注意**：不能与 [debounceInterval] 同时设置。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   throttleInterval: Duration(seconds: 1),
  /// )
  /// ```
  final Duration? throttleInterval;

  /// 节流是否触发 leading（首次立即执行）
  ///
  /// - `true`（默认）：首次立即执行
  /// - `false`：等待节流间隔后执行
  final bool throttleLeading;

  /// 节流是否触发 trailing（间隔结束后执行最后一次）
  ///
  /// - `true`（默认）：间隔结束后执行最后一次调用
  /// - `false`：丢弃间隔内的调用
  final bool throttleTrailing;

  // ---------------------------------------------------------------------------
  // 重试配置 - Retry Configuration
  // ---------------------------------------------------------------------------

  /// 失败自动重试次数
  ///
  /// 请求失败后的最大重试次数（不含首次请求）。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   retryCount: 3,  // 最多重试 3 次，总共请求 4 次
  /// )
  /// ```
  final int? retryCount;

  /// 重试间隔
  ///
  /// 每次重试之间的等待时间。当 [retryExponential] 为 `true` 时作为基础值。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   retryInterval: Duration(seconds: 1),
  /// )
  /// ```
  final Duration? retryInterval;

  /// 是否使用指数退避重试
  ///
  /// - `true`（默认）：重试间隔指数增长（1s -> 2s -> 4s -> 8s...）
  /// - `false`：固定间隔重试
  ///
  /// 指数退避可以减轻服务器压力，推荐在生产环境使用。
  final bool retryExponential;

  // ---------------------------------------------------------------------------
  // 加载状态配置 - Loading State Configuration
  // ---------------------------------------------------------------------------

  /// loading 延迟显示时间
  ///
  /// 请求在此时间内完成则不显示 loading 状态，避免快速请求时的闪烁。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   loadingDelay: Duration(milliseconds: 300),  // 300ms 内完成不显示 loading
  /// )
  /// ```
  final Duration? loadingDelay;

  // ---------------------------------------------------------------------------
  // 自动刷新配置 - Auto Refresh Configuration
  // ---------------------------------------------------------------------------

  /// 聚焦时是否自动刷新
  ///
  /// 当应用从后台回到前台时自动刷新数据。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   refreshOnFocus: true,
  /// )
  /// ```
  final bool refreshOnFocus;

  /// 网络重连时是否自动刷新
  ///
  /// 需要配合 [reconnectStream] 使用，提供网络状态变化流。
  final bool refreshOnReconnect;

  /// 外部提供的重连流
  ///
  /// 流发出 `true` 时表示网络恢复，会触发刷新。
  ///
  /// ```dart
  /// // 使用 connectivity_plus 包
  /// final connectivityStream = Connectivity()
  ///     .onConnectivityChanged
  ///     .map((result) => result != ConnectivityResult.none);
  ///
  /// UseRequestOptions(
  ///   refreshOnReconnect: true,
  ///   reconnectStream: connectivityStream,
  /// )
  /// ```
  final Stream<bool>? reconnectStream;

  // ---------------------------------------------------------------------------
  // 缓存配置 - Cache Configuration
  // ---------------------------------------------------------------------------

  /// 缓存 key 生成函数
  ///
  /// 根据请求参数生成唯一的缓存键。相同 key 的请求会复用缓存。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   cacheKey: (userId) => 'user-$userId',
  /// )
  /// ```
  final String Function(TParams params)? cacheKey;

  /// 缓存有效期
  ///
  /// 缓存数据的最大保留时间，超过后自动失效。`null` 表示不过期。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   cacheTime: Duration(minutes: 30),
  /// )
  /// ```
  final Duration? cacheTime;

  /// 数据新鲜时间（SWR staleTime）
  ///
  /// 在此时间内，数据被视为"新鲜"，直接返回缓存不发起请求。
  /// 超过此时间，先返回缓存（stale），同时后台刷新（revalidate）。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   staleTime: Duration(minutes: 5),   // 5 分钟内为新鲜数据
  ///   cacheTime: Duration(minutes: 30),  // 缓存保留 30 分钟
  /// )
  /// ```
  final Duration? staleTime;

  // ---------------------------------------------------------------------------
  // 并发控制 - Concurrency Control
  // ---------------------------------------------------------------------------

  /// 并发隔离 key 生成函数
  ///
  /// 用于同时管理多个独立的请求实例，每个 key 有独立的状态。
  ///
  /// ```dart
  /// // 同时请求多个用户，各自独立管理
  /// UseRequestOptions(
  ///   fetchKey: (userId) => 'user-$userId',
  /// )
  /// ```
  final String Function(TParams params)? fetchKey;

  // ---------------------------------------------------------------------------
  // 分页配置 - Pagination Configuration
  // ---------------------------------------------------------------------------

  /// 加载更多参数生成函数
  ///
  /// 根据当前参数和数据生成下一页的请求参数。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   loadMoreParams: (lastParams, data) => PageParams(
  ///     page: lastParams.page + 1,
  ///     size: lastParams.size,
  ///   ),
  /// )
  /// ```
  final TParams Function(TParams lastParams, TData? data)? loadMoreParams;

  /// 数据合并函数
  ///
  /// 定义如何合并旧数据和新数据（用于分页场景）。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   dataMerger: (previous, next) => [...?previous, ...next],
  /// )
  /// ```
  final TData Function(TData? previous, TData next)? dataMerger;

  /// 是否还有更多数据判断函数
  ///
  /// 返回 `false` 时，`loadMore()` 不会发起新请求。
  ///
  /// ```dart
  /// UseRequestOptions(
  ///   hasMore: (data) => data != null && data.length >= 20,
  /// )
  /// ```
  final bool Function(TData? data)? hasMore;

  // ---------------------------------------------------------------------------
  // 请求控制 - Request Control
  // ---------------------------------------------------------------------------

  /// 自定义 CancelToken
  ///
  /// 用于外部控制请求取消。内部会创建关联的 token，不会影响外部 token 的复用。
  ///
  /// ```dart
  /// final cancelToken = CancelToken();
  ///
  /// UseRequestOptions(
  ///   cancelToken: cancelToken,
  /// )
  ///
  /// // 外部取消
  /// cancelToken.cancel('User cancelled');
  /// ```
  final CancelToken? cancelToken;

  // ---------------------------------------------------------------------------
  // 生命周期回调 - Lifecycle Callbacks
  // ---------------------------------------------------------------------------

  /// 请求开始前的回调
  final OnBefore<TParams>? onBefore;

  /// 请求成功回调
  final OnSuccess<TData, TParams>? onSuccess;

  /// 请求失败回调
  final OnError<TParams>? onError;

  /// 请求完成回调（成功或失败都会触发）
  final OnFinally<TData, TParams>? onFinally;

  /// 重试尝试回调
  final OnRetryAttempt<TParams>? onRetryAttempt;

  // ---------------------------------------------------------------------------
  // 构造函数 - Constructor
  // ---------------------------------------------------------------------------

  const UseRequestOptions({
    // 请求控制
    this.manual = false,
    this.ready = true,
    this.defaultParams,
    this.refreshDeps,
    this.refreshDepsAction,
    // 超时配置
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    // 轮询配置
    this.pollingInterval,
    this.pollingWhenHidden = true,
    this.pausePollingOnError = false,
    this.pollingRetryInterval,
    // 防抖配置
    this.debounceInterval,
    this.debounceLeading = false,
    this.debounceTrailing = true,
    this.debounceMaxWait,
    // 节流配置
    this.throttleInterval,
    this.throttleLeading = true,
    this.throttleTrailing = true,
    // 重试配置
    this.retryCount,
    this.retryInterval,
    this.retryExponential = true,
    // 加载状态
    this.loadingDelay,
    // 自动刷新
    this.refreshOnFocus = false,
    this.refreshOnReconnect = false,
    this.reconnectStream,
    // 缓存配置
    this.cacheKey,
    this.cacheTime,
    this.staleTime,
    // 并发控制
    this.fetchKey,
    // 分页配置
    this.loadMoreParams,
    this.dataMerger,
    this.hasMore,
    // 请求控制
    this.cancelToken,
    // 生命周期回调
    this.onBefore,
    this.onSuccess,
    this.onError,
    this.onFinally,
    this.onRetryAttempt,
  });

  /// 复制并修改配置
  ///
  /// 创建当前配置的副本，可选择性地覆盖某些选项。
  ///
  /// ```dart
  /// final baseOptions = UseRequestOptions(
  ///   retryCount: 3,
  ///   loadingDelay: Duration(milliseconds: 300),
  /// );
  ///
  /// final customOptions = baseOptions.copyWith(
  ///   manual: true,
  /// );
  /// ```
  UseRequestOptions<TData, TParams> copyWith({
    bool? manual,
    bool? ready,
    TParams? defaultParams,
    List<Object?>? refreshDeps,
    VoidCallback? refreshDepsAction,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Duration? pollingInterval,
    bool? pollingWhenHidden,
    bool? pausePollingOnError,
    Duration? pollingRetryInterval,
    Duration? debounceInterval,
    bool? debounceLeading,
    bool? debounceTrailing,
    Duration? debounceMaxWait,
    Duration? throttleInterval,
    bool? throttleLeading,
    bool? throttleTrailing,
    int? retryCount,
    Duration? retryInterval,
    bool? retryExponential,
    Duration? loadingDelay,
    bool? refreshOnFocus,
    bool? refreshOnReconnect,
    Stream<bool>? reconnectStream,
    String Function(TParams params)? cacheKey,
    Duration? cacheTime,
    Duration? staleTime,
    String Function(TParams params)? fetchKey,
    TParams Function(TParams lastParams, TData? data)? loadMoreParams,
    TData Function(TData? previous, TData next)? dataMerger,
    bool Function(TData? data)? hasMore,
    CancelToken? cancelToken,
    OnBefore<TParams>? onBefore,
    OnSuccess<TData, TParams>? onSuccess,
    OnError<TParams>? onError,
    OnFinally<TData, TParams>? onFinally,
    OnRetryAttempt<TParams>? onRetryAttempt,
  }) {
    return UseRequestOptions<TData, TParams>(
      manual: manual ?? this.manual,
      ready: ready ?? this.ready,
      defaultParams: defaultParams ?? this.defaultParams,
      refreshDeps: refreshDeps ?? this.refreshDeps,
      refreshDepsAction: refreshDepsAction ?? this.refreshDepsAction,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      pollingInterval: pollingInterval ?? this.pollingInterval,
      pollingWhenHidden: pollingWhenHidden ?? this.pollingWhenHidden,
      pausePollingOnError: pausePollingOnError ?? this.pausePollingOnError,
      pollingRetryInterval: pollingRetryInterval ?? this.pollingRetryInterval,
      debounceInterval: debounceInterval ?? this.debounceInterval,
      debounceLeading: debounceLeading ?? this.debounceLeading,
      debounceTrailing: debounceTrailing ?? this.debounceTrailing,
      debounceMaxWait: debounceMaxWait ?? this.debounceMaxWait,
      throttleInterval: throttleInterval ?? this.throttleInterval,
      throttleLeading: throttleLeading ?? this.throttleLeading,
      throttleTrailing: throttleTrailing ?? this.throttleTrailing,
      retryCount: retryCount ?? this.retryCount,
      retryInterval: retryInterval ?? this.retryInterval,
      retryExponential: retryExponential ?? this.retryExponential,
      loadingDelay: loadingDelay ?? this.loadingDelay,
      refreshOnFocus: refreshOnFocus ?? this.refreshOnFocus,
      refreshOnReconnect: refreshOnReconnect ?? this.refreshOnReconnect,
      reconnectStream: reconnectStream ?? this.reconnectStream,
      cacheKey: cacheKey ?? this.cacheKey,
      cacheTime: cacheTime ?? this.cacheTime,
      staleTime: staleTime ?? this.staleTime,
      fetchKey: fetchKey ?? this.fetchKey,
      loadMoreParams: loadMoreParams ?? this.loadMoreParams,
      dataMerger: dataMerger ?? this.dataMerger,
      hasMore: hasMore ?? this.hasMore,
      cancelToken: cancelToken ?? this.cancelToken,
      onBefore: onBefore ?? this.onBefore,
      onSuccess: onSuccess ?? this.onSuccess,
      onError: onError ?? this.onError,
      onFinally: onFinally ?? this.onFinally,
      onRetryAttempt: onRetryAttempt ?? this.onRetryAttempt,
    );
  }
}

// ============================================================================
// UseRequestResult - 返回结果
// ============================================================================

/// useRequest 的返回结果对象
///
/// 包含请求状态和操作方法，提供完整的请求控制能力。
///
/// ## 状态属性
///
/// - [loading] - 是否正在加载
/// - [data] - 请求返回的数据
/// - [error] - 错误信息
/// - [params] - 当前请求的参数
/// - [loadingMore] - 是否正在加载更多
/// - [hasMore] - 是否还有更多数据
///
/// ## 操作方法
///
/// - [run]/[runAsync] - 执行请求
/// - [refresh]/[refreshAsync] - 刷新（使用上次参数）
/// - [loadMore]/[loadMoreAsync] - 加载更多
/// - [mutate] - 直接修改数据
/// - [cancel] - 取消请求
///
/// ## 示例
///
/// ```dart
/// final result = useRequest<User, int>(fetchUser);
///
/// // 根据状态渲染 UI
/// if (result.loading) {
///   return CircularProgressIndicator();
/// }
///
/// if (result.error != null) {
///   return Text('Error: ${result.error}');
/// }
///
/// return Text('User: ${result.data?.name}');
/// ```
class UseRequestResult<TData, TParams> {
  /// 是否处于加载中
  ///
  /// 当请求正在进行时为 `true`。
  /// 配合 [loadingDelay] 可避免快速请求时的闪烁。
  final bool loading;

  /// 返回数据
  ///
  /// 请求成功后的响应数据。类型由泛型 [TData] 指定。
  final TData? data;

  /// 错误信息
  ///
  /// 请求失败时的错误对象，可能是：
  /// - [DioException] - 网络错误
  /// - 业务异常 - 自定义错误
  /// - 其他异常
  final dynamic error;

  /// 当前请求的参数
  ///
  /// 最后一次请求使用的参数，用于 `refresh()` 时复用。
  final TParams? params;

  /// 是否处于加载更多中
  ///
  /// 仅在调用 `loadMore()` 时为 `true`，与 [loading] 独立。
  final bool loadingMore;

  /// 是否还有更多数据
  ///
  /// 由 [UseRequestOptions.hasMore] 函数计算得出。
  /// 为 `false` 时，`loadMore()` 不会发起新请求。
  final bool? hasMore;

  /// 是否正在轮询
  final bool isPolling;

  /// 异步执行请求
  ///
  /// 返回 `Future`，可等待请求完成并获取结果。
  ///
  /// ```dart
  /// try {
  ///   final user = await result.runAsync(1);
  ///   print('User: ${user.name}');
  /// } catch (e) {
  ///   print('Error: $e');
  /// }
  /// ```
  final Future<TData> Function(TParams params) runAsync;

  /// 触发请求（不等待返回）
  ///
  /// 发起请求但不等待结果，适用于不需要处理返回值的场景。
  ///
  /// ```dart
  /// result.run(1);  // 发起请求，通过 data/error 获取结果
  /// ```
  final void Function(TParams params) run;

  /// 使用上一次参数进行刷新（异步）
  ///
  /// 使用最后一次请求的参数重新发起请求。
  ///
  /// ```dart
  /// await result.refreshAsync();
  /// ```
  final Future<TData> Function() refreshAsync;

  /// 使用上一次参数进行刷新（不等待返回）
  ///
  /// ```dart
  /// result.refresh();
  /// ```
  final void Function() refresh;

  /// 加载更多（异步）
  ///
  /// 使用 [UseRequestOptions.loadMoreParams] 生成下一页参数并请求。
  /// 结果通过 [UseRequestOptions.dataMerger] 与现有数据合并。
  final Future<TData> Function()? loadMoreAsync;

  /// 加载更多（不等待返回）
  final void Function()? loadMore;

  /// 直接修改数据（不触发请求）
  ///
  /// 用于乐观更新、本地修改等场景。
  ///
  /// ```dart
  /// // 乐观删除
  /// result.mutate((oldData) {
  ///   return oldData?.where((item) => item.id != deletedId).toList();
  /// });
  /// ```
  final void Function(TData? Function(TData? oldData)? mutator) mutate;

  /// 取消当前进行中的请求
  ///
  /// 取消后请求会抛出取消异常，不会触发 `onSuccess` 或更新 `data`。
  ///
  /// ```dart
  /// result.cancel();
  /// ```
  final void Function() cancel;

  /// 暂停轮询
  final void Function() pausePolling;

  /// 恢复轮询
  final void Function() resumePolling;

  const UseRequestResult({
    required this.loading,
    required this.data,
    required this.error,
    required this.params,
    this.loadingMore = false,
    this.hasMore,
    this.isPolling = false,
    required this.runAsync,
    required this.run,
    required this.refreshAsync,
    required this.refresh,
    this.loadMoreAsync,
    this.loadMore,
    required this.mutate,
    required this.cancel,
    void Function()? pausePolling,
    void Function()? resumePolling,
  }) : pausePolling = pausePolling ?? _noop,
       resumePolling = resumePolling ?? _noop;
}

/// 空操作函数，用于可选回调的默认值
void _noop() {}

// ============================================================================
// UseRequestState - 内部状态
// ============================================================================

/// useRequest 内部状态
///
/// 用于状态管理（如 Riverpod StateNotifier）的不可变状态类。
///
/// ## 状态字段
///
/// - [loading] - 是否正在加载
/// - [loadingMore] - 是否正在加载更多
/// - [data] - 请求数据
/// - [error] - 错误信息
/// - [params] - 请求参数
/// - [requestCount] - 请求计数（用于取消旧请求）
/// - [hasMore] - 是否有更多数据
///
/// ## 示例
///
/// ```dart
/// // 初始状态
/// final state = UseRequestState<User, int>();
///
/// // 更新状态
/// final newState = state.copyWith(
///   loading: true,
///   params: 1,
/// );
/// ```
class UseRequestState<TData, TParams> {
  /// 是否正在加载
  final bool loading;

  /// 是否正在加载更多
  final bool loadingMore;

  /// 请求数据
  final TData? data;

  /// 错误信息
  final dynamic error;

  /// 请求参数
  final TParams? params;

  /// 请求计数
  ///
  /// 每次请求递增，用于判断响应是否为最新请求的结果。
  /// 旧请求的响应会被忽略，避免竞态条件。
  final int requestCount;

  /// 是否有更多数据
  final bool? hasMore;

  const UseRequestState({
    this.loading = false,
    this.loadingMore = false,
    this.data,
    this.error,
    this.params,
    this.requestCount = 0,
    this.hasMore,
  });

  /// 复制并修改状态
  ///
  /// [clearData] - 是否清除 data（设为 null）
  /// [clearError] - 是否清除 error（设为 null）
  UseRequestState<TData, TParams> copyWith({
    bool? loading,
    bool? loadingMore,
    TData? data,
    dynamic error,
    TParams? params,
    int? requestCount,
    bool? hasMore,
    bool clearData = false,
    bool clearError = false,
  }) {
    return UseRequestState<TData, TParams>(
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      data: clearData ? null : (data ?? this.data),
      error: clearError ? null : (error ?? this.error),
      params: params ?? this.params,
      requestCount: requestCount ?? this.requestCount,
      hasMore: hasMore ?? this.hasMore,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UseRequestState<TData, TParams> &&
        other.loading == loading &&
        other.loadingMore == loadingMore &&
        other.data == data &&
        other.error == error &&
        other.params == params &&
        other.requestCount == requestCount &&
        other.hasMore == hasMore;
  }

  @override
  int get hashCode {
    return Object.hash(
      loading,
      loadingMore,
      data,
      error,
      params,
      requestCount,
      hasMore,
    );
  }

  @override
  String toString() {
    return 'UseRequestState('
        'loading: $loading, '
        'loadingMore: $loadingMore, '
        'data: $data, '
        'error: $error, '
        'params: $params, '
        'requestCount: $requestCount, '
        'hasMore: $hasMore)';
  }
}
