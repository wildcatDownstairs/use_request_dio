# Request contracts

[简体中文](contracts.zh-CN.md) · [Full guide](guide.en.md)

Hooks, `UseRequestNotifier`, and `UseRequestBuilder` share one state machine. The 0.7.0 unified exports and existing public APIs remain available.

## Execution

- Services may return any `Future<T>`. Use `useRequestFn` for captured filters and `run(params)` for explicit actions.
- `refresh()` reuses the latest invocation's parameters. `refreshDeps` controls timing, not parameter replacement. Hooks update service/options on every build, including callbacks.
- `ready` controls automatic execution, dependency refresh, and polling. Explicit `run` still executes; `refreshDepsAction` delegates dependency changes to the caller.
- `fetchKey` isolates counters/cancellation, but UI state has one active key: only the most recently invoked key may update it.
- `focusTimespan` defaults to 5 seconds. It limits focus refresh, without blocking polling from resuming.

## Cache

`cacheKey` identifies both in-memory data and pending deduplication. Include business parameters and account identity in keys; consumers sharing a key must agree on data type and request semantics.

- Mounted, receptive consumers of the same key receive successful writes, `setCache`, and `mutate` updates. Switching keys or disposing removes the old subscription.
- `mutate((_) => null)` removes cached data and broadcasts null without cancelling pending work. That work may still complete and cache its result. Mutation does not end an in-flight loading state.
- `clearCacheEntry` / `clearAllCache` remove data and invalidate pending work so pre-clear requests cannot repopulate the cache. Ordinary Futures may continue running.
- `cacheTime` controls retention; `staleTime` controls revalidation. A pure cache hit skips success/finally callbacks. Failed background revalidation retains cached data.
- Storage is process-local, with a default 256-entry LRU limit. Persistence, restored parameters, and custom storage are not provided.

## Retry

`retryCount` is the maximum number of retries after the first attempt. The default retries selected Dio network/timeout errors and 5xx responses. Other errors require an explicit predicate:

```dart
final request = useRequestFn(
  () => repository.load(),
  options: UseRequestOptions(
    retryCount: 2,
    shouldRetry: (error) => error is TemporaryFailure,
  ),
);
```

Dio cancellation and `RetryCancelledException` are never retried, even if the custom predicate returns true. Shared retries continue while another consumer remains; the last departure stops backoff and future attempts, but cannot interrupt an ordinary Future already executing.

## Cancellation

| Path | UI/callbacks | Transport and `runAsync` |
| --- | --- | --- |
| Ordinary Future cancelled/disposed/superseded | Old completion ignored | Future continues; its original result/error eventually settles the wait, not necessarily immediately |
| `HttpRequestConfig` and Dio service using the injected token | Cancellation ignored | Token can interrupt Dio; wait receives cancellation error |
| One shared-pending consumer leaves | Its result ignored | Other consumers retain work; library-owned transport cancels only when the last leaves |
| Cache cleared | Data and relevant loading cleared | Old cache writes invalidated; ordinary Futures cannot be forcibly stopped |

`cancel()` also cancels debounce/throttle queues and stops receiving cache events until the next execution. `pausePolling()` pauses polling and cancels current work. Caller-owned external tokens can cancel a shared transport for every consumer; see [Dio integration](dio-integration.en.md).
