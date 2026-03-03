> 维护约定：自本版本起，更新日志统一使用简体中文。

## 0.3.4

- 修复：解决轮询在 `pausePollingOnError` 后进入暂停态时无法被 `pollingRetryInterval` 正确恢复的问题（Hook 与 Riverpod 两条路径均已修复）。
- 测试：新增 `UseRequestOptions` 行为覆盖测试，补齐 `pollingWhenHidden`、`pausePollingOnError`、`pollingRetryInterval`、`debounceLeading/trailing/maxWait`、`throttleLeading/trailing`、`retryExponential`、`onRetryAttempt`、`connectTimeout/receiveTimeout/sendTimeout`、`loadingDelay` 等关键配置项回归。
- 文档：README 顶部补充 GitHub 仓库地址，便于从 pub.dev 直接跳转源码与 Issue。

## 0.3.3

- 修复：为 `UseRequestObserver` 全部回调增加安全隔离，观察者异常不再影响请求主流程。
- 修复：`mutate((_) => null)` 时同步清理对应 `RequestCache`，避免状态与缓存不一致。
- 修复：`UseRequestBuilder.didUpdateWidget` 改为语义比较 options，避免等价配置的无效更新。
- 修复：`RequestCache.get<T>` 在类型不匹配时不再刷新 LRU 顺序。
- 新增：`PaginationHelpers.pageParams` 支持 `shouldReset`，可在筛选/刷新场景重置页码计数。
- 示例：重构 `example/lib/main.dart` 为由易到难的渐进式教学示例（GitHub API、Record 解构、hooks 数据流转）。
- 测试：新增并补强回归测试，覆盖 observer 异常、`onBefore` 异常、`mutate(null)` 缓存同步、LRU 顺序与 options 等价判定。

## 0.3.2

- 新增：`UseRequestNotifier` 支持 `updateOptions()`，可在运行时更新防抖/节流/轮询间隔等参数，不销毁 Notifier、不丢失请求状态。
- 新增：`UseRequestBuilder` 在仅 options 变化时调用 `updateOptions()`，不再销毁重建，保留已有数据与轮询状态。
- 新增：`UseRequestMixin` 同步暴露 `updateOptions()` 便捷方法。
- 测试：新增 `updateOptions` 状态保持测试。

## 0.3.1

- **BREAKING**: `UseRequestOptions` 新增 `==` / `hashCode`（基于标量配置字段），解决 `didUpdateWidget` 中 inline 构造导致无限重建。
- **BREAKING**: `mutate()` 现在同步写入全局 `RequestCache`，共享同一 `cacheKey` 的组件可见乐观更新。
- Fix: `RequestCache.get<T>` 新增类型安全守卫，类型不匹配时返回 null 而非运行时崩溃。
- Fix: Hook 版 `ready` 从 false→true 时，若有待执行的 `refreshDeps` 回放，跳过自动请求避免同帧重复触发。
- Feat: 新增 `initialData` 选项，支持 SSR/预加载数据注入，首帧即可渲染。
- Feat: 新增 `keepPreviousData` 选项，参数变化时保留旧数据直到新数据到达，避免 UI 闪白。
- Feat: 新增 `UseRequestObserver` 全局观察者机制，支持日志记录、请求监控、调试。
- Feat: `CacheCoordinator` 无 `staleTime` 时始终后台刷新（SWR 语义完善）。
- Test: 新增 32 个测试用例，覆盖缓存 LRU/类型安全、Options 等价性、Observer、状态机流转、错误路径、分页轮询。

## 0.3.0

