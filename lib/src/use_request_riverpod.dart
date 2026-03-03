import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'types.dart';
import 'use_request.dart'
    show RequestSupersededException, RequestCancelledException;
import 'utils/debounce.dart';
import 'utils/throttle.dart';
import 'utils/retry.dart';
import 'utils/polling.dart';
import 'utils/loading_delay.dart';
import 'utils/focus_manager.dart';
import 'utils/cache.dart';
import 'utils/cache_policy.dart';
import 'utils/cancel_token.dart';
import 'utils/observer.dart';
import 'utils/dio_adapter.dart' show HttpRequestConfig;

({bool isValid, TParams? params}) _resolveInvocableParams<TParams>(
  Object? candidate,
) {
  try {
    return (isValid: true, params: candidate as TParams);
  } catch (_) {
    return (isValid: false, params: null);
  }
}

UseRequestState<TData, TParams> _buildInitialState<TData, TParams>(
  UseRequestOptions<TData, TParams> options,
) {
  final cacheKeyBuilder = options.cacheKey;
  TData? initialData;

  // Riverpod 版和 Hook 版保持一致：如果默认参数对应的缓存已经存在，
  // 创建 notifier 时就先把缓存回填进 state，避免页面首次 build 先渲染默认值。
  if (cacheKeyBuilder != null &&
      (options.defaultParams != null || !options.manual)) {
    final resolved = _resolveInvocableParams<TParams>(options.defaultParams);
    if (resolved.isValid) {
      final params = resolved.params as TParams;
      final cacheKey = cacheKeyBuilder(params);
      if (cacheKey.isNotEmpty) {
        final coordinator = CacheCoordinator<TData>(
          cacheKey: cacheKey,
          cacheTime: options.cacheTime,
          staleTime: options.staleTime,
        );
        initialData = coordinator.getFresh();
      }
    }
  }

  return UseRequestState<TData, TParams>(
    params: options.defaultParams,
    data: initialData ?? options.initialData,
  );
}

