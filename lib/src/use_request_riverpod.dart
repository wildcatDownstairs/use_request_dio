import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'types.dart';
import 'use_request.dart' show RequestSupersededException, RequestCancelledException;
import 'utils/debounce.dart';
import 'utils/throttle.dart';
import 'utils/retry.dart';
import 'utils/polling.dart';
import 'utils/loading_delay.dart';
import 'utils/focus_manager.dart';
import 'utils/cache.dart';
import 'utils/cache_policy.dart';
import 'utils/cancel_token.dart';

/// 请求状态管理的 StateNotifier 实现
class UseRequestNotifier<TData, TParams> extends StateNotifier<UseRequestState<TData, TParams>> {
  final Service<TData, TParams> service;
  final UseRequestOptions<TData, TParams> options;

  final Map<String, CancelToken?> _cancelTokens = {};
  final Map<String, int> _requestCounts = {};
  final Map<String, TParams?> _lastParamsByKey = {};
  String? _lastKey;
  bool _ready = true;
  List<Object?>? _lastRefreshDeps;

  Debouncer<TData>? _debouncer;
  Throttler<TData>? _throttler;
  PollingController<TData>? _pollingController;
  Timer? _pollingRetryTimer;
  LoadingDelayController? _loadingDelayController;
  AppFocusManager? _focusManager;
  StreamSubscription<bool>? _reconnectSub;

  String _getKey(TParams params) => options.fetchKey?.call(params) ?? '_default';

