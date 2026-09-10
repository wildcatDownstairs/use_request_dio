# 请求行为契约

[English](contracts.en.md) · [完整指南](guide.zh-CN.md)

Hook、`UseRequestNotifier` 和 `UseRequestBuilder` 复用同一请求状态机。0.7.0 保留统一导出与已有公开 API。

## 执行与配置

- service 接受任意 `Future<T>`。闭包模式 `useRequestFn` 适合筛选条件；参数模式 `run(params)` 适合按钮动作。
- `refresh()` 复用最近参数；`refreshDeps` 决定刷新时机，不替换这些参数。Hook 每次构建更新 service 与 options，回调使用最新配置。
- `ready` 控制自动执行、依赖刷新与轮询；显式 `run` 仍可执行。`refreshDepsAction` 是调用方接管依赖变化的动作。
- `fetchKey` 隔离计数和取消；UI 仍只有一个 active key，只接受最后触发 key 的结果。
- `refreshOnFocus` 的 `focusTimespan` 默认 5 秒；只限制聚焦刷新，不阻碍后台轮询恢复。

## 缓存

`cacheKey` 同时决定内存缓存和 pending 去重。键必须包含业务参数与账号隔离信息；共享键的实例应使用一致的数据类型与请求语义。

- 同键实例正在挂载且接收事件时，成功写入、`setCache` 和 `mutate` 会同步数据。实例切换键或卸载后不再接收旧键更新。
- `mutate((_) => null)` 删除缓存数据并同步空值，不取消正在执行的请求；该请求仍可完成并写入结果。非空 mutate 同样不会提前结束 loading。
- `clearCacheEntry` / `clearAllCache` 删除数据、失效 pending，并阻止清除前的请求重新填充缓存；已有普通 Future 仍可继续执行。
- `cacheTime` 决定保留期，`staleTime` 决定是否后台再验证；纯缓存命中不调用成功/完成回调。失败的后台再验证保留旧缓存。
- 缓存仅在进程内，默认容量 256，按 LRU 淘汰。没有持久化、参数恢复或自定义后端契约。

## 重试

`retryCount` 表示首次尝试之外的最大重试次数。默认策略只重试部分 Dio 网络/超时错误与 5xx；普通异常需要显式 `shouldRetry`。

```dart
final request = useRequestFn(
  () => repository.load(),
  options: UseRequestOptions(
    retryCount: 2,
    shouldRetry: (error) => error is TemporaryFailure,
  ),
);
```

Dio 取消与 `RetryCancelledException` 不会因为自定义策略返回 true 而重试。共享请求仍有消费者时继续重试；最后一个消费者退出时停止后续 retry backoff。已经执行的普通 Future 无法中断。

## 取消与等待

| 路径 | UI 与回调 | 底层与 `runAsync` |
| --- | --- | --- |
| 普通 Future 的 cancel/卸载/覆盖 | 忽略旧结果 | 已开始的 Future 继续；等待者最终收到原结果或异常，不保证立即结束 |
| `HttpRequestConfig` + 使用注入 token 的 Dio service | 忽略取消结果 | token 可中断 Dio，等待者收到取消异常 |
| 共享 pending 的一个消费者 cancel/卸载 | 该实例忽略结果 | 其他消费者保留请求，最后一个退出才触发库拥有的 transport 取消 |
| 缓存清除 | 清空数据并结束相应 loading | 失效旧缓存写入资格，普通 Future 不能被强行终止 |

`cancel()` 也取消防抖/节流队列，并停止该实例接收缓存事件，直到下一次执行。`pausePolling()` 暂停轮询并取消当前请求。外部 Dio token 属于调用方：共享 transport 的创建者外部 token 取消会影响全部消费者，详见 [Dio 接入](dio-integration.zh-CN.md)。
