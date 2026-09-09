import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'types.dart';
import 'utils/debounce.dart';
import 'utils/throttle.dart';
import 'utils/retry.dart';
import 'utils/polling.dart';
import 'utils/loading_delay.dart';
import 'utils/focus_manager.dart';
import 'utils/cancel_token.dart';
import 'utils/cache.dart';
import 'utils/cache_policy.dart';
import 'utils/observer.dart';
import 'utils/dio_adapter.dart' show HttpRequestConfig;

void _ensurePollingActive<TData>(PollingController<TData> controller) {
  if (controller.isPaused) {
    controller.resume();
    return;
  }
  if (!controller.isRunning) {
    controller.start();
  }
}

TData? _resolveInitialCachedData<TData, TParams>(
  UseRequestOptions<TData, TParams> options,
) {
  final cacheKeyBuilder = options.cacheKey;
  if (cacheKeyBuilder == null) return null;

  // auto 请求允许“无参服务”把 null 当作默认参数参与 cacheKey 计算；
  // 对于必须显式传参的请求，这里的 cast 会失败并安全跳过缓存预填充，
  // 避免在首帧阶段因为类型不匹配直接抛异常。
  if (options.defaultParams == null && options.manual) return null;

  try {
    final params = options.defaultParams as TParams;
    final cacheKey = cacheKeyBuilder(params);
    if (cacheKey.isEmpty) return null;
    final coordinator = CacheCoordinator<TData>(
      cacheKey: cacheKey,
      cacheTime: options.cacheTime,
      staleTime: options.staleTime,
    );
    return coordinator.getFresh();
  } catch (_) {
    return null;
  }
}

