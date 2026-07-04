> 维护约定：自本版本起，更新日志同时提供简体中文与英文，便于 pub.dev 直接阅读。

> Maintenance note: Starting from this version, the changelog is maintained in both Simplified Chinese and English for better readability on pub.dev.

## 0.6.0

- 新增: 闭包驱动版入口 `useRequestFn`（closure mode）。service 为零参闭包，请求条件一律从闭包捕获的外部状态读取，`refreshDeps` 仅作为触发器；适用于搜索、筛选、Provider/Riverpod 派生条件等“依赖变化需带最新参数重新请求”的场景，不受 `refreshDeps` 复用上一次参数语义的影响。
- 文档: README 新增《参数从哪来——闭包模式、参数模式与 refreshDeps》一章，系统说明两种参数来源模式的选型、`refresh` / `refreshDeps` 语义差异与组合陷阱，附 CRUD、分页、无限加载、搜索 + 筛选四个完整管理后台示例；同步补充目录导航。
- 测试: 新增 `useRequestFn` 闭包时效性回归测试，覆盖 `refreshDeps` 变化后闭包必须读到最新筛选值，以及 `refresh()` 必须走最新一帧闭包（而非挂载时的旧闭包）。

- Added: `useRequestFn` is a closure-mode entrypoint where the service is a zero-argument closure and request conditions are always read from captured external state. `refreshDeps` acts only as a trigger, making it suitable for search, filters, and Provider/Riverpod-derived conditions that must re-request with the latest inputs instead of reusing previous params.
- Docs: Added a new README section, "Where do params come from? Closure mode, params mode, and refreshDeps", covering when to choose each param source model, the semantic differences between `refresh` and `refreshDeps`, common composition pitfalls, and four complete admin-style examples for CRUD, pagination, infinite loading, and search plus filters. The document navigation was also updated.
- Tests: Added regression tests for `useRequestFn` closure freshness, covering both that the closure reads the latest filter value after `refreshDeps` changes, and that `refresh()` uses the most recent frame's closure rather than the one captured at mount.

## 0.5.1

- 修复: 相同 `cacheKey` 的并发请求命中 pending cache 时不再取消正在复用的 Dio 请求。
- 修复: `HttpRequestConfig.cancelToken` 与 `UseRequestOptions.cancelToken` 统一关联到内部令牌，外部令牌和 `result.cancel()` 均可中断底层请求，内部取消不会反向废弃外部令牌。
- 修复: Riverpod `updateOptions()` 动态启用、替换或关闭 `refreshOnFocus`、`refreshOnReconnect`、`reconnectStream`、`pollingWhenHidden` 时会同步更新监听器。
- 修复: Hook 版 `isPolling` 改为响应式状态，调用 `pausePolling()` / `resumePolling()` 后立即更新；控制器卸载时静默释放，避免对已销毁 Widget 请求重建。
- 修复: `HttpRequestConfig` 值语义纳入 Dio `Options` 中会影响真实请求的字段，避免 headers、responseType、编码器等变化被误判为相同请求。
- 测试: 增加 pending 去重与取消、双向令牌关联、动态聚焦 / 重连监听、轮询响应式状态和 `Options` 值语义的组合测试。

- Fixed: Concurrent requests with the same `cacheKey` no longer cancel an in-flight Dio request when they hit the pending cache.
- Fixed: `HttpRequestConfig.cancelToken` and `UseRequestOptions.cancelToken` are now linked to the same internal token chain, so both the external token and `result.cancel()` can abort the underlying request, while internal cancellation does not invalidate the external token in reverse.
- Fixed: Riverpod `updateOptions()` now updates listeners correctly when `refreshOnFocus`, `refreshOnReconnect`, `reconnectStream`, or `pollingWhenHidden` are enabled, replaced, or disabled at runtime.
- Fixed: In the Hook implementation, `isPolling` is now reactive and updates immediately after `pausePolling()` or `resumePolling()`. Controllers are also released silently on dispose to avoid scheduling rebuilds for destroyed widgets.
- Fixed: The `HttpRequestConfig` value semantics now include Dio `Options` fields that affect the real request, preventing changes such as headers, `responseType`, or encoders from being treated as the same request by mistake.
- Tests: Added combined coverage for pending deduplication and cancellation, bidirectional token wiring, dynamic focus and reconnect listeners, reactive polling state, and `Options` value semantics.

