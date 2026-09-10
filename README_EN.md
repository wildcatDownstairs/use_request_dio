English | [简体中文](README.md)

# useRequest

A Flutter async task state library with auto/manual execution, loading/error/data state, refresh, polling, debounce, throttle, retry, cache, cancellation, and local mutation. A service can be any `Future`; Dio and Riverpod remain built-in integrations in the 0.7.0 line.

## Install

```yaml
dependencies:
  use_request: ^0.7.0
```

## Closure mode

Prefer `useRequestFn` when a filter or other widget state drives the request:

```dart
class UserName extends HookWidget {
  const UserName({super.key, required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context) {
    final request = useRequestFn(
      () => api.fetchUser(userId),
      options: UseRequestOptions(refreshDeps: [userId]),
    );

    if (request.loading) return const CircularProgressIndicator();
    if (request.error != null) return Text('${request.error}');
    return Text(request.data?.name ?? 'No user');
  }
}
```

## Explicit params mode

Use `run(params)` for button, submit, and search actions:

```dart
final request = useRequest<User, int>(
  api.fetchUser,
  options: const UseRequestOptions(manual: true),
);

ElevatedButton(
  onPressed: () => request.run(42),
  child: const Text('Load user'),
);
```

`refreshDeps` decides when to refresh. In params mode, `refresh()` reuses the latest params. Use closure mode when the dependency is itself the request input.

## Docs and examples

- [Full English guide](doc/guide.en.md)
- [API and behavior contracts](doc/contracts.en.md)
- [Optional Dio integration](doc/dio-integration.en.md)
- [Future Dio/Riverpod package split](doc/package-migration.en.md)
- [Minimal copyable example](example/lib/main.dart)
- [Full web showcase](website/lib/main.dart) · [Live demo](https://wildcatdownstairs.github.io/use_request_dio/)

```dart
import 'package:use_request/use_request.dart';
```

The 0.7.0 line keeps the existing unified entry point and public API. The main package still directly depends on Dio, flutter_hooks, Riverpod, and web visibility support; moving exports alone would not make those dependencies optional.

## Validate

```bash
flutter analyze
flutter test
cd example && flutter test
cd ../website && flutter test && flutter build web
```

See [LICENSE](LICENSE).