/// 请求状态管理的 StateNotifier 实现
class UseRequestNotifier<TData, TParams>
    extends StateNotifier<UseRequestState<TData, TParams>> {
  final Service<TData, TParams> service;
  UseRequestOptions<TData, TParams> options;

  final Map<String, CancelToken?> _cancelTokens = {};
  final Map<String, int> _requestCounts = {};
  final Map<String, TParams?> _lastParamsByKey = {};
  String? _lastKey;
  bool _ready = true;
  List<Object?>? _lastRefreshDeps;
  bool _pendingRefreshDeps = false;
  VoidCallback? _lastRefreshDepsAction;

  Debouncer<TData>? _debouncer;
  Throttler<TData>? _throttler;
  PollingController<TData>? _pollingController;
  Timer? _pollingRetryTimer;
  LoadingDelayController? _loadingDelayController;
  AppFocusManager? _focusManager;
  StreamSubscription<bool>? _reconnectSub;

  String _getKey(TParams params) =>
      options.fetchKey?.call(params) ?? '_default';

  bool _hasLastInvocationForKey(String key) =>
      _lastParamsByKey.containsKey(key);

  bool _runIfInvocable(Object? candidate) {
    final resolved = _resolveInvocableParams<TParams>(candidate);
    if (!resolved.isValid) return false;
    run(resolved.params as TParams);
    return true;
  }

  /// 对外暴露一个只读快照，避免 UI 层直接访问 StateNotifier 的受保护成员 `state`。
  ///
  /// 这样 Builder / mixin 仍然能在首帧同步拿到当前状态，但不会踩到 analyzer
  /// 对 protected 成员的可见性约束。
  UseRequestState<TData, TParams> get currentState => state;

  UseRequestNotifier({required this.service, required this.options})
    : super(_buildInitialState<TData, TParams>(options)) {
    _ready = options.ready;
    _lastRefreshDeps = options.refreshDeps == null
        ? null
        : List<Object?>.from(options.refreshDeps!);
    _lastRefreshDepsAction = options.refreshDepsAction;
    if (options.debounceInterval != null && options.throttleInterval != null) {
      throw ArgumentError('debounceInterval 与 throttleInterval 不能同时设置，请二选一');
    }

    final initialParams = _resolveInvocableParams<TParams>(
      options.defaultParams,
    );
    if (initialParams.isValid) {
      final params = initialParams.params as TParams;
      final key = _getKey(params);
      _lastParamsByKey[key] = params;
      _lastKey = key;
    }
    _initializeUtilities();

    // 非手动模式自动请求
    if (!options.manual && _ready) {
      _runIfInvocable(options.defaultParams);
    }
  }

  void _initializeUtilities() {
    // 初始化防抖
    if (options.debounceInterval != null) {
      _debouncer = Debouncer<TData>(
        duration: options.debounceInterval!,
        leading: options.debounceLeading,
        trailing: options.debounceTrailing,
        maxWait: options.debounceMaxWait,
      );
    }

    // 初始化节流
    if (options.throttleInterval != null) {
      _throttler = Throttler<TData>(
        duration: options.throttleInterval!,
        leading: options.throttleLeading,
        trailing: options.throttleTrailing,
        maxWait: options.throttleInterval,
      );
    }

    // 初始化轮询
    if (options.pollingInterval != null) {
      _pollingController = PollingController<TData>(
        interval: options.pollingInterval!,
        action: () {
          // 注意：当配置了 loadMoreParams（分页模式）时，轮询使用 defaultParams
          // 刷新首页数据，而非使用 lastParams（可能是某一页的参数），
          // 避免轮询覆盖已累积的分页数据。
          if (_lastKey != null) {
            if (_hasLastInvocationForKey(_lastKey!)) {
              final TParams params;
              if (options.loadMoreParams != null &&
                  options.defaultParams != null) {
                params = options.defaultParams as TParams;
              } else {
                params = _lastParamsByKey[_lastKey!] as TParams;
              }
              return _fetchData(_lastKey!, params);
            }
          }
          throw StateError('No params for polling');
        },
        onError: (_) {
          if (options.pausePollingOnError) {
            _pollingController?.pause();

            _pollingRetryTimer?.cancel();
            if (options.pollingRetryInterval != null) {
              _pollingRetryTimer = Timer(options.pollingRetryInterval!, () {
                if (!_ready || _pollingController == null) return;
                final hasParams =
                    _lastKey != null && _hasLastInvocationForKey(_lastKey!);
                final hasEverRun = state.requestCount > 0;
                final shouldAutoStart = !options.manual;
                final canPoll = hasParams && (shouldAutoStart || hasEverRun);
                if (canPoll) {
                  if (!_pollingController!.isRunning) {
                    _pollingController!.start();
                  } else {
                    _pollingController!.resume();
                  }
                }
              });
            }
          }
        },
      );

      if (!options.manual &&
          _lastKey != null &&
          _hasLastInvocationForKey(_lastKey!) &&
          _ready) {
        _pollingController!.start();
      }
    }

    // 初始化聚焦管理
    if (options.refreshOnFocus ||
        (options.pollingInterval != null && !options.pollingWhenHidden)) {
      _focusManager = AppFocusManager(
        onFocus: () {
          if (_lastKey != null &&
              _hasLastInvocationForKey(_lastKey!) &&
              _ready) {
            if (options.refreshOnFocus) {
              refresh();
            }
            if (options.pollingInterval != null && !options.pollingWhenHidden) {
              _pollingController?.resume();
            }
          }
        },
        onBlur: () {
          if (options.pollingInterval != null && !options.pollingWhenHidden) {
            _pollingController?.pause();
          }
        },
      );
      _focusManager!.start();
    }

    // refreshOnReconnect：监听外部 reconnectStream
    if (options.refreshOnReconnect && options.reconnectStream != null) {
      _reconnectSub?.cancel();
      _reconnectSub = options.reconnectStream!.listen((online) {
        if (online &&
            _ready &&
            _lastKey != null &&
            _hasLastInvocationForKey(_lastKey!)) {
          refresh();
        }
      });
    }
  }

  void _setLoading(bool loading) {
    if (options.loadingDelay != null && loading) {
      _loadingDelayController?.cancel();
      _loadingDelayController = LoadingDelayController(
        delay: options.loadingDelay!,
        onLoadingChange: (value) {
          if (mounted) {
            state = state.copyWith(loading: value);
          }
        },
      );
      _loadingDelayController!.startLoading();
    } else {
      _loadingDelayController?.endLoading();
      if (mounted) {
        state = state.copyWith(loading: loading);
      }
    }
  }

  Future<TData> _bindPendingRequest(
    Future<TData> pending,
    String key,
    TParams params,
    int currentRequestCount, {
    bool isLoadMore = false,
  }) async {
    if (isLoadMore) {
      if (mounted) {
        state = state.copyWith(
          loadingMore: true,
          params: params,
          clearError: true,
          requestCount: currentRequestCount,
        );
      }
    } else {
      _setLoading(true);
      if (mounted) {
        state = state.copyWith(
          params: params,
          clearError: true,
          requestCount: currentRequestCount,
        );
      }
    }

    try {
      final result = await pending;
      final latestCount = _requestCounts[key] ?? currentRequestCount;
      final isStaleKey = _lastKey != key;
      final cancelToken = _cancelTokens[key];
      if (currentRequestCount != latestCount ||
          isStaleKey ||
          (cancelToken?.isCancelled ?? false)) {
        return result;
      }

      final mergedResult = isLoadMore && options.dataMerger != null
          ? options.dataMerger!(state.data, result)
          : result;

      _loadingDelayController?.endLoading();
      if (mounted) {
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          data: mergedResult,
          clearError: true,
          hasMore: options.hasMore?.call(mergedResult) ?? state.hasMore,
        );
      }

      // 复用请求同样触发成功和完成回调
      try {
        options.onSuccess?.call(mergedResult, params);
      } catch (_) {}
      try {
        options.onFinally?.call(params, mergedResult, null);
      } catch (_) {}

      return mergedResult;
    } catch (e) {
      final latestCount = _requestCounts[key] ?? currentRequestCount;
      final isStaleKey = _lastKey != key;
      final cancelToken = _cancelTokens[key];
      final isStale = currentRequestCount != latestCount || isStaleKey;
      final isCancellation =
          (cancelToken?.isCancelled ?? false) ||
          e is RequestSupersededException ||
          e is RequestCancelledException ||
          e is RetryCancelledException ||
          (e is DioException && e.type == DioExceptionType.cancel);

      if (!isStale && !isCancellation && mounted) {
        _loadingDelayController?.endLoading();
        state = state.copyWith(loading: false, loadingMore: false, error: e);
        // 复用请求同样触发失败和完成回调
        try {
          options.onError?.call(e, params);
        } catch (_) {}
        try {
          options.onFinally?.call(params, null, e);
        } catch (_) {}
      }

      return Future.error(e);
    }
  }

  Future<TData> _fetchData(
    String key,
    TParams params, {
    bool isLoadMore = false,
  }) async {
    // If the params is HttpRequestConfig, merge default timeouts from options.
    final TParams callParams;
    if (params is HttpRequestConfig) {
      final config = params;
      callParams =
          config.copyWith(
                connectTimeout: config.connectTimeout ?? options.connectTimeout,
                receiveTimeout: config.receiveTimeout ?? options.receiveTimeout,
                sendTimeout: config.sendTimeout ?? options.sendTimeout,
              )
              as TParams;
    } else {
      callParams = params;
    }

    final currentRequestCount = (_requestCounts[key] ?? 0) + 1;
    _requestCounts[key] = currentRequestCount;

    // 创建新的取消令牌
    _cancelTokens[key]?.cancel('New request started');
    final cancelToken = createLinkedCancelToken(options.cancelToken);
    _cancelTokens[key] = cancelToken;

    // 记录当前参数，用于刷新
    _lastParamsByKey[key] = params;
    _lastKey = key;

    // 调用 onBefore 回调
    // 注意：loadMore 场景下不会触发 onBefore，因为 loadMore 是追加数据操作，
    // 而非全新请求。如需在 loadMore 前执行逻辑，请在调用 loadMore() 前自行处理。
    if (!isLoadMore) {
      try {
        options.onBefore?.call(params);
      } catch (_) {}
    }

    // 通知全局观察者
    notifyRequestObserverRequest(key, params);

    // 读取缓存
    TData? cachedData;
    final cacheKey = options.cacheKey?.call(params);
    if (cacheKey != null && cacheKey.isNotEmpty) {
      final pending = getPendingCache<TData>(cacheKey);
      if (pending != null) {
        return _bindPendingRequest(
          pending,
          key,
          params,
          currentRequestCount,
          isLoadMore: isLoadMore,
        );
      }

      final coordinator = CacheCoordinator<TData>(
        cacheKey: cacheKey,
        cacheTime: options.cacheTime,
        staleTime: options.staleTime,
      );
      cachedData = coordinator.getFresh();
      if (cachedData != null) {
        notifyRequestObserverCacheHit(cacheKey, coordinator.shouldRevalidate());
        if (mounted) {
          state = state.copyWith(
            loading: false,
            data: cachedData,
            params: params,
            clearError: true,
            requestCount: currentRequestCount,
          );
        }
        if (!coordinator.shouldRevalidate()) {
          return cachedData;
        }
      }
    }

    // 进入 loading 状态
    if (isLoadMore) {
      if (mounted) {
        state = state.copyWith(
          loadingMore: true,
          clearError: true,
          requestCount: currentRequestCount,
        );
      }
    } else {
      _setLoading(true);
      // keepPreviousData=false（默认）且参数变化时清除旧数据
      final shouldClearData =
          !options.keepPreviousData &&
          cachedData == null &&
          state.params != params;
      if (mounted) {
        state = state.copyWith(
          params: params,
          clearError: true,
          clearData: shouldClearData,
          requestCount: currentRequestCount,
        );
      }
    }

    try {
      TData result;

      // 执行失败重试（若配置）
      if (options.retryCount != null && options.retryCount! > 0) {
        final future = executeWithRetry<TData>(
          () => service(callParams),
          maxRetries: options.retryCount!,
          retryInterval: options.retryInterval ?? const Duration(seconds: 1),
          cancelToken: cancelToken,
          onRetry: (attempt, err) {
            options.onRetryAttempt?.call(attempt, err);
          },
          exponential: options.retryExponential,
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

      // 保证只处理最新一次请求且仅更新 active key
      final latestCount = _requestCounts[key] ?? currentRequestCount;
      final isStaleKey = _lastKey != key;
      if (currentRequestCount != latestCount ||
          cancelToken.isCancelled ||
          isStaleKey) {
        return result;
      }

      final mergedResult = isLoadMore && options.dataMerger != null
          ? options.dataMerger!(state.data, result)
          : result;

      // 更新成功态
      _loadingDelayController?.endLoading();
      if (mounted) {
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          data: mergedResult,
          clearError: true,
          hasMore: options.hasMore?.call(mergedResult) ?? state.hasMore,
        );
      }

      // 成功回调（捕获回调异常，确保后续缓存写入和 onFinally 不被跳过）
      try {
        options.onSuccess?.call(mergedResult, params);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverSuccess(key, mergedResult, params);

      // 写入缓存
      if (cacheKey != null && cacheKey.isNotEmpty) {
        setCache<TData>(cacheKey, mergedResult);
      }

      // 若配置了轮询且尚未启动，在首次成功后启动（手动模式也支持）
      if (options.pollingInterval != null &&
          _pollingController != null &&
          _lastKey != null &&
          _lastParamsByKey[_lastKey!] != null &&
          !_pollingController!.isRunning &&
          _ready) {
        _pollingController!.start();
      }

      // 完成回调
      try {
        options.onFinally?.call(params, mergedResult, null);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverFinally(key, params);

      return mergedResult;
    } catch (e) {
      final latestCount = _requestCounts[key] ?? currentRequestCount;
      final isStaleKey = _lastKey != key;
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
      _loadingDelayController?.endLoading();
      if (mounted) {
        state = state.copyWith(loading: false, loadingMore: false, error: e);
      }

      // 失败回调（捕获回调异常，确保 onFinally 和缓存清理不被跳过）
      try {
        options.onError?.call(e, params);
      } catch (_) {
        // 回调异常不应中断请求流程
      }
      notifyRequestObserverError(key, e, params);

      // 完成回调
      try {
        options.onFinally?.call(params, null, e);
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

  /// 异步执行请求（支持防抖/节流）
  Future<TData> runAsync(TParams params, {bool isLoadMore = false}) async {
    final key = _getKey(params);

    if (_debouncer != null) {
      return _debouncer!.call(
        () => _fetchData(key, params, isLoadMore: isLoadMore),
      );
    }

    if (_throttler != null) {
      return _throttler!.call(
        () => _fetchData(key, params, isLoadMore: isLoadMore),
      );
    }

    return _fetchData(key, params, isLoadMore: isLoadMore);
  }

  /// 触发请求（不等待返回）
  void run(TParams params) {
    unawaited(runAsync(params).then<void>((_) {}, onError: (_) {}));
  }

  /// 使用上一次参数刷新（异步）
  Future<TData> refreshAsync() {
    if (_lastKey == null) {
      throw StateError('No previous key to refresh with');
    }
    if (!_lastParamsByKey.containsKey(_lastKey!)) {
      throw StateError('No previous params to refresh with');
    }
    final params = _lastParamsByKey[_lastKey!];
    // 安全类型检查：当 TParams 为非空类型而 params 为 null 时，
    // 尝试回退到 defaultParams，避免运行时 _CastError。
    final resolved = _resolveInvocableParams<TParams>(params);
    if (!resolved.isValid) {
      final fallback = _resolveInvocableParams<TParams>(options.defaultParams);
      if (fallback.isValid) {
        return runAsync(fallback.params as TParams);
      }
      throw StateError(
        'Cannot refresh: last params ($params) is not a valid $TParams '
        'and no usable defaultParams available',
      );
    }
    return runAsync(params as TParams);
  }

  /// 使用上一次参数刷新（不等待返回）
  void refresh() {
    unawaited(refreshAsync().then<void>((_) {}, onError: (_) {}));
  }

  /// 加载更多（异步）
  Future<TData> loadMoreAsync() {
    // 如果 hasMore 明确为 false，不再发起请求
    if (state.hasMore == false) {
      return Future.error(StateError('没有更多数据可加载（hasMore 为 false）'));
    }
    if (_lastKey == null) {
      throw StateError('No previous key to load more with');
    }
    if (!_lastParamsByKey.containsKey(_lastKey!)) {
      throw StateError('No previous params to load more with');
    }
    final lastParams = _lastParamsByKey[_lastKey!];
    if (options.loadMoreParams == null) {
      throw StateError('UseRequestOptions.loadMoreParams 未提供，无法加载更多');
    }

    final nextParams = options.loadMoreParams!(
      lastParams as TParams,
      state.data,
    );
    return runAsync(nextParams, isLoadMore: true);
  }

  /// 加载更多（不等待返回）
  void loadMore() {
    unawaited(loadMoreAsync().then<void>((_) {}, onError: (_) {}));
  }

  /// 直接修改数据（不触发请求），同步写入全局缓存
  void mutate(TData? Function(TData? oldData)? mutator) {
    if (mutator != null && mounted) {
      final oldData = state.data;
      final newData = mutator(state.data);
      state = state.copyWith(data: newData, clearData: newData == null);
      // 同步写入全局缓存
      if (_lastKey != null) {
        final lastParams = _lastParamsByKey[_lastKey!];
        if (lastParams != null && options.cacheKey != null) {
          final ck = options.cacheKey!(lastParams as TParams);
          if (ck.isNotEmpty) {
            if (newData != null) {
              setCache<TData>(ck, newData);
            } else {
              clearCacheEntry(ck);
            }
          }
        }
        notifyRequestObserverMutate(_lastKey!, oldData, newData);
      }
    }
  }

  /// 取消当前进行中的请求（取消所有 key 的请求）
  void cancel() {
    for (final entry in _cancelTokens.entries) {
      entry.value?.cancel('Request cancelled by user');
      notifyRequestObserverCancel(entry.key);
    }
    _loadingDelayController?.endLoading();
    if (mounted) {
      state = state.copyWith(loading: false, loadingMore: false);
    }
  }

  /// 开始轮询
  void startPolling() {
    _pollingController?.start();
  }

  /// 停止轮询
  void stopPolling() {
    _pollingRetryTimer?.cancel();
    _pollingRetryTimer = null;
    _pollingController?.stop();
  }

  /// 获取上一次请求参数
  TParams? get lastParams =>
      _lastKey != null ? _lastParamsByKey[_lastKey!] : null;

  /// 切换 ready 状态
  void setReady(bool ready) {
    if (_ready == ready) return;
    _pollingRetryTimer?.cancel();
    _pollingRetryTimer = null;
    _ready = ready;

    if (_ready) {
      var replayedPendingWork = false;
      if (_pendingRefreshDeps && _lastRefreshDeps != null) {
        _pendingRefreshDeps = false;
        replayedPendingWork = true;
        final action = _lastRefreshDepsAction;
        if (action != null) {
          action();
        } else if (!options.manual) {
          final params = _lastKey != null
              ? _lastParamsByKey[_lastKey!]
              : options.defaultParams;
          // 与 Hook 版保持一致：即使 params 为 null（无参请求），也应触发 run。
          _runIfInvocable(params);
        }
      }
      if (!replayedPendingWork && !options.manual) {
        final params = _lastKey != null
            ? _lastParamsByKey[_lastKey!]
            : options.defaultParams;
        _runIfInvocable(params);
      }

      if (options.pollingInterval != null &&
          _pollingController != null &&
          _lastKey != null &&
          _hasLastInvocationForKey(_lastKey!)) {
        _pollingController!.start();
      }
    } else {
      _pollingController?.pause();
    }
  }

  /// 切换轮询可见性策略（仅暂停/恢复，不改变 ready）
  void setPollingVisible(bool visible) {
    if (options.pollingInterval == null || _pollingController == null) return;
    if (visible) {
      if (_ready && _lastKey != null && _hasLastInvocationForKey(_lastKey!)) {
        _pollingController!.resume();
      }
    } else {
      _pollingController?.pause();
    }
  }

  /// 依赖变更触发刷新（类似 refreshDeps）
  void refreshDeps(List<Object?> deps, {VoidCallback? action}) {
    final prev = _lastRefreshDeps;
    final changed = prev == null || !listEquals(prev, deps);
    if (!changed) return;

    _lastRefreshDeps = List<Object?>.from(deps);
    _lastRefreshDepsAction = action;

    if (action != null) {
      action();
      _pendingRefreshDeps = false;
      return;
    }

    if (!options.manual && _ready) {
      final params = _lastKey != null
          ? _lastParamsByKey[_lastKey!]
          : options.defaultParams;
      // refreshDeps 语义：依赖变化时触发一次刷新，无参请求也应生效。
      _runIfInvocable(params);
      _pendingRefreshDeps = false;
    } else {
      _pendingRefreshDeps = true;
    }
  }

  /// 动态更新配置参数（防抖/节流/轮询等工具参数），不销毁 Notifier、不丢失状态。
  ///
  /// 仅当工具相关参数发生变化时才会重建对应工具实例，轮询状态（运行/暂停）会被保留。
  void updateOptions(UseRequestOptions<TData, TParams> newOptions) {
    final old = options;
    options = newOptions;

    // — 防抖参数变化 —
    final debounceChanged =
        old.debounceInterval != newOptions.debounceInterval ||
        old.debounceLeading != newOptions.debounceLeading ||
        old.debounceTrailing != newOptions.debounceTrailing ||
        old.debounceMaxWait != newOptions.debounceMaxWait;
    if (debounceChanged) {
      _debouncer?.dispose();
      _debouncer = null;
      if (newOptions.debounceInterval != null) {
        _debouncer = Debouncer<TData>(
          duration: newOptions.debounceInterval!,
          leading: newOptions.debounceLeading,
          trailing: newOptions.debounceTrailing,
          maxWait: newOptions.debounceMaxWait,
        );
      }
    }

    // — 节流参数变化 —
    final throttleChanged =
        old.throttleInterval != newOptions.throttleInterval ||
        old.throttleLeading != newOptions.throttleLeading ||
        old.throttleTrailing != newOptions.throttleTrailing;
    if (throttleChanged) {
      _throttler?.dispose();
      _throttler = null;
      if (newOptions.throttleInterval != null) {
        _throttler = Throttler<TData>(
          duration: newOptions.throttleInterval!,
          leading: newOptions.throttleLeading,
          trailing: newOptions.throttleTrailing,
          maxWait: newOptions.throttleInterval,
        );
      }
    }

    // — 轮询参数变化 —
    final pollingChanged = old.pollingInterval != newOptions.pollingInterval;
    if (pollingChanged) {
      final wasRunning = _pollingController?.isRunning ?? false;
      _pollingRetryTimer?.cancel();
      _pollingRetryTimer = null;
      _pollingController?.dispose();
      _pollingController = null;

      if (newOptions.pollingInterval != null) {
        _pollingController = PollingController<TData>(
          interval: newOptions.pollingInterval!,
          action: () {
            if (_lastKey != null) {
              if (_hasLastInvocationForKey(_lastKey!)) {
                final TParams params;
                if (options.loadMoreParams != null &&
                    options.defaultParams != null) {
                  params = options.defaultParams as TParams;
                } else {
                  params = _lastParamsByKey[_lastKey!] as TParams;
                }
                return _fetchData(_lastKey!, params);
              }
            }
            throw StateError('No params for polling');
          },
          onError: (_) {
            if (options.pausePollingOnError) {
              _pollingController?.pause();
              _pollingRetryTimer?.cancel();
              if (options.pollingRetryInterval != null) {
                _pollingRetryTimer = Timer(options.pollingRetryInterval!, () {
                  if (!_ready || _pollingController == null) return;
                  final hasParams =
                      _lastKey != null && _hasLastInvocationForKey(_lastKey!);
                  final hasEverRun = state.requestCount > 0;
                  final shouldAutoStart = !options.manual;
                  final canPoll = hasParams && (shouldAutoStart || hasEverRun);
                  if (canPoll) {
                    if (!_pollingController!.isRunning) {
                      _pollingController!.start();
                    } else {
                      _pollingController!.resume();
                    }
                  }
                });
              }
            }
          },
        );
        // 恢复之前的运行状态
        if (wasRunning && _ready) {
          _pollingController!.start();
        }
      }
    }
  }

  @override
  void dispose() {
    _debouncer?.dispose();
    _throttler?.dispose();
    _pollingController?.dispose();
    _pollingRetryTimer?.cancel();
    _loadingDelayController?.dispose();
    _focusManager?.dispose();
    _reconnectSub?.cancel();
    for (final token in _cancelTokens.values) {
      token?.cancel('Notifier disposed');
    }
    super.dispose();
  }
}

/// useRequest 的 Provider 工厂
/// 用法示例：
/// ```dart
/// final myRequestProvider = createUseRequestProvider<MyData, MyParams>(
///   service: (params) => fetchMyData(params),
/// );
/// ```
StateNotifierProvider<
  UseRequestNotifier<TData, TParams>,
  UseRequestState<TData, TParams>
>
createUseRequestProvider<TData, TParams>({
  required Service<TData, TParams> service,
  UseRequestOptions<TData, TParams>? options,
}) {
  return StateNotifierProvider<
    UseRequestNotifier<TData, TParams>,
    UseRequestState<TData, TParams>
  >(
    (ref) => UseRequestNotifier<TData, TParams>(
      service: service,
      options: options ?? const UseRequestOptions(),
    ),
  );
}

/// 在 ConsumerStatefulWidget 中以 Hook 风格使用的 Mixin
///
/// 使用方式：
/// 1. 在 `initState` 中调用 `initUseRequest`，传入 `setState` 回调以触发 UI 重建
/// 2. 在 `dispose` 中调用 `disposeUseRequest`
///
/// ```dart
/// class _MyPageState extends ConsumerState<MyPage>
///     with UseRequestMixin<MyData, MyParams> {
///   @override
///   void initState() {
///     super.initState();
///     initUseRequest(
///       ref: ref,
///       service: myService,
///       onStateChange: () => setState(() {}),
///     );
///   }
///   @override
///   void dispose() {
///     disposeUseRequest();
///     super.dispose();
///   }
/// }
/// ```
mixin UseRequestMixin<TData, TParams> {
  late UseRequestNotifier<TData, TParams> _notifier;
  late VoidCallback _removeListener;
  late UseRequestState<TData, TParams> _state;

  void initUseRequest({
    required WidgetRef ref,
    required Service<TData, TParams> service,
    UseRequestOptions<TData, TParams>? options,

    /// 状态变化时的回调，通常传入 `() => setState(() {})` 以触发 UI 重建。
    /// 若不传则 UI 不会自动响应状态变化。
    VoidCallback? onStateChange,
  }) {
    _notifier = UseRequestNotifier<TData, TParams>(
      service: service,
      options: options ?? const UseRequestOptions(),
    );
    _state = _notifier.currentState;
    _removeListener = _notifier.addListener((s) {
      _state = s;
      onStateChange?.call();
    });
  }

  UseRequestState<TData, TParams> get state => _state;

  Future<TData> runAsync(TParams params) => _notifier.runAsync(params);
  void run(TParams params) => _notifier.run(params);
  Future<TData> refreshAsync() => _notifier.refreshAsync();
  void refresh() => _notifier.refresh();
  Future<TData> loadMoreAsync() => _notifier.loadMoreAsync();
  void loadMore() => _notifier.loadMore();
  void setReady(bool ready) => _notifier.setReady(ready);
  void refreshDeps(List<Object?> deps, {VoidCallback? action}) =>
      _notifier.refreshDeps(deps, action: action);
  void setPollingVisible(bool visible) => _notifier.setPollingVisible(visible);
  void mutate(TData? Function(TData? oldData)? mutator) =>
      _notifier.mutate(mutator);
  void cancel() => _notifier.cancel();

  /// 动态更新工具参数（防抖/节流/轮询间隔等），不丢失请求状态。
  void updateOptions(UseRequestOptions<TData, TParams> newOptions) =>
      _notifier.updateOptions(newOptions);

  void disposeUseRequest() {
    _removeListener();
    _notifier.dispose();
  }
}

/// 便捷状态判断扩展
extension UseRequestResultExtension<TData, TParams>
    on UseRequestState<TData, TParams> {
  bool get isLoading => loading;
  bool get hasData => data != null;
  bool get hasError => error != null;
  bool get isSuccess => !loading && data != null && error == null;
  bool get isError => !loading && error != null;
  bool get isIdle => !loading && data == null && error == null;
}

/// 提供 useRequest 能力的组件
///
/// 注意：[service] 参数使用函数引用比较。为避免 parent rebuild 时因闭包引用变化
/// 导致 notifier 被不必要地销毁重建，建议：
/// 1. 使用顶层函数或 static 方法作为 service
/// 2. 或通过 [serviceKey] 显式控制何时重建
class UseRequestBuilder<TData, TParams> extends ConsumerStatefulWidget {
  final Service<TData, TParams> service;
  final UseRequestOptions<TData, TParams>? options;

  /// 可选的 service 标识 key。
  /// 当 service 为闭包/匿名函数时，可通过此 key 控制何时重建 notifier。
  /// 仅当 serviceKey 发生变化时才会销毁旧 notifier 并重建。
  /// 若为 null，service 变化不会触发重建（避免闭包引用陷阱）。
  final Object? serviceKey;

  final Widget Function(
    BuildContext context,
    UseRequestState<TData, TParams> state,
    UseRequestNotifier<TData, TParams> notifier,
  )
  builder;

  const UseRequestBuilder({
    super.key,
    required this.service,
    this.options,
    this.serviceKey,
    required this.builder,
  });

  @override
  ConsumerState<UseRequestBuilder<TData, TParams>> createState() =>
      _UseRequestBuilderState<TData, TParams>();
}

class _UseRequestBuilderState<TData, TParams>
    extends ConsumerState<UseRequestBuilder<TData, TParams>> {
  late UseRequestNotifier<TData, TParams> _notifier;
  late VoidCallback _removeListener;
  late UseRequestState<TData, TParams> _state;

  @override
  void initState() {
    super.initState();
    _bindNotifier();
  }

  void _bindNotifier() {
    _notifier = UseRequestNotifier<TData, TParams>(
      service: widget.service,
      options: widget.options ?? const UseRequestOptions(),
    );
    _state = _notifier.currentState;
    _removeListener = _notifier.addListener(_onStateChange);
  }

  void _onStateChange(UseRequestState<TData, TParams> state) {
    if (mounted) {
      _state = state;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant UseRequestBuilder<TData, TParams> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 使用 serviceKey 判断 service 是否需要重建（避免闭包引用陷阱），
    // 若未提供 serviceKey 则不对 service 变化做判断。
    final serviceChanged =
        widget.serviceKey != null && oldWidget.serviceKey != widget.serviceKey;
    if (serviceChanged) {
      // service 变化：必须销毁重建
      _removeListener();
      _notifier.dispose();
      _bindNotifier();
      setState(() {});
    } else if (oldWidget.options != widget.options) {
      // 仅 options 变化：动态更新工具参数，保留请求状态
      _notifier.updateOptions(widget.options ?? const UseRequestOptions());
    }
  }

  @override
  void dispose() {
    _removeListener();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _state, _notifier);
  }
}