## 0.5.0

> 本版本包含若干破坏性变更（BREAKING CHANGE），详见下方标注项；其余为向后兼容的缺陷修复。

> This release contains several BREAKING CHANGEs, marked inline below. The remaining fixes are backward-compatible bug fixes.

- 修复（P0）: 自动请求 effect 不再依赖 `defaultParams`，消除内联构造未重写 `==` 的参数对象（如 `HttpRequestConfig`）导致的“请求 -> 重建 -> 再请求”无限循环；参数变化触发刷新请改用 `refreshDeps`。
  BREAKING CHANGE: 若此前依赖“`defaultParams` 每次变化都会重新请求”这一错误行为，需改用 `refreshDeps: [yourParam]` 显式声明。
- 修复（P0）: 缓存去重的 pending 清理改用 `then + onError`，消除失败请求触发的 Zone 未处理异步异常（此前会向全局错误处理器上报假崩溃）。
- 新增（P0）: `HttpRequestConfig` 增加 `cancelToken` 字段；useRequest 会自动注入内部令牌，`cancel()` 现在能真正中断底层 Dio 请求（用户显式设置的令牌优先）。
- 修复（P0）: Riverpod `UseRequestBuilder` 的 options 更新现在正确传播，切换 `ready`、变更 `refreshDeps`、更新回调闭包均生效。
- 修复（P1）: `refreshDeps` 触发刷新时优先复用最近一次请求参数（对齐 ahooks `refresh` 语义），最近参数不可用时回退 `defaultParams`；Hook 版与 Riverpod 版行为统一。
- 修复（P1）: `refresh()` / `loadMore()` 在从未请求过时不再同步抛出 `StateError`，统一转为被吞掉的 `Future.error`。
- 修复（P1）: `cancel()` 现在同时取消排队中的防抖 / 节流调用。
- 修复（P1）: 请求失败不再清除仍在 `cacheTime` 有效期内的缓存条目（SWR 语义：后台再验证失败保留旧数据）。
  BREAKING CHANGE: 若此前依赖“请求失败即清缓存”这一行为强制下次拿到全新数据，需改为显式调用 `clearCacheEntry`。
- 修复（P1）: 轮询、聚焦刷新、重连刷新的回调改经 ref 调用最新一帧实现，消除 stale closure（此前 `onSuccess` / `dataMerger` 等未列入 effect keys 的配置变化后轮询仍用旧值）。
- 修复（P1）: `Throttler` 的 maxWait 立即执行分支补齐清理，消除事件循环繁忙时排队 trailing 被双重执行的问题；排队等待者共享本次执行结果。
- 修复（P1）: `TData` 可空时 service 合法返回 `null` 现在会清空 `data`，不再被旧数据吞掉。
- 修复（P2）: fresh 缓存命中时补发观察者 `onFinally` 事件，保证 `onRequest` / `onFinally` 打点配对（用户回调仍与 ahooks 一致不触发）。
- 新增（P2）: `HttpRequestConfig` 实现值语义 `==` / `hashCode`（回调、`extra`、`cancelToken` 不参与比较），修复 `keepPreviousData=false` 下相同参数重复请求导致的数据闪空。
  BREAKING CHANGE: 若此前将 `HttpRequestConfig` 实例放入 `Set` / 用作 `Map` key 并依赖对象恒等语义，比较结果会变化。
- 重构（P2）: Web 可见性监听从已弃用的 `dart:html` 迁移到 `package:web` + `dart:js_interop`，兼容 WASM 编译目标（新增依赖 `web: ^1.1.1`）。
- 变更（P2）: `UseRequestBuilder` 改为普通 `StatefulWidget`，不再要求包裹 `ProviderScope`；`UseRequestMixin.initUseRequest` 的 `ref` 参数从未被使用，标记为弃用并改为可选。
- 变更（P2）: Hook 版 `isPolling` 改为直接派生自轮询控制器状态，移除可能脱节的影子布尔。
- 文档（P2）: `fetchKey` 文档明确与 ahooks v2 的语义差异（单份状态归属最新 key，非最新 key 的结果被丢弃）。
- 测试: 新增 P0 回归测试 8 条、P1 / P2 回归测试 11 条。

