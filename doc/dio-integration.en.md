# Dio integration

[简体中文](dio-integration.zh-CN.md) · [Contracts](contracts.en.md)

Keep existing Dio, http, retrofit, or repository services: `useRequestFn(() => repository.fetchUser())` works without replacing clients, interceptors, authentication, or response parsing.

The adapter is optional to use. Dio and Riverpod remain direct dependencies of the 0.7.0 main package.

## Library-managed transport cancellation

Wrap an existing Dio client and pass `HttpRequestConfig` through the service. This path injects an internal token for each request; the service must forward that configuration/token to Dio to interrupt I/O.

```dart
final adapter = DioHttpAdapter(dio: dio);
final service = createDioService<Map<String, dynamic>>(adapter);
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  service,
  options: const UseRequestOptions(manual: true),
);
request.run(const HttpRequestConfig(path: '/users'));
```

The former HTTP-method demo is retained here as configuration examples. Services own response conversion and business success rules:

```dart
request.run(const HttpRequestConfig(
  path: '/users', method: HttpMethod.post, data: {'name': 'Alice'},
));
request.run(const HttpRequestConfig(
  path: '/users/42', method: HttpMethod.put, data: {'name': 'Bob'},
));
request.run(const HttpRequestConfig(
  path: '/users/42', method: HttpMethod.delete,
));
```

## Ownership and shared work

- `cancel()` cancels an internally owned token, without cancelling caller-owned tokens. Ordinary Futures cannot be interrupted, even if their service privately uses Dio.
- External tokens from options and `HttpRequestConfig` link to the internal token. Cancelled external tokens cannot be reset; create a new token for subsequent work.
- With pending deduplication, cancelling/disposing one consumer preserves transport needed by others. The library cancels owned transport when the last consumer leaves.
- Cancelling the transport creator's external token terminates transport for all consumers. A later joiner's external token only suppresses that consumer's result; it does not own the creator's transport. Use different cache keys for independent cancellation boundaries, or coordinate shared tokens in your application.
- Clearing cache invalidates shared pending work. Cancellation cannot promise to undo writes already received by a server; retry writes only with appropriate business idempotency guarantees.

Option-level timeouts apply to `HttpRequestConfig` integration. Other services configure their existing clients directly. See the [full guide](guide.en.md) for upload/download and response conversion.
