# Dio 接入

[English](dio-integration.en.md) · [行为契约](contracts.zh-CN.md)

可以直接保留现有 Dio、http、retrofit 或 repository service：`useRequestFn(() => repository.fetchUser())`。不必为了状态管理替换客户端、拦截器、鉴权或 JSON 解析。

“可选接入”指用法可选；0.7.0 主包仍直接依赖 Dio 和 Riverpod，没有实现依赖可选化。

## 需要库管理 transport 取消时

使用已有 `Dio` 创建 adapter，把 `HttpRequestConfig` 交给 service；该路径会注入每次请求的内部 token。service 必须把该配置/token 传给 Dio，才能实际中断 I/O。

```dart
final adapter = DioHttpAdapter(dio: dio);
final service = createDioService<Map<String, dynamic>>(adapter);
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  service,
  options: const UseRequestOptions(manual: true),
);
request.run(const HttpRequestConfig(path: '/users'));
```

原 HTTP 方法演示保留为配置示例，响应转换与业务成功条件由 service 处理：

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

## token 所有权与共享请求

- `cancel()` 取消库拥有的内部 token，不反向取消调用方 token。普通 Future service 无法被强行中断；即使它内部使用 Dio，库也不会自动访问其私有 token。
- options 与单次 `HttpRequestConfig` 中的外部 token 都链接到内部 token。外部 token 取消不可恢复，下一轮需要新 token。
- 同 cacheKey pending 去重时，一个实例调用 cancel/卸载不会中断其他实例需要的 transport；全部消费者退出才取消库拥有的 transport。
- 创建 transport 的实例若使用调用方外部 token，该 token 直接取消会终止共享 transport，影响所有等待者；后加入者的外部 token 只隔离该消费者结果，不拥有创建者的 transport。需要独立取消边界时使用不同 cacheKey，或由业务统一管理共享 token。
- clear cache 会使共享 pending 失效。取消不保证服务器撤销已接收的写操作；不要自动重试不具备业务幂等保证的写操作。

超时配置仅对 `HttpRequestConfig` 接入生效；普通 service 请在现有客户端设置超时。更多上传、下载与响应转换见 [完整指南](guide.zh-CN.md)。
