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

  final initialCachedData = _resolveInitialCachedData<TData, TParams>(opts);

  // 使用 Hook 的状态管理（ValueNotifier）保证组件响应式更新
  final stateNotifier = useState(
    UseRequestState<TData, TParams>(
      params: opts.defaultParams,
      data: initialCachedData ?? opts.initialData,
    ),
  );

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
  final pollingActiveRef = useRef<bool>(false);
  // 轮询错误后的自动恢复计时器
  final pollingRetryTimerRef = useRef<Timer?>(null);

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
      pollingActiveRef.value = false;
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
    // If the params is HttpRequestConfig, merge default timeouts from options.
    // This makes UseRequestOptions.connectTimeout/receiveTimeout/sendTimeout effective
    // for DioHttpAdapter + HttpRequestConfig scenarios.
    final TParams callParams = params is HttpRequestConfig
        ? (params as HttpRequestConfig).copyWith(
                connectTimeout:
                    (params as HttpRequestConfig).connectTimeout ??
                    opts.connectTimeout,
                receiveTimeout:
                    (params as HttpRequestConfig).receiveTimeout ??
                    opts.receiveTimeout,
                sendTimeout:
                    (params as HttpRequestConfig).sendTimeout ??
                    opts.sendTimeout,
              )
              as TParams
        : params;

    // Increment request count per key
    final currentRequestCount = (requestCountMapRef.value[key] ?? 0) + 1;
    requestCountMapRef.value[key] = currentRequestCount;

    // 创建新的取消令牌（按 key）
    cancelTokenMapRef.value[key]?.cancel('New request started');
    final cancelToken = createLinkedCancelToken(opts.cancelToken);
    cancelTokenMapRef.value[key] = cancelToken;

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
        notifyRequestObserverCacheHit(cacheKey, coordinator.shouldRevalidate());
        updateState(
          (s) => s.copyWith(
            loading: false,
            data: cachedData,
            params: params,
            clearError: true,
            requestCount: currentRequestCount,
          ),
        );

        // 新鲜时直接返回；陈旧时继续走请求再验证
        if (!coordinator.shouldRevalidate()) {
          return cachedData;
        }
      }
    }

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
      loadingDelayControllerRef.value?.endLoading();
      updateState(
        (s) => s.copyWith(
          loading: false,
          loadingMore: false,
          data: mergedResult,
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
        pollingControllerRef.value!.start();
        pollingActiveRef.value = true;
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

      if (cacheKey != null && cacheKey.isNotEmpty) {
        clearCacheEntry(cacheKey);
      }

      return Future.error(e);
    }
  }

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
  Future<TData> refreshAsync() {
    final lastKey = lastKeyRef.value;
    if (lastKey == null) {
      throw StateError('No previous key to refresh with');
    }
    final paramsMap = lastParamsMapRef.value;
    if (!paramsMap.containsKey(lastKey)) {
      throw StateError('No previous params to refresh with');
    }
    final params = paramsMap[lastKey];
    // 安全类型检查：当 TParams 为非空类型而 params 为 null 时，
    // 尝试回退到 defaultParams，避免运行时 _CastError。
    if (!canInvokeWithParams(params)) {
      if (canInvokeWithParams(opts.defaultParams)) {
        return runAsync(opts.defaultParams as TParams);
      }
      throw StateError(
        'Cannot refresh: last params ($params) is not a valid $TParams '
        'and no usable defaultParams available',
      );
    }
    return runAsync(params as TParams);
  }

  // 使用上一次参数刷新（不等待返回）
  void refresh() {
    unawaited(refreshAsync().then<void>((_) {}, onError: (_) {}));
  }

  // 加载更多
  Future<TData> loadMoreAsync() {
    // 如果 hasMore 明确为 false，不再发起请求
    if (stateNotifier.value.hasMore == false) {
      return Future.error(StateError('没有更多数据可加载（hasMore 为 false）'));
    }
    final lastKey = lastKeyRef.value;
    if (lastKey == null) {
      throw StateError('No previous key to load more with');
    }
    final paramsMap = lastParamsMapRef.value;
    if (!paramsMap.containsKey(lastKey)) {
      throw StateError('No previous params to load more with');
    }
    final lastParams = paramsMap[lastKey];
    if (opts.loadMoreParams == null) {
      throw StateError('UseRequestOptions.loadMoreParams 未提供，无法加载更多');
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
        if (lastParams != null && opts.cacheKey != null) {
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

  // 取消当前请求（取消所有 key 的进行中请求）
  void cancel() {
    for (final entry in cancelTokenMapRef.value.entries) {
      entry.value?.cancel('Request cancelled by user');
      notifyRequestObserverCancel(entry.key);
    }
    loadingDelayControllerRef.value?.endLoading();
    updateState((s) => s.copyWith(loading: false, loadingMore: false));
  }

  void pausePolling() {
    pollingControllerRef.value?.pause();
    pollingActiveRef.value = false;
    cancel();
  }

  void resumePolling() {
    final lastKey = lastKeyRef.value;
    final hasParams = lastKey != null && hasLastInvocationForKey(lastKey);
    if (pollingControllerRef.value != null && hasParams && opts.ready) {
      pollingControllerRef.value!.resume();
      pollingActiveRef.value = true;
    }
  }

  final refreshDepsKey = opts.refreshDeps == null
      ? null
      : Object.hashAll(opts.refreshDeps!);

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
        opts.refreshDepsAction!();
        pendingRefreshDepsRef.value = false;
      } else if (!opts.manual && opts.ready) {
        // refreshDeps 的语义：依赖变化时，触发一次“使用当前闭包/参数”的刷新。
        //
        // 注意：对于“无参请求”（service 不依赖入参，或 TParams 允许为 null），
        // params 可能为 null。此时也应该触发 run，否则会出现：
        // - 依赖变了，但不发请求（与 ahooks 行为不一致）
        // - 需要业务侧额外写兜底 refresh 逻辑
        //
        // 因此这里不要用 `params != null` 作为是否触发的条件。
        final params =
            opts.defaultParams ??
            (lastKeyRef.value != null
                ? lastParamsMapRef.value[lastKeyRef.value!]
                : null);
        pendingRefreshDepsRef.value = false;
        runIfInvocable(params);
      } else {
        pendingRefreshDepsRef.value = true;
      }
    } else if (opts.ready && pendingRefreshDepsRef.value) {
      pendingRefreshDepsRef.value = false;
      if (opts.refreshDepsAction != null) {
        opts.refreshDepsAction!();
      } else if (!opts.manual) {
        final params =
            opts.defaultParams ??
            (lastKeyRef.value != null
                ? lastParamsMapRef.value[lastKeyRef.value!]
                : null);
        runIfInvocable(params);
      }
    }

    return null;
  }, [refreshDepsKey, opts.ready]);

  // 设置轮询控制器（按 pollingInterval 变化重建）
  useEffect(
    () {
      pollingRetryTimerRef.value?.cancel();
      pollingRetryTimerRef.value = null;

      if (opts.pollingInterval == null) {
        pollingControllerRef.value?.dispose();
        pollingControllerRef.value = null;
        pollingActiveRef.value = false;
        return null;
      }

      late final PollingController<TData> controller;
      controller = PollingController<TData>(
        interval: opts.pollingInterval!,
        action: () {
          // 注意：当配置了 loadMoreParams（分页模式）时，轮询使用 defaultParams
          // 刷新首页数据，而非使用 lastParams（可能是某一页的参数），
          // 避免轮询覆盖已累积的分页数据。
          final key = lastKeyRef.value;
          if (key != null && hasLastInvocationForKey(key)) {
            final TParams params;
            if (opts.loadMoreParams != null && opts.defaultParams != null) {
              params = opts.defaultParams as TParams;
            } else {
              params = (lastParamsMapRef.value[key]) as TParams;
            }
            return fetchData(key, params);
          }
          throw StateError('No params for polling');
        },
        onSuccess: (_) {
          // Success is already handled in fetchData
        },
        onError: (error) {
          if (opts.pausePollingOnError) {
            controller.pause();
            pollingActiveRef.value = false;

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
                  if (!controller.isRunning) {
                    controller.start();
                  } else {
                    controller.resume();
                  }
                  pollingActiveRef.value = true;
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
        pollingActiveRef.value = false;
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
        if (!controller.isRunning) {
          controller.start();
        } else {
          controller.resume();
        }
        pollingActiveRef.value = true;
      } else {
        controller.pause();
        pollingActiveRef.value = false;
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
                refresh();
              }
              if (opts.pollingInterval != null && !opts.pollingWhenHidden) {
                resumePolling();
              }
            }
          },
          onBlur: () {
            if (opts.pollingInterval != null && !opts.pollingWhenHidden) {
              pollingControllerRef.value?.pause();
              pollingActiveRef.value = false;
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
            refresh();
          }
        }
      });
      return sub.cancel;
    }
    return null;
  }, [opts.refreshOnReconnect, opts.reconnectStream, opts.ready]);

  // 非手动模式下，挂载后自动请求一次
  useEffect(() {
    if (!opts.manual && opts.ready) {
      // 如果有待执行的 refreshDeps 回放，跳过自动请求避免同帧重复触发
      if (pendingRefreshDepsRef.value && opts.refreshDeps != null) return null;
      runIfInvocable(opts.defaultParams);
    }
    return null;
  }, [opts.manual, opts.defaultParams, opts.ready]);

  return UseRequestResult<TData, TParams>(
    loading: stateNotifier.value.loading,
    loadingMore: stateNotifier.value.loadingMore,
    data: stateNotifier.value.data,
    error: stateNotifier.value.error,
    params: stateNotifier.value.params,
    hasMore: stateNotifier.value.hasMore,
    isPolling: pollingActiveRef.value,
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
