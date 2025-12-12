English | [简体中文](README.md)

# Demo
- Install deps in example: `cd example && flutter pub get`
- Run on your target platform:
  - Web (Chrome): `flutter run -d chrome`
  - macOS desktop: `flutter run -d macos`
  - iOS simulator: `flutter run -d ios` (requires Xcode)
  - Android: `flutter run -d android` (emulator/device)
- Demo home & feature pages: `example/lib/demo/use_request_demo_page.dart`

# useRequest

> A Flutter async request management library inspired by ahooks `useRequest`.  
> It supports auto/manual requests, polling, debounce/throttle, refresh-on-focus,
> retry with backoff, delayed loading, cancellation, local mutation, and more.

- Hook entry: `useRequest` (`lib/src/use_request.dart`)
- Riverpod entry: `UseRequestNotifier` / `createUseRequestProvider` / `UseRequestBuilder`
  (`lib/src/use_request_riverpod.dart`)
- HTTP adapter: `DioHttpAdapter` (`lib/src/utils/dio_adapter.dart`)
- Types/config: `UseRequestOptions`, `UseRequestResult`, `UseRequestState`
  (`lib/src/types.dart`)

---

## Features

### Core
- Auto/manual/ready: control initial request by `manual` + `defaultParams`; when
  `ready=false`, auto request & polling are deferred.
- Polling: periodic fetch via `pollingInterval`, with start/stop controls
  (Riverpod exposes methods).
- Polling visibility: when `pollingWhenHidden=false`, polling pauses on
  focus-loss/background and resumes on foreground.
- Polling error policy: `pausePollingOnError` pauses polling on error; optional
  `pollingRetryInterval` auto-resumes after a delay.
- Debounce / throttle: `debounceInterval` or `throttleInterval` (mutually
  exclusive), with leading/trailing and debounce `maxWait`.
- Refresh on focus: `refreshOnFocus` refreshes when app regains focus.
- Dependency refresh: `refreshDeps` / `refreshDepsAction` (Hook) triggers refresh
  when deps change.
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

### Advanced (v2.0)
- **HTTP semantic layer**: `DioHttpAdapter` provides typed GET/POST/PUT/DELETE/PATCH.
- **Per-request timeouts**: `connectTimeout` / `receiveTimeout` / `sendTimeout`.
- **Upload / download**: file transfer with progress callbacks.
- **Retry callback**: `onRetryAttempt` to observe retry attempts.

---

## Installation

Add dependencies in `pubspec.yaml`:

```yaml
dependencies:
  dio: ^5.9.0
  flutter_hooks: ^0.20.5
  flutter_riverpod: ^2.6.1
  # Optional: only if you use HookConsumerWidget / hooks_riverpod in UI
  hooks_riverpod: ^2.6.1
```

Import from the unified entry:

```dart
import 'package:use_request/use_request.dart';
```

If you use `UseRequestBuilder` or Riverpod providers, wrap your app with
`ProviderScope`:

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
final fetchUsers = createDioService<List<dynamic>, void>(
  dio: Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com')),
  method: HttpMethod.get,
  path: '/users',
);

final result = useRequest<List<dynamic>, void>(
  fetchUsers,
  options: const UseRequestOptions(manual: false),
);
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

  // Dependency refresh (Hook)
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

  // Timeouts (v2.0)
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
- Add `ProviderScope` for builder/provider usage.
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
  - A: Yes, it is a `ConsumerStatefulWidget`.
- Q: Can I use Hook version in a plain `StatelessWidget`?
  - A: Use `HookWidget` or `HookBuilder`.
- Q: Does `refreshOnReconnect` work out of the box?
  - A: It's a placeholder unless you provide `reconnectStream`.

---

## Source Map

- Hook core: `lib/src/use_request.dart`
- Riverpod core: `lib/src/use_request_riverpod.dart`
- Types: `lib/src/types.dart`
- Dio adapter: `lib/src/utils/dio_adapter.dart`
- Utils: `lib/src/utils/`
