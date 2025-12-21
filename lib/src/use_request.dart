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

  // 使用 Hook 的状态管理（ValueNotifier）保证组件响应式更新
  final stateNotifier = useState(
    UseRequestState<TData, TParams>(params: opts.defaultParams),
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

  // 初始化默认参数的 key
  if (opts.defaultParams != null) {
    final key = getKey(opts.defaultParams as TParams);
    lastParamsMapRef.value[key] = opts.defaultParams;
    lastKeyRef.value = key;
  }

  // 上一次 refreshDeps（用于依赖刷新比较）
  final lastRefreshDepsRef = useRef<List<Object?>?>(opts.refreshDeps);

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

  // 核心请求函数
  Future<TData> fetchData(
    String key,
    TParams params, {
    bool isLoadMore = false,
  }) async {
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
    if (!isLoadMore) {
      opts.onBefore?.call(params);
    }

    // 读取缓存
    final cacheKey = opts.cacheKey?.call(params);
    if (cacheKey != null && cacheKey.isNotEmpty) {
      // 若有进行中的请求，直接复用
      final pending = getPendingCache<TData>(cacheKey);
      if (pending != null) {
        return pending;
      }

      final coordinator = CacheCoordinator<TData>(
        cacheKey: cacheKey,
        cacheTime: opts.cacheTime,
        staleTime: opts.staleTime,
      );
      final cachedData = coordinator.getFresh();
      if (cachedData != null) {
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
      updateState(
        (s) => s.copyWith(
          params: params,
          clearError: true,
          requestCount: currentRequestCount,
        ),
      );
    }

    try {
      TData result;

      // 执行失败重试（若配置）
      if (opts.retryCount != null && opts.retryCount! > 0) {
        final future = executeWithRetry<TData>(
          () => service(params),
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
        final future = service(params);
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

      // 触发成功回调
      opts.onSuccess?.call(mergedResult, params);

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
      opts.onFinally?.call(params, mergedResult, null);

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

      // 触发失败回调
      opts.onError?.call(e, params);

      // 触发完成回调
      opts.onFinally?.call(params, null, e);

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

  // 使用上一次参数刷新（异步）
  Future<TData> refreshAsync() {
    final lastKey = lastKeyRef.value;
    if (lastKey == null) {
      throw StateError('No previous key to refresh with');
    }
    final params = lastParamsMapRef.value[lastKey];
    if (params == null) {
      throw StateError('No previous params to refresh with');
    }
    return runAsync(params);
  }

  // 使用上一次参数刷新（不等待返回）
  void refresh() {
    unawaited(refreshAsync().then<void>((_) {}, onError: (_) {}));
  }

  // 加载更多
  Future<TData> loadMoreAsync() {
    final lastKey = lastKeyRef.value;
    if (lastKey == null) {
      throw StateError('No previous key to load more with');
    }
    final lastParams = lastParamsMapRef.value[lastKey];
    if (lastParams == null) {
      throw StateError('No previous params to load more with');
    }
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

  // 直接修改数据（不触发请求）
  void mutate(TData? Function(TData? oldData)? mutator) {
    if (mutator != null) {
      updateState((s) {
        final newData = mutator(s.data);
        return s.copyWith(data: newData, clearData: newData == null);
      });
    }
  }

  // 取消当前请求
  void cancel() {
    final lastKey = lastKeyRef.value;
    if (lastKey != null) {
      cancelTokenMapRef.value[lastKey]?.cancel('Request cancelled by user');
    }
    loadingDelayControllerRef.value?.endLoading();
    updateState((s) => s.copyWith(loading: false));
  }

  void pausePolling() {
    pollingControllerRef.value?.pause();
    pollingActiveRef.value = false;
    cancel();
  }

  void resumePolling() {
    final lastKey = lastKeyRef.value;
    final hasParams =
        lastKey != null && lastParamsMapRef.value[lastKey] != null;
    if (pollingControllerRef.value != null && hasParams && opts.ready) {
      pollingControllerRef.value!.resume();
      pollingActiveRef.value = true;
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
        opts.refreshDepsAction!();
      } else if (!opts.manual && opts.ready) {
        final params =
            opts.defaultParams ??
            (lastKeyRef.value != null
                ? lastParamsMapRef.value[lastKeyRef.value!]
                : null);
        if (params != null) {
          run(params as TParams);
        }
      }
    }

    return null;
  }, [opts.refreshDeps, opts.ready]);

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
          final key = lastKeyRef.value;
          final params = key != null ? lastParamsMapRef.value[key] : null;
          if (params != null && key != null) {
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
                    lastKey != null && lastParamsMapRef.value[lastKey] != null;
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
      final hasParams =
          lastKey != null && lastParamsMapRef.value[lastKey] != null;
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
            if (opts.ready &&
                key != null &&
                lastParamsMapRef.value[key] != null) {
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
          if (key != null && lastParamsMapRef.value[key] != null) {
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
      run(opts.defaultParams as TParams);
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
