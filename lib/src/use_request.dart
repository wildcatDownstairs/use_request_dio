import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';

import 'types.dart';
import 'use_request_riverpod.dart' show UseRequestNotifier;

/// Hook 适配层。
///
/// 请求状态机由 [UseRequestNotifier] 统一维护；这里仅把它接入 Hook 生命周期。
UseRequestResult<TData, TParams> useRequest<TData, TParams>(
  Service<TData, TParams> service, {
  UseRequestOptions<TData, TParams>? options,
}) {
  final opts = options ?? const UseRequestOptions();
  final serviceRef = useRef(service);
  serviceRef.value = service;

  final notifier = useMemoized(
    () => UseRequestNotifier<TData, TParams>(
      service: (params) => serviceRef.value(params),
      options: opts,
      startAutomatically: false,
    ),
    const [],
  );
  final state = useState(notifier.currentState);
  final isPolling = useValueListenable(notifier.pollingListenable);

  useEffect(() {
    final removeListener = notifier.addListener((next) {
      state.value = next;
    });
    return () {
      removeListener();
      notifier.dispose();
    };
  }, const []);

  // options 的相等判断有意忽略函数和 defaultParams 等字段。每次 build 都把
  // 最新配置交给 Notifier，由其逐项判断真正需要重建的控制器和副作用。
  useEffect(() {
    notifier.updateOptions(opts);
    return null;
  });

  useEffect(() {
    if (!opts.manual && opts.ready) {
      notifier.runWithLastOrDefaultParams();
    }
    return null;
  }, const []);

  final previousManual = useRef(opts.manual);
  final previousReady = useRef(opts.ready);
  useEffect(() {
    final becameAutomaticWhileReady =
        previousManual.value && !opts.manual && previousReady.value;
    previousManual.value = opts.manual;
    previousReady.value = opts.ready;
    if (becameAutomaticWhileReady && opts.ready) {
      notifier.runWithLastOrDefaultParams();
    }
    return null;
  }, [opts.manual, opts.ready]);

  Future<TData> runAsync(TParams params) => notifier.runAsync(params);
  void run(TParams params) => notifier.run(params);
  Future<TData> refreshAsync() => notifier.refreshAsync();
  void refresh() => notifier.refresh();
  Future<TData> loadMoreAsync() => notifier.loadMoreAsync();
  void loadMore() => notifier.loadMore();
  void mutate(TData? Function(TData? oldData)? mutator) =>
      notifier.mutate(mutator);
  void cancel() => notifier.cancel();
  void pausePolling() {
    notifier.pausePolling();
  }

  void resumePolling() {
    notifier.resumePolling();
  }

  final current = state.value;
  return UseRequestResult<TData, TParams>(
    loading: current.loading,
    loadingMore: current.loadingMore,
    data: current.data,
    error: current.error,
    params: current.params,
    hasMore: current.hasMore,
    isPolling: isPolling,
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

/// 闭包驱动版 useRequest。
UseRequestResult<TData, Null> useRequestFn<TData>(
  Future<TData> Function() service, {
  UseRequestOptions<TData, Null>? options,
}) {
  final serviceRef = useRef(service);
  serviceRef.value = service;
  return useRequest<TData, Null>((_) => serviceRef.value(), options: options);
}
