English | [简体中文](README.md)

[![GitHub](https://img.shields.io/badge/GitHub-use__request__dio-181717?logo=github)](https://github.com/wildcatDownstairs/use_request_dio)
[![pub package](https://img.shields.io/pub/v/use_request.svg)](https://pub.dev/packages/use_request)
[![likes](https://img.shields.io/pub/likes/use_request)](https://pub.dev/packages/use_request/score)
[![pub points](https://img.shields.io/pub/points/use_request)](https://pub.dev/packages/use_request/score)
[![popularity](https://img.shields.io/pub/popularity/use_request)](https://pub.dev/packages/use_request/score)
[![Flutter CI](https://github.com/wildcatDownstairs/use_request_dio/actions/workflows/dart.yml/badge.svg)](https://github.com/wildcatDownstairs/use_request_dio/actions/workflows/dart.yml)
[![Web Demo](https://img.shields.io/badge/Web%20Demo-GitHub%20Pages-0ea5a4)](https://wildcatdownstairs.github.io/use_request_dio/)

# useRequest

> A Flutter async request management library inspired by ahooks `useRequest`.  
> It supports auto/manual requests, polling, debounce/throttle, refresh-on-focus,
> retry with backoff, delayed loading, cancellation, local mutation, and more.

- Hook entry: `useRequest` (params mode) / `useRequestFn` (closure mode) (`lib/src/use_request.dart`)
- Riverpod entry: `UseRequestNotifier` / `createUseRequestProvider` / `UseRequestBuilder`
  (`lib/src/use_request_riverpod.dart`)
- HTTP adapter: `DioHttpAdapter` (`lib/src/utils/dio_adapter.dart`)
- Types/config: `UseRequestOptions`, `UseRequestResult`, `UseRequestState`
  (`lib/src/types.dart`)

> **⚠️ Must read: [Where do params come from? Closure mode, params mode, and refreshDeps](#where-do-params-come-from-closure-mode-params-mode-and-refreshdeps)**
> `refreshDeps` only decides *when* to re-request, not *what params* to request with.
> In Hook contexts, for filter/search cases where "the dependency IS the param",
> use closure mode `useRequestFn`. On pure Riverpod Provider / Builder paths, use
> `refreshDepsAction` or notifier `refreshDeps(..., action: ...)` to pass the new
> params explicitly; otherwise you hit the classic "tab changed but request params didn't".

## Table of Contents

- [Demo](#demo)
- [For LLM Agents](#for-llm-agents)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Where do params come from? Closure mode, params mode, and refreshDeps](#where-do-params-come-from-closure-mode-params-mode-and-refreshdeps)
- [HTTP Semantic Layer (`DioHttpAdapter`)](#http-semantic-layer-diohttpadapter)
- [API Reference](#api-reference)
- [Best Practices](#best-practices)
- [Flutter Web Demo & Renderer](#flutter-web-demo--renderer)
- [FAQ](#faq)
- [Source Map](#source-map)

---

## Demo
- Live demo (GitHub Pages): https://wildcatdownstairs.github.io/use_request_dio/
- Install deps in example: `cd example && flutter pub get`
- Run on your target platform:
  - Web (Chrome): `flutter run -d chrome`
  - macOS desktop: `flutter run -d macos`
  - iOS simulator: `flutter run -d ios` (requires Xcode)
  - Android: `flutter run -d android` (emulator/device)
- Demo home: `example/lib/main.dart`
- Legacy demo hub: `example/lib/demo/use_request_demo_page.dart`

---

## For LLM Agents

### For humans (copy and send to your agent)

After you send this prompt, the agent will:
1. install/configure `use_request` in your current project;
2. pick and migrate one smallest network module as a PoC;
3. report what changed and whether to expand migration.

```text
Please follow this guide in my current project (not in use_request package repo), install use_request, and migrate one smallest network module first:
https://raw.githubusercontent.com/wildcatDownstairs/use_request_dio/main/doc/llm-agent-quickstart.zh-CN.md
```

### For LLM agents (fetch and execute)

```bash
curl -fsSL https://raw.githubusercontent.com/wildcatDownstairs/use_request_dio/main/doc/llm-agent-quickstart.zh-CN.md
```

---

## Features

### Core
- Auto/manual/ready: control initial request by `manual` + `defaultParams`; when
  `ready=false`, auto request & polling are deferred (manual `run/runAsync` still works).
- Polling: periodic fetch via `pollingInterval`, with start/stop controls
  (Riverpod exposes methods).
- Polling visibility: when `pollingWhenHidden=false`, polling pauses on
  focus-loss/background and resumes on foreground.
- Polling error policy: `pausePollingOnError` pauses polling on error; optional
  `pollingRetryInterval` auto-resumes after a delay.
- Debounce / throttle: `debounceInterval` or `throttleInterval` (mutually
  exclusive), with leading/trailing and debounce `maxWait`.
- Refresh on focus: `refreshOnFocus` refreshes when app regains focus.
- Dependency refresh: `refreshDeps` / `refreshDepsAction`.
  Hook auto-watches deps; Riverpod also supports deps refresh via notifier method.
- Cache & concurrency: `cacheKey` + `cacheTime`/`staleTime` cache results.
  `fetchKey` isolates cancel/requestCount per key; **state is single-active-key**
  (only the latest key updates UI).
- Load more: `loadMoreParams` + `dataMerger` + `hasMore`, plus `loadMore` /
  `loadingMore`.
- Retry: `retryCount` + `retryInterval`, optional exponential backoff.
- Loading delay: `loadingDelay` avoids flicker for fast requests.
- Cancellation: `cancel()` + custom `CancelToken`.
- Local mutation: `mutate()` updates data without refetch.
- Lifecycle callbacks: `onBefore`, `onSuccess`, `onError`, `onFinally`.

### Advanced
- **HTTP semantic layer**: `DioHttpAdapter` provides typed GET/POST/PUT/DELETE/PATCH.
- **Per-request timeouts**: `connectTimeout` / `receiveTimeout` / `sendTimeout`.
- **Upload / download**: file transfer with progress callbacks.
- **Retry callback**: `onRetryAttempt` to observe retry attempts.

### Closure mode (v0.6.0)
- **`useRequestFn`**: the service is a zero-arg closure; request conditions are read
  straight from captured external state, and `refreshDeps` only acts as a trigger.
  This sidesteps the "dependency changed but old params reused" trap. See
  [Where do params come from?](#where-do-params-come-from-closure-mode-params-mode-and-refreshdeps).

---

## Installation

Add dependencies in `pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.9.0
  flutter_hooks: ^0.21.3+1
  flutter_riverpod: ^3.0.3
  # Optional: only if you use HookConsumerWidget / hooks_riverpod in UI
  hooks_riverpod: ^3.0.3
```

Import from the unified entry:

```dart
import 'package:use_request/use_request.dart';
```

If you use Riverpod providers (`createUseRequestProvider`), wrap your app with
`ProviderScope`. `UseRequestBuilder` manages its own notifier internally and does
not depend on `ProviderScope`:

```dart
void main() {
  runApp(const ProviderScope(child: MyApp()));
}
```

---

## Quick Start

### Hook (`useRequest`)

Best for local state in `HookWidget` / `HookConsumerWidget`.

```dart
class UserParams { final int id; UserParams(this.id); }
Future<User> fetchUser(UserParams p) async {
  final res = await Dio().get('https://jsonplaceholder.typicode.com/users/${p.id}');
  return User.fromJson(res.data);
}

class UserPage extends HookWidget {
  const UserPage({super.key});
  @override
  Widget build(BuildContext context) {
    final result = useRequest<User, UserParams>(
      fetchUser,
      options: const UseRequestOptions(
        manual: false,
        defaultParams: UserParams(1),
        loadingDelay: Duration(milliseconds: 200),
        retryCount: 2,
        retryInterval: Duration(seconds: 1),
        refreshOnFocus: true,
      ),
    );

    if (result.loading) return const Center(child: CircularProgressIndicator());
    if (result.error != null) return Text('Error: ${result.error}');
    return Column(
      children: [
        Text(result.data?.name ?? ''),
        ElevatedButton(onPressed: () => result.run(UserParams(2)), child: const Text('Run again')),
      ],
    );
  }
}
```

### Hook — closure mode (`useRequestFn`)

Best when the request runs on mount without external params, or when the request
conditions live in external state (`useState` / Provider / Riverpod) and you want
a re-request with the *latest* conditions whenever that state changes.

```dart
Future<List<User>> fetchUsers() async => ...;

final request = useRequestFn(fetchUsers);   // zero-config auto request, no params to handle
```

```dart
final keyword = useState('');

final request = useRequestFn(
  () => searchUsers(keyword.value),   // closure reads the latest keyword
  options: UseRequestOptions(refreshDeps: [keyword.value]),
);
```

How the two modes differ and how `refreshDeps` really behaves is covered in
[Where do params come from?](#where-do-params-come-from-closure-mode-params-mode-and-refreshdeps)
— the most trap-prone part of the library.

### Builder (`UseRequestBuilder`)

No hooks needed; use a builder to access state/actions.

```dart
UseRequestBuilder<User, UserParams>(
  service: fetchUser,
  options: const UseRequestOptions(
    manual: false,
    defaultParams: UserParams(1),
  ),
  builder: (context, state, notifier) {
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.error != null) return Center(child: Text('Error: ${state.error}'));
    return Column(
      children: [
        Text(state.data?.name ?? ''),
        ElevatedButton(
          onPressed: () => notifier.run(UserParams(2)),
          child: const Text('Fetch another user'),
        ),
      ],
    );
  },
);
```

### Riverpod Provider

Great for shared request state or advanced polling control.

```dart
final userRequestProvider = createUseRequestProvider<User, UserParams>(
  service: fetchUser,
  options: const UseRequestOptions(manual: true),
);

class RiverpodProviderExample extends ConsumerWidget {
  const RiverpodProviderExample({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userRequestProvider);
    final notifier = ref.read(userRequestProvider.notifier);

    return Column(
      children: [
        if (state.loading) const CircularProgressIndicator(),
        if (state.error != null) Text('Error: ${state.error}'),
        if (state.data != null) Text('Name: ${state.data!.name}') else const Text('Empty'),
        Row(
          children: [
            ElevatedButton(onPressed: () => notifier.run(UserParams(1)), child: const Text('Run')),
            ElevatedButton(onPressed: notifier.refresh, child: const Text('Refresh')),
          ],
        ),
      ],
    );
  }
}
```

---

## Where do params come from? Closure mode, params mode, and refreshDeps

> This is the most trap-prone part of the library. If you read one section, read this.
>
> One line: **refreshDeps only decides *when* to re-request, never *what params* to request with.**
> Params come either from a closure (recommended for auto-refresh) or from `run(params)`
> (recommended for manual actions).

### Cheat sheet

| | Closure mode `useRequestFn` | Params mode `useRequest` + `run(params)` |
|---|---|---|
| Service signature | `() => api(query)` zero-arg closure | `(params) => api(params)` explicit param |
| Param source | Captured external state | Passed explicitly on each `run(params)` |
| Auto-refresh on dep change | ✅ `refreshDeps` works directly | ⚠️ Needs `refreshDepsAction`, else reuses old params |
| Pagination `loadMore` | ❌ Put page into external state | ✅ `loadMoreParams` derives next page |
| Typical scenarios | Search input, filter tabs, Provider/Riverpod-derived conditions in a Hook context | Click-to-search, form submit, manual refresh |
| Availability | `HookWidget` / `HookConsumerWidget` | Hook / Builder / Riverpod Provider — all |

### Why two entries instead of one `useRequest(fn)`?

This is not API inflation for its own sake. In Dart, these two semantics should
be separated.

If you do not care about JS/TS history, keep just this one sentence:

- `useRequest`: the library passes `params` into the service when you call `run(params)`
- `useRequestFn`: the library passes no params; the service reads external state by itself

- Params mode needs a service shaped like `Future<T> Function(TParams)`.
- Closure mode needs a service shaped like `Future<T> Function()`.
- If one `useRequest(fn)` tried to accept both, the public signature would have
  to be widened to something like `Function` or `Object?`, then split at runtime.

You can also read it as two very different call flows:

```dart
// Params mode: the library passes the params in
final request = useRequest(fetchUser);
request.run(123); // roughly: fetchUser(123)

// Closure mode: the library only "runs this function again"
final request = useRequestFn(() => fetchUser(userId.value));
request.refresh(); // roughly: (() => fetchUser(userId.value))()
```

For beginners, the key difference is not the terms "function" and "closure". It
is simply this:

- **Params mode**: request params live in `run(...)`
- **Closure mode**: request params live inside `() => ...`

That causes two problems:

- **It weakens the static type relationship**. In `useRequest<TData, TParams>`,
  `params`, `defaultParams`, `cacheKey`, `loadMoreParams`, and
  `onSuccess(data, params)` all line up around the same `TParams`. A wide
  `Function`-based API would dilute that contract.
- **Runtime dispatch is a poor foundation for a public Dart API**. In Flutter
  release/AOT, `dart:mirrors` is unavailable. Even aside from reflection, named
  functions, anonymous functions, and closures that capture external state are
  all just callable objects at runtime; the API should not rely on guessing
  semantics from that.

So the split is explicit:

- `useRequest`: params come from `run(params)`.
- `useRequestFn`: params come from captured external state.

That keeps the semantics readable and preserves type checking.

### Closure mode

```dart
final keyword = useState('');
final status = useState(0);

final result = useRequestFn(
  () => fetchOrderList(keyword: keyword.value, status: status.value),
  options: UseRequestOptions(
    refreshDeps: [keyword.value, status.value],
    debounceInterval: const Duration(milliseconds: 300),
  ),
);
```

**Mental model: the condition IS the state; when state changes, re-request; the
request always reads the latest state.**

- The service is a zero-arg closure, recreated on every widget rebuild, so the
  captured `keyword.value` / `status.value` are always the latest.
- `refreshDeps` does exactly one thing: when it changes, re-run the closure once.
  It passes nothing to the service.
- Because params never go through the `params` mechanism, the "refreshDeps reuses
  last params" semantics simply don't apply here — that's why it's robust.

Good for:

- **Search**: input changes auto-search (with `debounceInterval`)
- **Filter**: status tabs, dropdowns, date ranges auto-refresh the list
- **Provider / Riverpod (Hook context)**: inside `HookWidget` / `HookConsumerWidget`,
  put `context.watch` / `ref.watch` conditions into the closure

> **⚠️ Closure mode is a Hook entry**: `useRequestFn` only works inside a
> `HookWidget` / `HookConsumerWidget` (`hooks_riverpod`). On the pure Provider path
> (`createUseRequestProvider` / `UseRequestBuilder`), the service is fixed to
> `Service<TData, TParams>` at provider creation — there's no "rebuild the closure
> each frame" step. There, use the notifier's `refreshDeps(deps, action: ...)` to
> re-request with the latest params explicitly (equivalent to `refreshDepsAction`).

If you've written a React admin panel, this is exactly the model you know:

```tsx
// ahooks equivalent, same mental model
const { data } = useRequest(() => fetchOrderList(keyword, status), {
  refreshDeps: [keyword, status],
});
```

#### Pagination in closure mode

`loadMoreParams` is meaningless in closure mode (params is always null). Put the
page into external state too:

```dart
final page = useState(1);

final result = useRequestFn(
  () => fetchList(page: page.value, keyword: keyword.value),
  options: UseRequestOptions(refreshDeps: [page.value, keyword.value]),
);

onNextPage: () => page.value++;
onKeywordChange: (v) { keyword.value = v; page.value = 1; }  // reset to page 1
```

### Params mode

```dart
final result = useRequest<OrderDetail, int>(
  fetchOrderDetail,           // (orderId) => Future<OrderDetail>
  options: UseRequestOptions(manual: true),
);

onTap: (order) => result.run(order.id);
```

**Mental model: params are part of the action; each action passes them explicitly.**

- The service declares its param type; `run(params)` / `runAsync(params)` passes them.
- `refresh()` reuses the last `run` params verbatim — which is correct here: "run
  that same request again".
- Full type safety: `params`, `cacheKey`, `loadMoreParams`, `onSuccess` all get strong types.

Good for:

- **Click-to-search**: request only fires on button press, params from the form
- **Submit**: create/update/delete actions, `manual: true` + `run(payload)`
- **Manual refresh**: `refresh()` re-runs the last request

#### ⚠️ The params-mode + refreshDeps trap

**Don't do this** (the most common mistake):

```dart
// ❌ Wrong: assuming a refreshDeps change carries the new defaultParams
final params = useMemoized(() => buildParams(status), [status]);
final result = useRequest(
  fetchList,
  options: UseRequestOptions(
    defaultParams: params,
    refreshDeps: [status],   // status changes → refresh() → reuses the OLD params!
  ),
);
```

A `refreshDeps` change triggers `refresh()`, and `refresh()` is defined as "re-run
with the last request's params". The freshly computed `defaultParams` is only read
on the first auto request; the `refreshDeps` path never reads it again. So after
`status` switches, the request still carries the old status.

There is another, more subtle mistake: **the code looks like params mode, but the
actual request params come from a closure**.

```dart
// ❌ It runs, but run(params) is no longer the real request condition
final keyword = useState('banana');

final result = useRequest<List<User>, String>(
  (_) => searchUsers(keyword.value),
  options: UseRequestOptions(manual: true),
);

result.run('apple');
```

In this snippet:

- `run('apple')` stores `'apple'` as the request params
- the service actually reads `keyword.value`
- if `keyword.value == 'banana'`, the real request goes out with `banana`

So `onSuccess(data, params)` receives `'apple'`, while the server query condition
was really `banana`. The code does not crash, but the semantics are already off.
If you need this shape, either switch to true params mode
`useRequest(searchUsers)`, or switch fully to closure mode
`useRequestFn(() => searchUsers(keyword.value))`.

#### How to think about `defaultParams` and `refreshDepsAction`

These are not general switches for "make params follow state automatically". Both
have narrow, specific jobs.

- `defaultParams`: mainly for the **first auto request**. In a few framework-owned
  paths where a request param is needed but there is no usable "last params" yet,
  it also serves as a fallback, such as the first `refresh()` / first
  `refreshDeps` trigger before any valid params have been recorded.
- `refreshDepsAction`: not the default recommendation; it is the **explicit action
  hook for dependency changes while staying in params mode**. That exists because
  the default `refreshDeps` behavior is `refresh()`, and `refresh()` is defined
  as "run again with the last params".

For beginners, a simple way to remember them:

- `defaultParams`: "which params should the page use on its first auto request?"
- `refreshDepsAction`: "when deps change, do not use the default refresh behavior; use my explicit action instead"

In practice:

- Dependency changed and **request params should change too**: prefer `useRequestFn`
- Dependency changed but **params should stay the same**: plain `refreshDeps`
- Dependency changed and **you must stay in params mode and choose the new params
  yourself**: use `refreshDepsAction`

Typical `refreshDepsAction` cases:

- Pure Riverpod Provider / Builder paths, where there is no `useRequestFn`-style
  "rebuild the closure each frame" entry
- Cases where you intentionally keep params-mode features such as
  `loadMoreParams`, `cacheKey(params)`, or `run(payload)`

If you truly need params mode + dependency auto-refresh, use `refreshDepsAction` to
pass the new params explicitly:

```dart
// ✅ Correct: refreshDepsAction decides which params to use
final latestParams = useRef(params)..value = params;
final runRef = useRef<void Function(ListParams)?>(null);

final result = useRequest(
  fetchList,
  options: UseRequestOptions(
    defaultParams: params,
    refreshDeps: [status],
    refreshDepsAction: () => runRef.value?.call(latestParams.value),
  ),
);
runRef.value = result.run;
```

But generally — **when you reach for `refreshDepsAction`, first ask whether you
should be in closure mode**. That whole ref-relay block collapses to one line with
`useRequestFn`.

### refresh vs. refreshDeps

Both names contain "refresh" but mean very different things.

#### refresh(): same query, ask again

```dart
result.refresh();   // = run(last params)
```

`refresh()` takes no params and always reuses the last `run`/`runAsync` params. It
answers "**what is the server's data now, for the same conditions**", not "the
conditions changed, query with the new ones". This matches ahooks exactly.

#### refreshDeps: the outside world changed, ask again

Any item in `refreshDeps` changing → triggers `refresh()` by default.

Note the default action is `refresh()` — so it inherits the "reuse last params"
semantics. This is **not a bug**; the correct scenario is: **the dependency and the
request params are two different things**, the dependency changed but the params
did not, and you just want fresh data. For example:

- **Language switch**: query params don't change at all; what changes is the
  `Accept-Language` header — re-run to get localized text. Correct.
- **Re-login / tenant switch**: token/tenant lives in an interceptor, params unchanged.
- **Manual refresh signal**: an incrementing counter in refreshDeps, params unchanged.

When "the dependency IS the request param" (filter/search/paging), reusing old
params becomes a bug. Use closure mode there: params via closure, refreshDeps as
trigger only.

#### Decision rule

```
After a dependency changes, do the params need to change too?
├─ Yes → closure mode useRequestFn (or refreshDepsAction)
└─ No  (params unchanged, you just want fresh data) → params mode + refreshDeps directly
```

### Full examples (common admin-panel shapes)

The four demos below follow common enterprise admin-panel shapes; copy and adapt.

#### 1. CRUD (list + create + delete + edit)

```dart
class UserManagePage extends HookWidget {
  const UserManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    // List: closure mode, no param, loads on mount
    final list = useRequestFn(() => api.getUserList());

    // Create: params mode + manual, refresh the list on success
    final create = useRequest<void, CreateUserPayload>(
      api.createUser,
      options: UseRequestOptions(manual: true, onSuccess: (_, __) => list.refresh()),
    );

    // Delete: same
    final remove = useRequest<void, int>(
      api.deleteUser,
      options: UseRequestOptions(manual: true, onSuccess: (_, __) => list.refresh()),
    );

    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: list.refresh),
      ]),
      body: ListView(children: [
        for (final user in list.data ?? const <User>[])
          ListTile(
            title: Text(user.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => remove.run(user.id),
            ),
          ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final payload = await showCreateUserDialog(context);
          if (payload != null) create.run(payload);
        },
      ),
    );
  }
}
```

Key point: reads use closure mode; writes (create/update/delete) use params mode +
`manual: true`, and `list.refresh()` in `onSuccess` re-runs the original query —
exactly where "refresh reuses last params" belongs.

#### 2. Pagination (page-number table)

```dart
class OrderTablePage extends HookWidget {
  const OrderTablePage({super.key});

  @override
  Widget build(BuildContext context) {
    final page = useState(1);
    final pageSize = useState(20);
    final status = useState<int?>(null);

    final table = useRequestFn(
      () => api.getOrderPage(page: page.value, size: pageSize.value, status: status.value),
      options: UseRequestOptions(
        refreshDeps: [page.value, pageSize.value, status.value],
        keepPreviousData: true,   // keep old rows on screen while paging, avoid blank flash
      ),
    );

    return Column(children: [
      StatusFilterTabs(
        value: status.value,
        onChanged: (v) { status.value = v; page.value = 1; },  // reset to page 1 on filter change
      ),
      Expanded(child: OrderDataTable(rows: table.data?.records ?? const [], loading: table.loading)),
      PaginationBar(
        page: page.value,
        total: table.data?.total ?? 0,
        pageSize: pageSize.value,
        onPageChanged: (p) => page.value = p,
        onPageSizeChanged: (s) { pageSize.value = s; page.value = 1; },
      ),
    ]);
  }
}
```

Key point: page/pageSize/status are all external state, all in `refreshDeps`; any
change auto-refetches with the latest values. `keepPreviousData: true` smooths
paging. **Reset page to 1 on filter change** — that's a business rule, the library
won't guess it.

#### 3. Infinite loading (append on scroll-to-bottom)

Infinite loading needs "append each page to the existing list", which relies on
`loadMoreParams` + `dataMerger` — params-mode territory:

```dart
class MessageFeedPage extends HookWidget {
  const MessageFeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final result = useRequest<PageData<Message>, PageQuery>(
      api.getMessagePage,
      options: UseRequestOptions(
        defaultParams: const PageQuery(page: 1, size: 20),
        loadMoreParams: (last, _) => last.copyWith(page: last.page + 1),   // next page
        dataMerger: (prev, next) => PageData(
          records: [...?prev?.records, ...next.records],
          total: next.total,
        ),
        hasMore: (data) => data != null && data.records.length < (data.total ?? 0),
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final nearBottom = n.metrics.pixels >= n.metrics.maxScrollExtent - 200;
        if (nearBottom && result.hasMore == true && !result.loadingMore) {
          result.loadMore?.call();
        }
        return false;
      },
      child: ListView.builder(
        itemCount: (result.data?.records.length ?? 0) + 1,
        itemBuilder: (context, i) {
          final records = result.data?.records ?? const <Message>[];
          if (i == records.length) {
            return result.hasMore == true
                ? const Center(child: CircularProgressIndicator())
                : const Center(child: Text('No more'));
          }
          return MessageTile(records[i]);
        },
      ),
    );
  }
}
```

Key point: `loadMoreParams` only makes sense in params mode — it needs "the last
params" to derive the next page, so "reuse last params" is the essence of paging here.

#### 4. Search + filter + refreshDeps (the standard answer to the trap)

The most typical admin combo: search box + status tabs + paged table, all auto-refresh.

```dart
class CouponSearchPage extends HookWidget {
  const CouponSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final keyword = useState('');
    final statusTab = useState(0);          // 0=all 1=usable 2=pending...
    final page = useState(1);

    const statusMap = [-1, 1, 2, 3, 4];     // tab index → API orderStatus

    final list = useRequestFn(
      () => api.getCouponList(
        page: page.value,
        size: 10,
        orderStatus: statusMap[statusTab.value],
        keyword: keyword.value.isEmpty ? null : keyword.value,
      ),
      options: UseRequestOptions(
        refreshDeps: [keyword.value, statusTab.value, page.value],
        debounceInterval: const Duration(milliseconds: 300),
        keepPreviousData: true,
      ),
    );

    void resetToFirstPage() => page.value = 1;

    return Column(children: [
      SearchField(onChanged: (v) { keyword.value = v; resetToFirstPage(); }),
      StatusTabs(index: statusTab.value, onChanged: (i) { statusTab.value = i; resetToFirstPage(); }),
      Expanded(child: CouponListView(items: list.data?.records ?? const [], loading: list.loading)),
    ]);
  }
}
```

The wrong version once more (verbatim from a real project):

```dart
// ❌ Params mode + refreshDeps: tab changed, request params didn't
final params = useMemoized(
  () => CouponListParams(orderStatus: statusMap[statusTab.value]),
  [statusTab.value],
);
final list = useRequest(
  api.getCouponList,
  options: UseRequestOptions(
    defaultParams: params,          // used only on the first request
    refreshDeps: [statusTab.value], // afterwards refresh() reuses old params every time
  ),
);
```

Symptom: the tab highlight switches, the request even fires, but a packet capture
shows `orderStatus` is forever the previous tab's value. Fix: switch to closure mode
above, or params mode + `refreshDepsAction` (see "the trap" above).

---

## HTTP Semantic Layer (`DioHttpAdapter`)

```dart
final http = DioHttpAdapter(
  dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
);

final users = await http.get<List<User>>('/users');
final newUser = await http.post<User>('/users', data: {'name': 'John'});
await http.put('/users/1', data: {'name': 'Jane'});
await http.delete('/users/1');
await http.patch('/users/1', data: {'status': 'active'});
```

Integration with `useRequest`:

```dart
final http = DioHttpAdapter.withBaseUrl('https://jsonplaceholder.typicode.com');

// Build a Service where params is HttpRequestConfig (recommended).
final fetchUsers = createDioService<List<dynamic>>(
  http,
  transformer: (res) => (res.data as List<dynamic>?) ?? const [],
);

final result = useRequest<List<dynamic>, HttpRequestConfig>(
  fetchUsers,
  options: const UseRequestOptions(
    manual: true,
    // Optional: default timeouts (applied only when TParams=HttpRequestConfig)
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 15),
    sendTimeout: Duration(seconds: 15),
  ),
);

result.run(HttpRequestConfig.get('/users'));
```

---

## API Reference

### `UseRequestOptions<TData, TParams>`

```dart
const UseRequestOptions({
  // Basic
  bool manual = false,
  bool ready = true,
  TParams? defaultParams,

  // Dependency refresh
  List<Object?>? refreshDeps,
  VoidCallback? refreshDepsAction,

  // Polling
  Duration? pollingInterval,
  bool pollingWhenHidden = true,
  bool pausePollingOnError = false,
  Duration? pollingRetryInterval,

  // Debounce
  Duration? debounceInterval,
  bool debounceLeading = false,
  bool debounceTrailing = true,
  Duration? debounceMaxWait,

  // Throttle
  Duration? throttleInterval,
  bool throttleLeading = true,
  bool throttleTrailing = true,

  // Retry
  int? retryCount,
  Duration? retryInterval,
  bool retryExponential = true,
  OnRetryAttempt? onRetryAttempt,

  // Timeouts (v2.0, effective when TParams=HttpRequestConfig)
  Duration? connectTimeout,
  Duration? receiveTimeout,
  Duration? sendTimeout,

  // Loading & refresh
  Duration? loadingDelay,
  bool refreshOnFocus = false,
  bool refreshOnReconnect = false,
  Stream<bool>? reconnectStream,

  // Cache
  String Function(TParams params)? cacheKey,
  Duration? cacheTime,
  Duration? staleTime,

  // Concurrency & pagination
  String Function(TParams params)? fetchKey,
  TParams Function(TParams lastParams, TData? data)? loadMoreParams,
  TData Function(TData? previous, TData next)? dataMerger,
  bool Function(TData? data)? hasMore,

  // Cancel & callbacks
  CancelToken? cancelToken,
  OnBefore<TParams>? onBefore,
  OnSuccess<TData, TParams>? onSuccess,
  OnError<TParams>? onError,
  OnFinally<TData, TParams>? onFinally,
})
```

### `UseRequestResult<TData, TParams>`

- Fields: `loading`, `data`, `error`, `params`
- Methods: `run/runAsync`, `refresh/refreshAsync`, `mutate`, `cancel`,
  `loadMore/loadMoreAsync` (when pagination is enabled).

---

## Best Practices

- Prefer strong types for `TData` / `TParams`; avoid `dynamic`.
- Decide the param source first: if a dependency change must carry new params, use
  `useRequestFn` (closure mode); if it just means "ask again" with unchanged params,
  use params mode + `refreshDeps` (see
  [Where do params come from?](#where-do-params-come-from-closure-mode-params-mode-and-refreshdeps)).
- Add `ProviderScope` only for the Riverpod Provider path (`createUseRequestProvider` / `ConsumerWidget`); `UseRequestBuilder` itself does not need it.
- Put side-effects in callbacks (`onSuccess`/`onError`) instead of scattering in UI.
- Choose reasonable polling intervals; combine with debounce/throttle if needed.
- Cancel in-flight requests on page dispose or rapid re-runs.

---

## Flutter Web Demo & Renderer

```bash
cd example
flutter run -d chrome --web-renderer html
flutter run -d chrome --web-renderer canvaskit
```

```bash
flutter build web --release --web-renderer html
flutter build web --release --web-renderer canvaskit
```

Guideline:
- `html` renderer ships smaller bundles and loads faster for data-heavy UIs.
- `canvaskit` looks closer to mobile but is heavier.

---

## FAQ

- Q: Must `UseRequestBuilder` be under `ProviderScope`?
  - A: No. `UseRequestBuilder` manages `UseRequestNotifier` internally and does not depend on a Riverpod container.
- Q: When is `ProviderScope` actually required?
  - A: When you use the Riverpod Provider path such as `createUseRequestProvider`, `ConsumerWidget`, or `WidgetRef`. Pure Hook usage and `UseRequestBuilder` do not require it.
- Q: Can I use Hook version in a plain `StatelessWidget`?
  - A: Use `HookWidget` or `HookBuilder`.
- Q: Does `refreshOnReconnect` work out of the box?
  - A: It works when you provide `reconnectStream`; the library does not include network detection.
- Q: Why does the API still send the old params after I switch a filter tab?
  - A: Most likely you used params mode with only `refreshDeps` and no
    `refreshDepsAction` — the default `refresh()` reuses the last params. Switch to
    closure mode `useRequestFn`, or hand-write `refreshDepsAction` (see
    [the trap](#-the-params-mode--refreshdeps-trap)).

---

## Source Map

- Hook core (`useRequest` / `useRequestFn`): `lib/src/use_request.dart`
- Riverpod core: `lib/src/use_request_riverpod.dart`
- Types: `lib/src/types.dart`
- Dio adapter: `lib/src/utils/dio_adapter.dart`
- Utils: `lib/src/utils/`