- Fixed (P0): The auto-request effect no longer depends on `defaultParams`, removing the infinite "request -> rebuild -> request again" loop caused by inline param objects without custom `==` such as `HttpRequestConfig`. Use `refreshDeps` when param changes should trigger refreshes.
  BREAKING CHANGE: If your code relied on the previous incorrect behavior where changes to `defaultParams` re-triggered requests automatically, switch to an explicit `refreshDeps: [yourParam]`.
- Fixed (P0): Pending-cache cleanup now uses `then + onError`, preventing failed requests from producing unhandled async exceptions in the Zone that previously surfaced as false crashes to global error handlers.
- Added (P0): `HttpRequestConfig` now supports `cancelToken`. useRequest injects its internal token automatically, and `cancel()` can now abort the underlying Dio request for real, while still respecting user-provided tokens first.
- Fixed (P0): Option updates now propagate correctly through Riverpod `UseRequestBuilder`, so toggling `ready`, changing `refreshDeps`, and replacing callback closures all take effect.
- Fixed (P1): Refreshes triggered by `refreshDeps` now prefer the most recent request params to match ahooks `refresh` semantics, and fall back to `defaultParams` only when the latest params are unavailable. Hook and Riverpod behavior is now aligned.
- Fixed (P1): `refresh()` and `loadMore()` no longer throw synchronous `StateError`s when nothing has ever run. They now consistently surface as swallowed `Future.error`s.
- Fixed (P1): `cancel()` now also cancels queued debounce and throttle executions.
- Fixed (P1): Failed requests no longer clear cache entries that are still valid under `cacheTime`, following SWR semantics where stale data is retained if background revalidation fails.
  BREAKING CHANGE: If your code relied on "failure clears cache immediately" to force the next read to fetch fresh data, call `clearCacheEntry` explicitly instead.
- Fixed (P1): Polling, focus refresh, and reconnect refresh callbacks now invoke the latest frame via refs, removing stale-closure issues where polling could keep using outdated values after changes to options like `onSuccess` or `dataMerger` that were not part of effect keys.
- Fixed (P1): The immediate-execution branch of `Throttler.maxWait` now performs full cleanup, preventing queued trailing calls from running twice under a busy event loop. Waiting callers now share the same execution result.
- Fixed (P1): When `TData` is nullable and the service legitimately returns `null`, `data` is now cleared instead of leaving stale data visible.
- Fixed (P2): Observer `onFinally` is now emitted for fresh-cache hits as well, so `onRequest` and `onFinally` telemetry stays paired. User callbacks still remain consistent with ahooks and are not fired for cache hits.
- Added (P2): `HttpRequestConfig` now implements value-based `==` and `hashCode` excluding callbacks, `extra`, and `cancelToken`, fixing data flicker when identical params are requested repeatedly with `keepPreviousData=false`.
  BREAKING CHANGE: If you stored `HttpRequestConfig` instances in a `Set` or used them as `Map` keys while relying on identity semantics, comparisons will now behave differently.
- Refactor (P2): Web visibility handling moved from deprecated `dart:html` to `package:web` plus `dart:js_interop`, making it compatible with WASM compilation targets (new dependency: `web: ^1.1.1`).
- Changed (P2): `UseRequestBuilder` is now a regular `StatefulWidget` and no longer requires wrapping in `ProviderScope`. The unused `ref` argument of `UseRequestMixin.initUseRequest` is now deprecated and optional.
- Changed (P2): The Hook implementation of `isPolling` now derives directly from the polling controller state, removing the previous shadow boolean that could drift out of sync.
- Docs (P2): Clarified in the `fetchKey` docs how this library differs from ahooks v2: state belongs to the latest key only, and results from stale keys are discarded.
- Tests: Added 8 new P0 regression tests and 11 new P1 / P2 regression tests.

## 0.3.5

- 示例：新增 `Options` 与频率控制进阶示例模块，完善演示入口与交互链路。
- 修复：修正示例页在不同宽度下的多处布局溢出问题（标题区、操作区、下拉框区域）。
- 测试：增强示例 UI 交互测试稳定性，补齐可见性处理与网络 Mock，确保关键交互可稳定回归。
- 文档：补充 GitHub Pages 自动部署流程与 LLM Agent 接入说明，支持接入方项目最小模块试点改造。

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