- Fix: `RequestCache` 新增 LRU 淘汰策略（默认最大 256 条），防止长时间运行导致内存无限增长（Bug 10）。
- Fix: `CacheCoordinator` 修正 SWR 语义——只配 `cacheTime` 不配 `staleTime` 时，缓存始终后台刷新（Bug 13）。
- Fix: 轮询与分页（`loadMoreParams`）同时使用时，轮询优先使用 `defaultParams` 刷新首页，避免覆盖已累积的分页数据（Bug 15）。
- Feat: `RequestCache.removeWhere()` 支持按模式批量清除缓存（如 `key.startsWith('user-')`）。
- Fix: `UseRequestState.copyWith` 新增 `clearParams`/`clearHasMore` 标志位（Bug 1）。
- Fix: `defaultParams` 仅在首次 build 时初始化，不再覆盖用户手动参数（Bug 2）。
- Fix: `PaginationHelpers.pageParams` 通过内部计数器正确追踪页码（Bug 3）。
- Fix: `UseRequestMixin.initUseRequest` 新增 `onStateChange` 回调以触发宿主 Widget 重建（Bug 4）。
- Fix: `loadMore()` 在 `hasMore == false` 时拒绝发起新请求（Bug 5）。
- Fix: 所有生命周期回调（onSuccess/onError/onFinally）包裹 try-catch，异常不再中断请求流程（Bug 6）。
- Fix: `bindPendingRequest` 补充 onSuccess/onError/onFinally 回调（Bug 7）。
- Fix: `UseRequestBuilder` 引入 `serviceKey` 机制，避免闭包引用变化导致无限重建（Bug 8）。
- Fix: `refreshAsync` 安全类型检查，非空 TParams 场景下回退到 `defaultParams`（Bug 9）。
- Fix: `cancel()` 取消所有 key 的进行中请求，而非仅最后一个（Bug 11）。
- Fix: `AppFocusManager` 不再将 `inactive` 状态视为 blur（Bug 12）。
- Docs: `onBefore` 在 `loadMore` 场景下不触发的行为已补充文档说明（Bug 14）。

## 0.0.13

- Fix: clear both `loading` and `loadingMore` on cancel, and make Hook/Riverpod consistently support no-params requests across auto-run, `refreshDeps`, polling, focus refresh, and reconnect refresh.
- Fix: remove duplicate Riverpod auto requests when `refreshDeps` and `ready` replay overlap, and let `UseRequestBuilder` / `UseRequestMixin` render notifier state on the first frame instead of a synthetic empty state.
- Fix: harden scheduler and cache utilities, including correct `Debouncer.maxWait`, non-cancelling leading debounce futures, correct `Throttler` behavior for `leading:false`, cancellable retry backoff, pending-cache overwrite safety, and `UseRequestOptions.copyWith()` explicit null clearing.
- Test: add Hook, Riverpod, debounce, throttle, retry, cache, and options contract tests for the above edge cases.

## 0.0.12

- Fix: hydrate fresh cache into Hook and Riverpod state on the first frame, so pages that remount can render cached data immediately instead of flashing default values before auto requests run.

## 0.0.11

- Fix: pending cache subscribers now receive the in-flight result in both Hook and Riverpod implementations, instead of reusing the Future without updating local state.

## 0.0.10

- Fix: `refreshDeps` now triggers auto refresh even when last/default params is `null` (no-params service), aligning with ahooks.

## 0.0.9

- Fix: refreshDeps change detection now survives list reuse/mutation by hashing deps and copying snapshots.
- Fix: refreshDeps changes while `ready=false` are replayed once `ready=true` (Hook + Riverpod).
- Fix: Riverpod refreshDeps initial trigger actually fires (no pre-seeded deps).

## 0.0.8

- Fix: allow `refresh()` to reuse a previous `null` params entry instead of throwing (both Hook and Riverpod).

## 0.0.7

- Example: add an inline Quick Start snippet in `example/lib/main.dart` so pub.dev can render a meaningful Example tab.

## 0.0.6

- Align docs with implementation: make `UseRequestOptions` timeouts effective when `TParams=HttpRequestConfig`.
- Add `uploadFile` / `downloadFile` aliases to `DioHttpAdapter` to match README examples.
- Unify `ready` semantics between Hook and Riverpod (ready=false gates auto/polling, manual run still works).
- Fix example widget test to reflect the current demo app.

## 0.0.5

- Optimize auto-request logic: allow auto-trigger when `defaultParams` is null (provided `manual` is false).
- Docs: add minimalist usage example (Zero Configuration).

## 0.0.4

- Reformat source to satisfy `dart format` and static analysis.
- Upgrade dependencies to latest supported versions (`flutter_hooks`, `flutter_riverpod`), keeping Riverpod v3 compatibility via legacy API.

## 0.0.2

- Implement active-key single-state semantics for `fetchKey` (stale key results no longer update state).
- Fix `Debouncer` so new calls cancel previous pending futures instead of leaving them hanging.
- Align Hook and Riverpod behaviors (retry callbacks, polling control, cancel semantics, cache consistency).
- Improve polling lifecycle: ready/manual gating, visibility pause/resume on Web, and optional `pollingRetryInterval` auto-restore.
- Rework `DioHttpAdapter.request` to support per-request timeouts and merged headers/query.
- Enhance example demos (interactive polling controls, sidebar scroll fix, JSONPlaceholder PUT/PATCH safe id).
- Docs/metadata: add bilingual README, pub badges, topics, and Flutter CI workflow.

## 0.0.1

- Initial release.