/// useRequest Hook 实现
/// 借鉴 ahooks 的数据请求能力并结合 Dart/Flutter 特性
UseRequestResult<TData, TParams> useRequest<TData, TParams>(
  Service<TData, TParams> service, {
  UseRequestOptions<TData, TParams>? options,
}) {
  final opts = options ?? const UseRequestOptions();

  if (opts.debounceInterval != null && opts.throttleInterval != null) {
    throw ArgumentError('debounceInterval 与 throttleInterval 不能同时设置，请二选一');
  }

  String getKey(TParams params) => opts.fetchKey?.call(params) ?? '_default';

  final initialCachedData = useMemoized(
    () => _resolveInitialCachedData<TData, TParams>(opts),
    const [],
  );

  // 使用 Hook 的状态管理（ValueNotifier）保证组件响应式更新
  final stateNotifier = useState(
    UseRequestState<TData, TParams>(
      params: opts.defaultParams,
      data: initialCachedData ?? opts.initialData,
    ),
  );

  // PollingController 不是响应式对象，单独保存其运行状态。
  // 控制器通过 onStateChange 更新该值，使 pause/resume 后立即重建 UI。
  final pollingActiveState = useState(false);

  // 请求取消令牌（按 key）
  final cancelTokenMapRef = useRef<Map<String, CancelToken?>>({});

  // 请求计数器（按 key），保证只处理每个 key 最新一次请求
  final requestCountMapRef = useRef<Map<String, int>>({});

  // 防抖器引用
  final debouncerRef = useRef<Debouncer<TData>?>(null);

  // 节流器引用
  final throttlerRef = useRef<Throttler<TData>?>(null);

  // 轮询控制器引用
  final pollingControllerRef = useRef<PollingController<TData>?>(null);
  // 轮询错误后的自动恢复计时器
  final pollingRetryTimerRef = useRef<Timer?>(null);

  // 最新一帧的 opts / 核心闭包。
  // useEffect 创建的长生命周期回调（轮询 action、聚焦/重连监听）若直接捕获
  // build 时的闭包，会在未列入 effect keys 的 options 变化后继续使用旧配置
  // （stale closure）。统一经由 ref 间接调用，保证始终执行最新一帧的实现。
  final optsRef = useRef(opts);
  optsRef.value = opts;
  final fetchDataRef =
      useRef<Future<TData> Function(String, TParams, {bool isLoadMore})?>(null);
  final refreshRef = useRef<VoidCallback?>(null);

  // loading 延迟控制器引用
  final loadingDelayControllerRef = useRef<LoadingDelayController?>(null);

  // 聚焦管理器引用
  final focusManagerRef = useRef<AppFocusManager?>(null);

  // 上一次请求参数（用于刷新，按 key）
  final lastParamsMapRef = useRef<Map<String, TParams?>>({});
  final lastKeyRef = useRef<String?>(null);

  // 初始化默认参数的 key（仅首次执行，避免每次 build 覆盖用户手动传入的参数）
  final hasInitializedDefaultParams = useRef<bool>(false);
  if (!hasInitializedDefaultParams.value && opts.defaultParams != null) {
    hasInitializedDefaultParams.value = true;
    final key = getKey(opts.defaultParams as TParams);
    lastParamsMapRef.value[key] = opts.defaultParams;
    lastKeyRef.value = key;
  }

  bool canInvokeWithParams(Object? params) {
    try {
      params as TParams;
      return true;
    } catch (_) {
      return false;
    }
  }

  bool hasLastInvocationForKey(String key) =>
      lastParamsMapRef.value.containsKey(key);

  // 上一次 refreshDeps（用于依赖刷新比较）
  final lastRefreshDepsRef = useRef<List<Object?>?>(
    opts.refreshDeps == null ? null : List<Object?>.from(opts.refreshDeps!),
  );
  // ready=false 时变更的 refreshDeps 会在 ready=true 时补偿触发
  final pendingRefreshDepsRef = useRef<bool>(false);
  // 标记当前 build 是否已由 refreshDeps 触发请求或自定义动作。
  // refreshDeps effect 位于自动请求 effect 之前；同帧 ready 恢复时据此避免重复执行。
  final handledRefreshDepsThisBuildRef = useRef<bool>(false);
  handledRefreshDepsThisBuildRef.value = false;

  // 组件是否仍挂载，避免卸载后更新状态
  final isMountedRef = useRef<bool>(true);

  // 组件卸载时统一清理资源
  useEffect(() {
    return () {
      isMountedRef.value = false;
      debouncerRef.value?.dispose();
      debouncerRef.value = null;
      throttlerRef.value?.dispose();
      throttlerRef.value = null;
      pollingRetryTimerRef.value?.cancel();
      pollingRetryTimerRef.value = null;
      pollingControllerRef.value?.dispose();
      loadingDelayControllerRef.value?.dispose();
      focusManagerRef.value?.dispose();
      for (final token in cancelTokenMapRef.value.values) {
        token?.cancel('Component disposed');
      }
    };
  }, const []);

  // 防抖器按配置动态创建/销毁
  useEffect(
    () {
      debouncerRef.value?.dispose();
      debouncerRef.value = null;
      if (opts.debounceInterval != null) {
        debouncerRef.value = Debouncer<TData>(
          duration: opts.debounceInterval!,
          leading: opts.debounceLeading,
          trailing: opts.debounceTrailing,
          maxWait: opts.debounceMaxWait,
        );
      }
      return null;
    },
    [
      opts.debounceInterval,
      opts.debounceLeading,
      opts.debounceTrailing,
      opts.debounceMaxWait,
    ],
  );

  // 节流器按配置动态创建/销毁
  useEffect(() {
    throttlerRef.value?.dispose();
    throttlerRef.value = null;
    if (opts.throttleInterval != null) {
      throttlerRef.value = Throttler<TData>(
        duration: opts.throttleInterval!,
        leading: opts.throttleLeading,
        trailing: opts.throttleTrailing,
        maxWait: opts.throttleInterval,
      );
    }
    return null;
  }, [opts.throttleInterval, opts.throttleLeading, opts.throttleTrailing]);

  // 更新状态的辅助函数
  void updateState(
    UseRequestState<TData, TParams> Function(UseRequestState<TData, TParams>)
    updater,
  ) {
    if (isMountedRef.value) {
      stateNotifier.value = updater(stateNotifier.value);
    }
  }

  // 设置 loading 状态（支持延迟展示）
  void setLoading(bool loading) {
    if (opts.loadingDelay != null && loading) {
      loadingDelayControllerRef.value?.cancel();
      loadingDelayControllerRef.value = LoadingDelayController(
        delay: opts.loadingDelay!,
        onLoadingChange: (value) {
          updateState((s) => s.copyWith(loading: value));
        },
      );
      loadingDelayControllerRef.value!.startLoading();
    } else {
      loadingDelayControllerRef.value?.endLoading();
      updateState((s) => s.copyWith(loading: loading));
    }
  }

  Future<TData> bindPendingRequest(
    Future<TData> pending,
    String key,
    TParams params,
    int currentRequestCount, {
    bool isLoadMore = false,
  }) async {
    if (isLoadMore) {
      updateState(
        (s) => s.copyWith(
          loadingMore: true,
          params: params,
          clearError: true,
          requestCount: currentRequestCount,
        ),
      );
    } else {
      setLoading(true);
      updateState(
        (s) => s.copyWith(
          params: params,
          clearError: true,
          requestCount: currentRequestCount,
        ),
      );
    }

    try {
      final result = await pending;
      final latestCount = requestCountMapRef.value[key] ?? currentRequestCount;
      final isStaleKey = lastKeyRef.value != key;
      final cancelToken = cancelTokenMapRef.value[key];
      if (currentRequestCount != latestCount ||
          isStaleKey ||
          (cancelToken?.isCancelled ?? false)) {
        return result;
      }

      final mergedResult = isLoadMore && opts.dataMerger != null
          ? opts.dataMerger!(stateNotifier.value.data, result)
          : result;

      loadingDelayControllerRef.value?.endLoading();
      updateState(
        (s) => s.copyWith(
          loading: false,
          loadingMore: false,
          data: mergedResult,
          clearData: mergedResult == null,
          clearError: true,
          hasMore:
              opts.hasMore?.call(mergedResult) ?? stateNotifier.value.hasMore,
        ),
      );

      // 复用请求同样触发成功和完成回调
      try {
        opts.onSuccess?.call(mergedResult, params);
      } catch (_) {}
      try {
        opts.onFinally?.call(params, mergedResult, null);
      } catch (_) {}

      return mergedResult;
    } catch (e) {
      final latestCount = requestCountMapRef.value[key] ?? currentRequestCount;
      final isStaleKey = lastKeyRef.value != key;
      final cancelToken = cancelTokenMapRef.value[key];
      final isStale = currentRequestCount != latestCount || isStaleKey;
      final isCancellation =
          (cancelToken?.isCancelled ?? false) ||
          e is RequestSupersededException ||
          e is RequestCancelledException ||
          e is RetryCancelledException ||
          (e is DioException && e.type == DioExceptionType.cancel);

      if (!isStale && !isCancellation) {
        loadingDelayControllerRef.value?.endLoading();
        updateState(
          (s) => s.copyWith(loading: false, loadingMore: false, error: e),
        );
        // 复用请求同样触发失败和完成回调
        try {
          opts.onError?.call(e, params);
        } catch (_) {}
        try {
          opts.onFinally?.call(params, null, e);
        } catch (_) {}
      }

      return Future.error(e);
    }
  }

  // 核心请求函数
  Future<TData> fetchData(
    String key,
    TParams params, {
    bool isLoadMore = false,
  }) async {
    // Increment request count per key
    final currentRequestCount = (requestCountMapRef.value[key] ?? 0) + 1;
    requestCountMapRef.value[key] = currentRequestCount;

    // 记录当前参数与 key 用于刷新
    lastParamsMapRef.value[key] = params;
    lastKeyRef.value = key;

    // 触发 onBefore 回调
    // 注意：loadMore 场景下不会触发 onBefore，因为 loadMore 是追加数据操作，
    // 而非全新请求。如需在 loadMore 前执行逻辑，请在调用 loadMore() 前自行处理。
    if (!isLoadMore) {
      try {
        opts.onBefore?.call(params);
      } catch (_) {}
    }

    // 通知全局观察者
    notifyRequestObserverRequest(key, params);

    // 读取缓存
    TData? cachedData;
    final cacheKey = opts.cacheKey?.call(params);
    if (cacheKey != null && cacheKey.isNotEmpty) {
      // 若有进行中的请求，直接复用
      final pending = getPendingCache<TData>(cacheKey);
      if (pending != null) {
        // pending 可能属于当前 Hook，也可能来自另一个相同 cacheKey 的实例。
        // 不能在复用前取消旧令牌，否则会把这个 pending Future 一并取消。
        final existingToken = cancelTokenMapRef.value[key];
        if (existingToken == null || existingToken.isCancelled) {
          final configToken = params is HttpRequestConfig
              ? params.cancelToken
              : null;
          cancelTokenMapRef.value[key] = createLinkedCancelToken(
            opts.cancelToken,
            configToken,
          );
        }
        return bindPendingRequest(
          pending,
          key,
          params,
          currentRequestCount,
          isLoadMore: isLoadMore,
        );
      }

      final coordinator = CacheCoordinator<TData>(
        cacheKey: cacheKey,
        cacheTime: opts.cacheTime,
        staleTime: opts.staleTime,
      );
      cachedData = coordinator.getFresh();
      if (cachedData != null) {
        final shouldRevalidate = coordinator.shouldRevalidate();
        notifyRequestObserverCacheHit(cacheKey, shouldRevalidate);
        updateState(
          (s) => s.copyWith(
            loading: false,
            data: cachedData,
            params: params,
            clearError: true,
            requestCount: currentRequestCount,
          ),
        );

        // 新鲜时直接返回；陈旧时继续走请求再验证。
        // 与 ahooks 一致：纯缓存命中不触发 onSuccess/onFinally 用户回调，
        // 但补发观察者 finally 事件，保证 onRequest/onFinally 打点配对。
        if (!shouldRevalidate) {
          notifyRequestObserverFinally(key, params);
          return cachedData;
        }
      }
    }

    // 只有确定要发起新请求后才取消当前 key 的旧请求。命中 pending 时必须
    // 保留原请求，因为本次调用会直接复用它。
    cancelTokenMapRef.value[key]?.cancel('New request started');
    final configToken = params is HttpRequestConfig ? params.cancelToken : null;
    final cancelToken = createLinkedCancelToken(opts.cancelToken, configToken);
    cancelTokenMapRef.value[key] = cancelToken;

    // HttpRequestConfig 始终使用内部令牌。配置令牌与 options 令牌都关联到
    // 内部令牌，因此任一外部令牌或 result.cancel() 均可中断 Dio 请求。
    final TParams callParams = params is HttpRequestConfig
        ? params.copyWith(
                connectTimeout: params.connectTimeout ?? opts.connectTimeout,
                receiveTimeout: params.receiveTimeout ?? opts.receiveTimeout,
                sendTimeout: params.sendTimeout ?? opts.sendTimeout,
                cancelToken: cancelToken,
              )
              as TParams
        : params;

    // 进入 loading 状态
    if (isLoadMore) {
      updateState(
        (s) => s.copyWith(
          loadingMore: true,
          clearError: true,
          requestCount: currentRequestCount,
        ),
      );
    } else {
      setLoading(true);
      // keepPreviousData=false（默认）且参数变化时清除旧数据，避免显示不匹配的数据
      final shouldClearData =
          !opts.keepPreviousData &&
          cachedData == null &&
          stateNotifier.value.params != params;
      updateState(
        (s) => s.copyWith(
          params: params,
          clearError: true,
          clearData: shouldClearData,
          requestCount: currentRequestCount,
        ),
      );
    }

    try {
      TData result;

      // 执行失败重试（若配置）
      if (opts.retryCount != null && opts.retryCount! > 0) {
        final future = executeWithRetry<TData>(
          () => service(callParams),
          maxRetries: opts.retryCount!,
          retryInterval: opts.retryInterval ?? const Duration(seconds: 1),
          cancelToken: cancelToken,
          onRetry: (attempt, err) {
            opts.onRetryAttempt?.call(attempt, err);
          },
          exponential: opts.retryExponential,
        );
        if (cacheKey != null && cacheKey.isNotEmpty) {
          setPendingCache<TData>(cacheKey, future);
        }
        result = await future;
      } else {
        final future = service(callParams);
        if (cacheKey != null && cacheKey.isNotEmpty) {
          setPendingCache<TData>(cacheKey, future);
        }
        result = await future;
      }

      // 只处理最新一次请求且仅更新 active key；旧请求结果直接丢弃
      final latestCount = requestCountMapRef.value[key] ?? currentRequestCount;
      final isStaleKey = lastKeyRef.value != key;
      if (currentRequestCount != latestCount ||
          cancelToken.isCancelled ||
          isStaleKey) {
        return result;
      }

      // 合并数据（加载更多场景）
      final mergedResult = isLoadMore && opts.dataMerger != null
          ? opts.dataMerger!(stateNotifier.value.data, result)
          : result;

      // 更新成功态
      // clearData：TData 可空时 service 合法返回 null，copyWith 的 ?? 合并
      // 会保留旧数据，需显式清除。
      loadingDelayControllerRef.value?.endLoading();
      updateState(
        (s) => s.copyWith(
          loading: false,
          loadingMore: false,
          data: mergedResult,
          clearData: mergedResult == null,
          clearError: true,
          hasMore:
              opts.hasMore?.call(mergedResult) ?? stateNotifier.value.hasMore,
        ),
      );

      // 触发成功回调（捕获回调异常，确保后续缓存写入和 onFinally 不被跳过）
      try {
        opts.onSuccess?.call(mergedResult, params);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverSuccess(key, mergedResult, params);

      // 写入缓存
      if (cacheKey != null && cacheKey.isNotEmpty) {
        setCache<TData>(cacheKey, mergedResult);
      }

      // 若配置了轮询且尚未启动，在首次成功后启动（手动模式也支持）
      if (opts.pollingInterval != null &&
          pollingControllerRef.value != null &&
          lastKeyRef.value != null &&
          lastParamsMapRef.value[lastKeyRef.value!] != null &&
          !pollingControllerRef.value!.isRunning &&
          opts.ready) {
        _ensurePollingActive(pollingControllerRef.value!);
      }

      // 触发完成回调
      try {
        opts.onFinally?.call(params, mergedResult, null);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverFinally(key, params);

      return mergedResult;
    } catch (e) {
      final latestCount = requestCountMapRef.value[key] ?? currentRequestCount;
      final isStaleKey = lastKeyRef.value != key;
      final isStale = currentRequestCount != latestCount || isStaleKey;
      final isCancellation =
          cancelToken.isCancelled ||
          e is RequestSupersededException ||
          e is RequestCancelledException ||
          e is RetryCancelledException ||
          (e is DioException && e.type == DioExceptionType.cancel);

      if (isStale || isCancellation) {
        return Future.error(e);
      }

      // 更新错误态
      loadingDelayControllerRef.value?.endLoading();
      updateState(
        (s) => s.copyWith(loading: false, loadingMore: false, error: e),
      );

      // 触发失败回调（捕获回调异常，确保 onFinally 和缓存清理不被跳过）
      try {
        opts.onError?.call(e, params);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverError(key, e, params);

      // 触发完成回调
      try {
        opts.onFinally?.call(params, null, e);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverFinally(key, params);

      // 注意：失败时不清除已有缓存条目（SWR 语义）——后台再验证失败不应
      // 抹掉仍在 cacheTime 有效期内的旧数据；进行中的 pending 条目会自动清理。

      return Future.error(e);
    }
  }

  fetchDataRef.value = fetchData;

  // 异步执行（支持防抖/节流）
  Future<TData> runAsync(TParams params, {bool isLoadMore = false}) async {
    final key = getKey(params);

    // Apply debounce if configured
    if (debouncerRef.value != null) {
      return debouncerRef.value!.call(
        () => fetchData(key, params, isLoadMore: isLoadMore),
      );
    }

    // Apply throttle if configured
    if (throttlerRef.value != null) {
      return throttlerRef.value!.call(
        () => fetchData(key, params, isLoadMore: isLoadMore),
      );
    }

    return fetchData(key, params, isLoadMore: isLoadMore);
  }

  // 触发请求（不等待返回）
  void run(TParams params) {
    unawaited(runAsync(params).then<void>((_) {}, onError: (_) {}));
  }

  /// 只有在参数真的能安全转换成 TParams 时才触发请求。
  ///
  /// 这里单独包一层是为了统一处理“无参请求”和“非空参数尚未就绪”两种情况：
  /// - 对 `dynamic/Object?/nullable` 参数，请求应该正常发起；
  /// - 对 `int/String` 这类非空参数，如果当前拿到的是 `null`，则应安静跳过，
  ///   而不是在自动请求或 refreshDeps 阶段直接抛出运行时类型错误。
  bool runIfInvocable(Object? params) {
    if (!canInvokeWithParams(params)) return false;
    run(params as TParams);
    return true;
  }

  // 使用上一次参数刷新（异步）
  //
  // 前置条件不满足时返回 Future.error 而非同步 throw，
  // 保证 refresh()（void 版）在任何时机调用都不会让调用方同步崩溃。
  Future<TData> refreshAsync() {
    final lastKey = lastKeyRef.value;
    if (lastKey == null) {
      return Future.error(StateError('No previous key to refresh with'));
    }
    final paramsMap = lastParamsMapRef.value;
    if (!paramsMap.containsKey(lastKey)) {
      return Future.error(StateError('No previous params to refresh with'));
    }
    final params = paramsMap[lastKey];
    // 安全类型检查：当 TParams 为非空类型而 params 为 null 时，
    // 尝试回退到 defaultParams，避免运行时 _CastError。
    if (!canInvokeWithParams(params)) {
      if (canInvokeWithParams(opts.defaultParams)) {
        return runAsync(opts.defaultParams as TParams);
      }
      return Future.error(
        StateError(
          'Cannot refresh: last params ($params) is not a valid $TParams '
          'and no usable defaultParams available',
        ),
      );
    }
    return runAsync(params as TParams);
  }

  // 使用上一次参数刷新（不等待返回）
  void refresh() {
    unawaited(refreshAsync().then<void>((_) {}, onError: (_) {}));
  }

  refreshRef.value = refresh;

  // 加载更多
  //
  // 与 refreshAsync 一致：前置条件不满足时统一返回 Future.error，
  // 避免 loadMore()（void 版）在事件回调中同步抛出。
  Future<TData> loadMoreAsync() {
    // 如果 hasMore 明确为 false，不再发起请求
    if (stateNotifier.value.hasMore == false) {
      return Future.error(StateError('没有更多数据可加载（hasMore 为 false）'));
    }
    final lastKey = lastKeyRef.value;
    if (lastKey == null) {
      return Future.error(StateError('No previous key to load more with'));
    }
    final paramsMap = lastParamsMapRef.value;
    if (!paramsMap.containsKey(lastKey)) {
      return Future.error(StateError('No previous params to load more with'));
    }
    final lastParams = paramsMap[lastKey];
    if (opts.loadMoreParams == null) {
      return Future.error(
        StateError('UseRequestOptions.loadMoreParams 未提供，无法加载更多'),
      );
    }
    final nextParams = opts.loadMoreParams!(
      lastParams as TParams,
      stateNotifier.value.data,
    );
    return runAsync(nextParams, isLoadMore: true);
  }

  void loadMore() {
    unawaited(loadMoreAsync().then<void>((_) {}, onError: (_) {}));
  }

  // 直接修改数据（不触发请求），同步写入全局缓存
  void mutate(TData? Function(TData? oldData)? mutator) {
    if (mutator != null) {
      final oldData = stateNotifier.value.data;
      updateState((s) {
        final newData = mutator(s.data);
        return s.copyWith(data: newData, clearData: newData == null);
      });
      final newData = stateNotifier.value.data;
      // 同步写入全局缓存
      final lastKey = lastKeyRef.value;
      if (lastKey != null) {
        final lastParams = lastParamsMapRef.value[lastKey];
        if (lastParamsMapRef.value.containsKey(lastKey) &&
            opts.cacheKey != null) {
          final ck = opts.cacheKey!(lastParams as TParams);
          if (ck.isNotEmpty) {
            if (newData != null) {
              setCache<TData>(ck, newData);
            } else {
              clearCacheEntry(ck);
            }
          }
        }
        notifyRequestObserverMutate(lastKey, oldData, newData);
      }
    }
  }

  // 取消当前请求（取消所有 key 的进行中请求，含排队中的防抖/节流调用）
  void cancel() {
    debouncerRef.value?.cancel();
    throttlerRef.value?.cancel();
    for (final entry in cancelTokenMapRef.value.entries) {
      entry.value?.cancel('Request cancelled by user');
      notifyRequestObserverCancel(entry.key);
    }
    loadingDelayControllerRef.value?.endLoading();
    updateState((s) => s.copyWith(loading: false, loadingMore: false));
  }

  void pausePolling() {
    pollingControllerRef.value?.pause();
    cancel();
  }

  void resumePolling() {
    final lastKey = lastKeyRef.value;
    final hasParams = lastKey != null && hasLastInvocationForKey(lastKey);
    if (pollingControllerRef.value != null && hasParams && opts.ready) {
      pollingControllerRef.value!.resume();
    }
  }

  final refreshDepsKey = opts.refreshDeps == null
      ? null
      : Object.hashAll(opts.refreshDeps!);

  // refreshDeps 触发的刷新：与 ahooks 的 refresh 语义一致，优先复用最近一次
  // 请求的参数（用户 run(x) 之后依赖变化，应以 x 刷新）；从未请求过或
  // 最近参数无法安全转换为 TParams 时，回退 defaultParams。
  //
  // 注意：对于“无参请求”（TParams 允许为 null），params 为 null 也应触发 run，
  // 否则会出现依赖变了但不发请求的行为（与 ahooks 不一致）。
  void runForRefreshDeps() {
    final lastKey = lastKeyRef.value;
    final hasLast = lastKey != null && hasLastInvocationForKey(lastKey);
    final params = hasLast
        ? lastParamsMapRef.value[lastKey]
        : opts.defaultParams;
    if (!runIfInvocable(params) && hasLast) {
      runIfInvocable(opts.defaultParams);
    }
  }

  // 依赖变化时自动刷新（仅在配置了 refreshDeps 时触发）
  useEffect(() {
    final deps = opts.refreshDeps;
    if (deps == null) {
      return null;
    }

    final prev = lastRefreshDepsRef.value;
    final changed = prev == null || !listEquals(prev, deps);

    if (changed) {
      lastRefreshDepsRef.value = List<Object?>.from(deps);

      if (opts.refreshDepsAction != null) {
        handledRefreshDepsThisBuildRef.value = true;
        opts.refreshDepsAction!();
        pendingRefreshDepsRef.value = false;
      } else if (!opts.manual && opts.ready) {
        handledRefreshDepsThisBuildRef.value = true;
        pendingRefreshDepsRef.value = false;
        runForRefreshDeps();
      } else {
        pendingRefreshDepsRef.value = true;
      }
    } else if (opts.ready && pendingRefreshDepsRef.value) {
      pendingRefreshDepsRef.value = false;
      if (opts.refreshDepsAction != null) {
        handledRefreshDepsThisBuildRef.value = true;
        opts.refreshDepsAction!();
      } else if (!opts.manual) {
        handledRefreshDepsThisBuildRef.value = true;
        runForRefreshDeps();
      }
    }

    return null;
  }, [refreshDepsKey, opts.ready]);

  // 设置轮询控制器（按 pollingInterval 变化重建）
  useEffect(
    () {
      pollingRetryTimerRef.value?.cancel();
      pollingRetryTimerRef.value = null;
      // effect 重新执行表示旧控制器已由 cleanup 释放；先同步为停止状态，
      // 后续新控制器若满足启动条件会通过 onStateChange 再更新为 true。
      pollingActiveState.value = false;

      if (opts.pollingInterval == null) {
        pollingControllerRef.value?.dispose();
        pollingControllerRef.value = null;
        return null;
      }

      late final PollingController<TData> controller;
      controller = PollingController<TData>(
        interval: opts.pollingInterval!,
        onStateChange: (isPolling) {
          if (isMountedRef.value) {
            pollingActiveState.value = isPolling;
          }
        },
        action: () {
          // 通过 optsRef/fetchDataRef 读取最新一帧的配置与实现，
          // 避免长生命周期的轮询回调捕获旧闭包（stale closure）。
          //
          // 注意：当配置了 loadMoreParams（分页模式）时，轮询使用 defaultParams
          // 刷新首页数据，而非使用 lastParams（可能是某一页的参数），
          // 避免轮询覆盖已累积的分页数据。
          final currentOpts = optsRef.value;
          final key = lastKeyRef.value;
          if (key != null && hasLastInvocationForKey(key)) {
            final TParams params;
            if (currentOpts.loadMoreParams != null &&
                currentOpts.defaultParams != null) {
              params = currentOpts.defaultParams as TParams;
            } else {
              params = (lastParamsMapRef.value[key]) as TParams;
            }
            return fetchDataRef.value!(key, params);
          }
          throw StateError('No params for polling');
        },
        onSuccess: (_) {
          // Success is already handled in fetchData
        },
        onError: (error) {
          if (opts.pausePollingOnError) {
            controller.pause();

            pollingRetryTimerRef.value?.cancel();
            final retryInterval = opts.pollingRetryInterval;
            if (retryInterval != null) {
              pollingRetryTimerRef.value = Timer(retryInterval, () {
                if (!isMountedRef.value) return;
                if (pollingControllerRef.value != controller) return;

                final lastKey = lastKeyRef.value;
                final hasParams =
                    lastKey != null && hasLastInvocationForKey(lastKey);
                final hasEverRun = stateNotifier.value.requestCount > 0;
                final shouldAutoStart = !opts.manual;
                final canPoll =
                    opts.ready && hasParams && (shouldAutoStart || hasEverRun);

                if (canPoll) {
                  _ensurePollingActive(controller);
                }
              });
            }
          }
        },
      );

      pollingControllerRef.value = controller;

      return () {
        pollingRetryTimerRef.value?.cancel();
        pollingRetryTimerRef.value = null;
        controller.dispose();
        if (pollingControllerRef.value == controller) {
          pollingControllerRef.value = null;
        }
      };
    },
    [
      opts.pollingInterval,
      opts.pausePollingOnError,
      opts.pollingRetryInterval,
      opts.manual,
      opts.ready,
    ],
  );

  // 根据 ready/manual/是否有过请求来启动或暂停轮询
  useEffect(
    () {
      final controller = pollingControllerRef.value;
      if (controller == null) return null;

      pollingRetryTimerRef.value?.cancel();
      pollingRetryTimerRef.value = null;

      final lastKey = lastKeyRef.value;
      final hasParams = lastKey != null && hasLastInvocationForKey(lastKey);
      final hasEverRun = stateNotifier.value.requestCount > 0;
      final shouldAutoStart = !opts.manual;
      final canPoll =
          opts.pollingInterval != null &&
          opts.ready &&
          hasParams &&
          (shouldAutoStart || hasEverRun);

      if (canPoll) {
        _ensurePollingActive(controller);
      } else {
        controller.pause();
      }

      return null;
    },
    [
      opts.pollingInterval,
      opts.manual,
      opts.ready,
      stateNotifier.value.requestCount,
    ],
  );

  // 设置聚焦刷新
  useEffect(
    () {
      if (opts.refreshOnFocus ||
          (opts.pollingInterval != null && !opts.pollingWhenHidden)) {
        focusManagerRef.value = AppFocusManager(
          onFocus: () {
            final key = lastKeyRef.value;
            if (opts.ready && key != null && hasLastInvocationForKey(key)) {
              if (opts.refreshOnFocus) {
                // 经 ref 调用最新一帧的 refresh，避免 stale closure
                refreshRef.value?.call();
              }
              if (opts.pollingInterval != null && !opts.pollingWhenHidden) {
                pollingControllerRef.value?.resume();
              }
            }
          },
          onBlur: () {
            if (opts.pollingInterval != null && !opts.pollingWhenHidden) {
              pollingControllerRef.value?.pause();
            }
          },
        );
        focusManagerRef.value!.start();
      }

      return () {
        focusManagerRef.value?.dispose();
      };
    },
    [
      opts.refreshOnFocus,
      opts.pollingInterval,
      opts.pollingWhenHidden,
      opts.ready,
    ],
  );

  // 重连刷新（外部提供 reconnectStream）
  useEffect(() {
    if (opts.refreshOnReconnect && opts.reconnectStream != null) {
      final sub = opts.reconnectStream!.listen((online) {
        if (online && opts.ready) {
          final key = lastKeyRef.value;
          if (key != null && hasLastInvocationForKey(key)) {
            // 经 ref 调用最新一帧的 refresh，避免 stale closure
            refreshRef.value?.call();
          }
        }
      });
      return sub.cancel;
    }
    return null;
  }, [opts.refreshOnReconnect, opts.reconnectStream, opts.ready]);

  // 非手动模式下，挂载后自动请求一次
  //
  // 注意：keys 不包含 defaultParams。defaultParams 只在挂载（或 manual/ready 切换）时
  // 消费一次，与 ahooks 语义一致。若把它加入 keys，内联构造且未重写 == 的参数对象
  // （如 HttpRequestConfig）会在每次 rebuild 时判定为"变化"，形成
  // 请求 → 状态变更 → rebuild → 再请求的死循环。参数变化触发刷新请使用 refreshDeps。
  useEffect(() {
    if (!opts.manual && opts.ready) {
      // refreshDeps 已在当前 build 触发，或仍有待回放任务时，跳过自动请求。
      if (handledRefreshDepsThisBuildRef.value ||
          (pendingRefreshDepsRef.value && opts.refreshDeps != null)) {
        return null;
      }
      runIfInvocable(opts.defaultParams);
    }
    return null;
  }, [opts.manual, opts.ready]);

  return UseRequestResult<TData, TParams>(
    loading: stateNotifier.value.loading,
    loadingMore: stateNotifier.value.loadingMore,
    data: stateNotifier.value.data,
    error: stateNotifier.value.error,
    params: stateNotifier.value.params,
    hasMore: stateNotifier.value.hasMore,
    isPolling: pollingActiveState.value,
    runAsync: runAsync,
    run: run,
    refreshAsync: refreshAsync,
    refresh: refresh,
    loadMoreAsync: opts.loadMoreParams != null ? loadMoreAsync : null,
    loadMore: opts.loadMoreParams != null ? loadMore : null,
    mutate: mutate,
    cancel: cancel,
    pausePolling: pausePolling,
    resumePolling: resumePolling,
  );
}

/// 闭包驱动版 useRequest（closure mode）。
///
/// 与 [useRequest] 的区别：service 是零参闭包，请求数据一律从闭包捕获的
/// 外部状态（useState / Provider / Riverpod / widget 字段）读取，
/// `refreshDeps` 只负责"什么时候重新请求"，不参与参数传递。
///
/// 这是"依赖变化 → 自动带最新条件重新请求"场景的推荐写法：
///
/// ```dart
/// final keyword = useState('');
///
/// final result = useRequestFn(
///   () => searchProducts(keyword.value),   // 永远读最新 keyword
///   options: UseRequestOptions(
///     refreshDeps: [keyword.value],        // keyword 变了自动重发
///   ),
/// );
/// ```
///
/// 对比参数模式 `useRequest(service)` + `run(params)`：
/// - 闭包模式：条件即状态，变化即刷新，不经过 params 机制，
///   因此不受"refreshDeps 复用上一次参数"语义的影响。
/// - 参数模式：参数由每次 `run(params)` 显式传入，适合点击搜索、
///   提交表单等一次性动作。
///
/// 注意：闭包模式下 `loadMoreParams` 无意义（params 恒为 null），
/// 分页/无限加载请把 page 也放进外部状态与 `refreshDeps`。
UseRequestResult<TData, Null> useRequestFn<TData>(
  Future<TData> Function() service, {
  UseRequestOptions<TData, Null>? options,
}) {
  // 每帧更新 ref：轮询、聚焦刷新等长生命周期回调经 fetchDataRef 间接调用时，
  // 保证执行的是最新一帧的闭包（读到最新的外部状态）。
  final serviceRef = useRef(service);
  serviceRef.value = service;
  return useRequest<TData, Null>((_) => serviceRef.value(), options: options);
}

/// 当请求被更新的请求覆盖时抛出
class RequestSupersededException implements Exception {
  const RequestSupersededException();

  @override
  String toString() =>
      'RequestSupersededException: Request was superseded by a newer request';
}

/// 当请求被取消时抛出
class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'RequestCancelledException: Request was cancelled';
}