  UseRequestNotifier({
    required this.service,
    required this.options,
  }) : super(UseRequestState<TData, TParams>(params: options.defaultParams)) {
    _ready = options.ready;
    _lastRefreshDeps = options.refreshDeps != null ? List<Object?>.from(options.refreshDeps!) : null;
    if (options.debounceInterval != null && options.throttleInterval != null) {
      throw ArgumentError('debounceInterval 与 throttleInterval 不能同时设置，请二选一');
    }

    if (options.defaultParams != null) {
      final key = _getKey(options.defaultParams as TParams);
      _lastParamsByKey[key] = options.defaultParams;
      _lastKey = key;
    }
    _initializeUtilities();

    // 非手动模式自动请求
    if (!options.manual && options.defaultParams != null && _ready) {
      run(options.defaultParams as TParams);
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
          if (_lastKey != null) {
            final params = _lastParamsByKey[_lastKey!];
            if (params != null) {
              return _fetchData(_lastKey!, params as TParams);
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
                final hasParams = _lastKey != null && _lastParamsByKey[_lastKey!] != null;
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

      if (!options.manual && _lastKey != null && _lastParamsByKey[_lastKey!] != null && _ready) {
        _pollingController!.start();
      }
    }

    // 初始化聚焦管理
    if (options.refreshOnFocus || (options.pollingInterval != null && !options.pollingWhenHidden)) {
      _focusManager = AppFocusManager(
        onFocus: () {
          if (_lastKey != null && _lastParamsByKey[_lastKey!] != null && _ready) {
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

    // options.refreshDeps 初始触发（静态）
    if (options.refreshDeps != null) {
      refreshDeps(options.refreshDeps!, action: options.refreshDepsAction);
    }

    // refreshOnReconnect：监听外部 reconnectStream
    if (options.refreshOnReconnect && options.reconnectStream != null) {
      _reconnectSub?.cancel();
      _reconnectSub = options.reconnectStream!.listen((online) {
        if (online && _ready && _lastKey != null && _lastParamsByKey[_lastKey!] != null) {
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

  Future<TData> _fetchData(String key, TParams params, {bool isLoadMore = false}) async {
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
    if (!isLoadMore) {
      options.onBefore?.call(params);
    }

    // 读取缓存
    final cacheKey = options.cacheKey?.call(params);
    if (cacheKey != null && cacheKey.isNotEmpty) {
      final pending = getPendingCache<TData>(cacheKey);
      if (pending != null) {
        return pending;
      }

      final coordinator = CacheCoordinator<TData>(
        cacheKey: cacheKey,
        cacheTime: options.cacheTime,
        staleTime: options.staleTime,
      );
      final cachedData = coordinator.getFresh();
      if (cachedData != null) {
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
        state = state.copyWith(loadingMore: true, clearError: true, requestCount: currentRequestCount);
      }
    } else {
      _setLoading(true);
      if (mounted) {
        state = state.copyWith(params: params, clearError: true, requestCount: currentRequestCount);
      }
    }

    try {
      TData result;

      // 执行失败重试（若配置）
      if (options.retryCount != null && options.retryCount! > 0) {
        final future = executeWithRetry<TData>(
          () => service(params),
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
        final future = service(params);
        if (cacheKey != null && cacheKey.isNotEmpty) {
          setPendingCache<TData>(cacheKey, future);
        }
        result = await future;
      }

      // 保证只处理最新一次请求且仅更新 active key
      final latestCount = _requestCounts[key] ?? currentRequestCount;
      final isStaleKey = _lastKey != key;
      if (currentRequestCount != latestCount || cancelToken.isCancelled || isStaleKey) {
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

      // 成功回调
      options.onSuccess?.call(mergedResult, params);

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
      options.onFinally?.call(params, mergedResult, null);

      return mergedResult;
    } catch (e) {
      final latestCount = _requestCounts[key] ?? currentRequestCount;
      final isStaleKey = _lastKey != key;
      final isStale = currentRequestCount != latestCount || isStaleKey;
      final isCancellation = cancelToken.isCancelled ||
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
        state = state.copyWith(
          loading: false,
          loadingMore: false,
          error: e,
        );
      }

      // 失败回调
      options.onError?.call(e, params);

      // 完成回调
      options.onFinally?.call(params, null, e);

      if (cacheKey != null && cacheKey.isNotEmpty) {
        clearCacheEntry(cacheKey);
      }

      return Future.error(e);
    }
  }

  /// 异步执行请求（支持防抖/节流）
  Future<TData> runAsync(TParams params, {bool isLoadMore = false}) async {
    if (!_ready) {
      throw StateError('Request not ready');
    }

    final key = _getKey(params);

    if (_debouncer != null) {
      return _debouncer!.call(() => _fetchData(key, params, isLoadMore: isLoadMore));
    }

    if (_throttler != null) {
      return _throttler!.call(() => _fetchData(key, params, isLoadMore: isLoadMore));
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
    final params = _lastParamsByKey[_lastKey!];
    if (params == null) {
      throw StateError('No previous params to refresh with');
    }
    return runAsync(params as TParams);
  }

  /// 使用上一次参数刷新（不等待返回）
  void refresh() {
    unawaited(refreshAsync().then<void>((_) {}, onError: (_) {}));
  }

  /// 加载更多（异步）
  Future<TData> loadMoreAsync() {
    if (_lastKey == null) {
      throw StateError('No previous key to load more with');
    }
    final lastParams = _lastParamsByKey[_lastKey!];
    if (lastParams == null) {
      throw StateError('No previous params to load more with');
    }
    if (options.loadMoreParams == null) {
      throw StateError('UseRequestOptions.loadMoreParams 未提供，无法加载更多');
    }

    final nextParams = options.loadMoreParams!(lastParams as TParams, state.data);
    return runAsync(nextParams, isLoadMore: true);
  }

  /// 加载更多（不等待返回）
  void loadMore() {
    unawaited(loadMoreAsync().then<void>((_) {}, onError: (_) {}));
  }

  /// 直接修改数据（不触发请求）
  void mutate(TData? Function(TData? oldData)? mutator) {
    if (mutator != null && mounted) {
      final newData = mutator(state.data);
      state = state.copyWith(data: newData, clearData: newData == null);
    }
  }

  /// 取消当前进行中的请求
  void cancel() {
    if (_lastKey != null) {
      _cancelTokens[_lastKey!]?.cancel('Request cancelled by user');
    }
    _loadingDelayController?.endLoading();
    if (mounted) {
      state = state.copyWith(loading: false);
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
  TParams? get lastParams => _lastKey != null ? _lastParamsByKey[_lastKey!] : null;

  /// 切换 ready 状态
  void setReady(bool ready) {
    if (_ready == ready) return;
    _pollingRetryTimer?.cancel();
    _pollingRetryTimer = null;
    _ready = ready;

    if (_ready) {
      if (!options.manual) {
        final params = _lastKey != null ? _lastParamsByKey[_lastKey!] : options.defaultParams;
        if (params != null) {
          run(params as TParams);
        }
      }

      if (options.pollingInterval != null &&
          _pollingController != null &&
          _lastKey != null &&
          _lastParamsByKey[_lastKey!] != null) {
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
      if (_ready && _lastKey != null && _lastParamsByKey[_lastKey!] != null) {
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

    if (action != null) {
      action();
      return;
    }

    if (!options.manual && _ready) {
      final params = _lastKey != null ? _lastParamsByKey[_lastKey!] : options.defaultParams;
      if (params != null) {
        run(params as TParams);
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
StateNotifierProvider<UseRequestNotifier<TData, TParams>, UseRequestState<TData, TParams>>
    createUseRequestProvider<TData, TParams>({
  required Service<TData, TParams> service,
  UseRequestOptions<TData, TParams>? options,
}) {
  return StateNotifierProvider<UseRequestNotifier<TData, TParams>, UseRequestState<TData, TParams>>(
    (ref) => UseRequestNotifier<TData, TParams>(
      service: service,
      options: options ?? const UseRequestOptions(),
    ),
  );
}

/// 在 ConsumerWidget 中以 Hook 风格使用的 Mixin
mixin UseRequestMixin<TData, TParams> {
  late UseRequestNotifier<TData, TParams> _notifier;
  late VoidCallback _removeListener;
  late UseRequestState<TData, TParams> _state;

  void initUseRequest({
    required WidgetRef ref,
    required Service<TData, TParams> service,
    UseRequestOptions<TData, TParams>? options,
  }) {
    _notifier = UseRequestNotifier<TData, TParams>(
      service: service,
      options: options ?? const UseRequestOptions(),
    );
    _state = UseRequestState<TData, TParams>();
    _removeListener = _notifier.addListener((s) {
      _state = s;
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
  void refreshDeps(List<Object?> deps, {VoidCallback? action}) => _notifier.refreshDeps(deps, action: action);
  void setPollingVisible(bool visible) => _notifier.setPollingVisible(visible);
  void mutate(TData? Function(TData? oldData)? mutator) => _notifier.mutate(mutator);
  void cancel() => _notifier.cancel();

  void disposeUseRequest() {
    _removeListener();
    _notifier.dispose();
  }
}

/// 便捷状态判断扩展
extension UseRequestResultExtension<TData, TParams> on UseRequestState<TData, TParams> {
  bool get isLoading => loading;
  bool get hasData => data != null;
  bool get hasError => error != null;
  bool get isSuccess => !loading && data != null && error == null;
  bool get isError => !loading && error != null;
  bool get isIdle => !loading && data == null && error == null;
}

/// 提供 useRequest 能力的组件
class UseRequestBuilder<TData, TParams> extends ConsumerStatefulWidget {
  final Service<TData, TParams> service;
  final UseRequestOptions<TData, TParams>? options;
  final Widget Function(
    BuildContext context,
    UseRequestState<TData, TParams> state,
    UseRequestNotifier<TData, TParams> notifier,
  ) builder;

  const UseRequestBuilder({
    super.key,
    required this.service,
    this.options,
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
    _notifier = UseRequestNotifier<TData, TParams>(
      service: widget.service,
      options: widget.options ?? const UseRequestOptions(),
    );
    _state = UseRequestState<TData, TParams>();
    _removeListener = _notifier.addListener(_onStateChange);
  }

  void _onStateChange(UseRequestState<TData, TParams> state) {
    if (mounted) {
      _state = state;
      setState(() {});
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
