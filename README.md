简体中文 | [English](README_EN.md)

[![pub package](https://img.shields.io/pub/v/use_request.svg)](https://pub.dev/packages/use_request)
[![likes](https://img.shields.io/pub/likes/use_request)](https://pub.dev/packages/use_request/score)
[![pub points](https://img.shields.io/pub/points/use_request)](https://pub.dev/packages/use_request/score)
[![popularity](https://img.shields.io/pub/popularity/use_request)](https://pub.dev/packages/use_request/score)
[![Flutter CI](https://github.com/wildcatDownstairs/use_request_dio/actions/workflows/dart.yml/badge.svg)](https://github.com/wildcatDownstairs/use_request_dio/actions/workflows/dart.yml)

# demo
- 进入示例目录并安装依赖： `cd example && flutter pub get`
- 按平台启动：
- Web（Chrome）： `flutter run -d chrome`
- macOS 桌面： `flutter run -d macos`
- iOS 模拟器： `flutter run -d ios` （需安装 Xcode）
- Android： `flutter run -d android` （需已启动模拟器或连接设备）
- 示例首页与各功能演示： example/lib/demo/use_request_demo_page.dart:1

# useRequest 组件库文档

> 面向 Flutter 的通用异步请求管理库，借鉴 ahooks 的 `useRequest` 思路，提供自动/手动请求、轮询、防抖/节流、聚焦刷新、失败重试、延迟 loading、取消请求、数据变更等能力。

- Hook 版入口：`useRequest`（`lib/src/use_request.dart`）
- Riverpod 版入口：`UseRequestNotifier` / `createUseRequestProvider` / `UseRequestBuilder`（`lib/src/use_request_riverpod.dart`）
- HTTP 适配器：`DioHttpAdapter`（`lib/src/utils/dio_adapter.dart`）
- 类型与配置：`UseRequestOptions`、`UseRequestResult`、`UseRequestState`（`lib/src/types.dart`）

---

## 特性概览

### 核心功能
- 自动/手动/就绪：通过 `manual` 与 `defaultParams` 控制初始请求，`ready=false` 时延迟首次请求/轮询
- 轮询：`pollingInterval` 周期拉取，支持开始/停止（Riverpod 版提供控制方法）
- 轮询可见性：`pollingWhenHidden=false` 时应用失焦/后台会暂停轮询，回到前台恢复
- 轮询错误策略：`pausePollingOnError` 遇错自动暂停（手动恢复）
- 防抖/节流：`debounceInterval` / `throttleInterval`（二选一），支持 leading/trailing、debounce 的 maxWait
- 聚焦刷新：`refreshOnFocus` 在应用重新获得焦点时自动刷新
- 依赖刷新：`refreshDeps` / `refreshDepsAction`（Hook 版），依赖变化后自动刷新
- 缓存与并发控制：`cacheKey` + `cacheTime`/`staleTime` 缓存结果，`fetchKey` 按 key 隔离取消/计数（状态以最后一次触发的 key 为准）
- 加载更多：`loadMoreParams` + `dataMerger` + `hasMore`，提供 `loadMore`/`loadingMore`
- 失败重试：`retryCount` + `retryInterval`，网络不稳定场景更鲁棒
- 延迟 loading：`loadingDelay` 优化短请求的"闪烁"体验
- 取消请求：`cancel()` 与自定义 `CancelToken`
- 数据变更：`mutate()` 直接修改数据不触发请求
- 回调钩子：`onBefore`、`onSuccess`、`onError`、`onFinally`

### 高级功能（v2.0 新增）
- **HTTP 语义层**：`DioHttpAdapter` 提供 GET/POST/PUT/DELETE/PATCH 等语义化方法
- **超时配置**：`connectTimeout`/`receiveTimeout`/`sendTimeout` 精细控制请求超时
- **文件上传/下载**：支持进度回调的文件传输功能
- **重试回调**：`onRetryAttempt` 实时追踪重试进度

---

## 安装与引入

在 `pubspec.yaml` 添加依赖（项目已经包含）：

```yaml
dependencies:
  dio: ^5.9.0
  flutter_hooks: ^0.20.5
  flutter_riverpod: ^2.6.1
  # 可选：若你在 UI 里使用 HookConsumerWidget / hooks_riverpod
  hooks_riverpod: ^2.6.1
```

统一从导出入口引入：

```dart
import 'package:use_request/use_request.dart';
```

若使用 `UseRequestBuilder` 或 Provider 版本，请确保在根部包裹 `ProviderScope`：

```dart
void main() {
  runApp(const ProviderScope(child: MyApp()));
}
```

---

## 快速上手

### Hook 版（`useRequest`）

适合 `HookWidget` 或 `HookConsumerWidget` 中的本地状态管理。

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
    // 自动触发请求（零配置）
    // 默认传入 null 作为参数，Service 接收后忽略即可
    final request = useRequest<List<User>, dynamic>(
      ([_]) => fetchUserList(), 
    );

    // 自动触发请求（带默认参数）
    final userRequest = useRequest<User, int>(
      fetchUser,
      options: const UseRequestOptions(
        defaultParams: 1, // 组件挂载后自动请求 fetchUser(1)
      ),
    );

    if (userRequest.loading) return const CircularProgressIndicator();
    if (userRequest.error != null) return Text('Error: ${userRequest.error}');
    
    return Text('User: ${userRequest.data?.name}');
  }
}
```

### Riverpod 版（`UseRequestBuilder`）

无需使用 Hook，任意组件中以 Builder 方式获取状态与操作。

```dart
Scaffold(
  appBar: AppBar(title: const Text('Builder 示例')),
  body: UseRequestBuilder<User, UserParams>(
    service: fetchUser,
    options: const UseRequestOptions(
      manual: false,
      defaultParams: UserParams(1),
    ),
    builder: (context, state, notifier) {
      if (state.loading) return const Center(child: CircularProgressIndicator());
      if (state.error != null) return Center(child: Text('错误: ${state.error}'));
      return Column(
        children: [
          Text(state.data?.name ?? ''),
          ElevatedButton(
            onPressed: () => notifier.run(UserParams(2)),
            child: const Text('拉取另一个用户'),
          ),
        ],
      );
    },
  ),
);
```

组件定义参考：`lib/src/use_request_riverpod.dart:345`。

### Riverpod Provider 版

适合跨组件共享请求状态，或需要更精细的轮询控制。

```dart
final userRequestProvider = createUseRequestProvider<User, UserParams>(
  service: fetchUser,
  options: const UseRequestOptions(manual: true),
);

class RiverpodProviderExample extends ConsumerWidget {
  const RiverpodProviderExample({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userRequestProvider); // 状态
    final notifier = ref.read(userRequestProvider.notifier); // 操作

    return Column(
      children: [
        if (state.loading) const CircularProgressIndicator(),
        if (state.error != null) Text('错误: ${state.error}'),
        if (state.data != null) Text('用户名: ${state.data!.name}')
        else const Text('空态'),
        Row(
          children: [
            ElevatedButton(onPressed: () => notifier.run(UserParams(1)), child: const Text('请求')),
            ElevatedButton(onPressed: notifier.refresh, child: const Text('刷新')),
          ],
        ),
      ],
    );
  }
}
```

Provider 工厂参考：`lib/src/use_request_riverpod.dart:286`。

---

## HTTP 语义层（DioHttpAdapter）

`DioHttpAdapter` 提供类型安全的 HTTP 方法语义层，简化与 `useRequest` 的集成。

### 基础用法

```dart
import 'package:use_request/use_request.dart';

// 创建适配器
final http = DioHttpAdapter(
  dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
);

// GET 请求
final users = await http.get<List<User>>('/users');

// POST 请求
final newUser = await http.post<User>('/users', data: {'name': 'John'});

// PUT 请求
await http.put('/users/1', data: {'name': 'Jane'});

// DELETE 请求
await http.delete('/users/1');

// PATCH 请求
await http.patch('/users/1', data: {'status': 'active'});
```

### 与 useRequest 集成

```dart
// 使用 createDioService 工厂函数
final fetchUsers = createDioService<List<dynamic>, void>(
  dio: Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com')),
  method: HttpMethod.get,
  path: '/users',
);

// 在组件中使用
final result = useRequest<List<dynamic>, void>(
  fetchUsers,
  options: const UseRequestOptions(manual: false),
);
```

### 超时配置

```dart
// 方式一：在 DioHttpAdapter 中配置
final http = DioHttpAdapter(
  dio: Dio(BaseOptions(
    baseUrl: 'https://api.example.com',
    connectTimeout: Duration(seconds: 10),
    receiveTimeout: Duration(seconds: 30),
    sendTimeout: Duration(seconds: 30),
  )),
);

// 方式二：在 UseRequestOptions 中配置（覆盖 Dio 默认值）
UseRequestOptions(
  connectTimeout: Duration(seconds: 5),
  receiveTimeout: Duration(seconds: 15),
  sendTimeout: Duration(seconds: 15),
);
```

### 文件上传（带进度）

```dart
final http = DioHttpAdapter(dio: Dio());

// 上传文件并追踪进度
await http.uploadFile(
  '/upload',
  filePath: '/path/to/file.jpg',
  fileField: 'file',
  onProgress: (sent, total) {
    final progress = (sent / total * 100).toStringAsFixed(1);
    print('上传进度: $progress%');
  },
);
```

### 文件下载（带进度）

```dart
await http.downloadFile(
  '/files/document.pdf',
  savePath: '/local/path/document.pdf',
  onProgress: (received, total) {
    final progress = (received / total * 100).toStringAsFixed(1);
    print('下载进度: $progress%');
  },
);
```

### HttpRequestConfig 配置对象

```dart
// 使用配置对象发起请求
final config = HttpRequestConfig(
  method: HttpMethod.post,
  path: '/api/data',
  data: {'key': 'value'},
  queryParameters: {'page': '1'},
  headers: {'Authorization': 'Bearer token'},
  cancelToken: CancelToken(),
);

final response = await http.request<Map<String, dynamic>>(config);
```

---

## API 参考

### 类型定义

- `Service<TData, TParams>`：`Future<TData> Function(TParams params)`（`lib/src/types.dart:3`）
- `OnBefore` / `OnSuccess` / `OnError` / `OnFinally` 回调类型（`lib/src/types.dart:6-20`）

### 配置项：`UseRequestOptions<TData, TParams>`（`lib/src/types.dart`）

```dart
const UseRequestOptions({
  // ========== 基础配置 ==========
  bool manual = false,              // 是否手动触发请求
  bool ready = true,                // 是否就绪（false 时阻止自动请求/轮询）
  TParams? defaultParams,           // 默认参数（manual=false 时自动使用）

  // ========== 依赖刷新 ==========
  List<Object?>? refreshDeps,       // 依赖项列表（变化时自动刷新）
  VoidCallback? refreshDepsAction,  // 依赖变化时的自定义动作

  // ========== 轮询配置 ==========
  Duration? pollingInterval,        // 轮询间隔
  bool pollingWhenHidden = true,    // 应用后台时是否继续轮询
  bool pausePollingOnError = false, // 出错时是否暂停轮询
  Duration? pollingRetryInterval,   // 轮询错误后的重试间隔

  // ========== 防抖配置 ==========
  Duration? debounceInterval,       // 防抖间隔
  bool debounceLeading = false,     // 是否在首次调用时立即执行
  bool debounceTrailing = true,     // 是否在延迟结束后执行
  Duration? debounceMaxWait,        // 最大等待时间（防止无限等待）

  // ========== 节流配置 ==========
  Duration? throttleInterval,       // 节流间隔
  bool throttleLeading = true,      // 是否在首次调用时立即执行
  bool throttleTrailing = true,     // 是否在间隔结束后执行最后一次

  // ========== 重试配置 ==========
  int? retryCount,                  // 最大重试次数
  Duration? retryInterval,          // 重试间隔
  bool retryExponential = true,     // 是否使用指数退避
  OnRetryAttempt? onRetryAttempt,   // 每次重试时的回调 (attempt, error) => void

  // ========== 超时配置（v2.0 新增）==========
  Duration? connectTimeout,         // 连接超时
  Duration? receiveTimeout,         // 接收超时
  Duration? sendTimeout,            // 发送超时

  // ========== 加载与刷新 ==========
  Duration? loadingDelay,           // 延迟显示 loading（避免闪烁）
  bool refreshOnFocus = false,      // 应用获得焦点时自动刷新
  bool refreshOnReconnect = false,  // 网络重连时自动刷新（占位）
  Stream<bool>? reconnectStream,    // 网络重连事件流

  // ========== 缓存配置 ==========
  String Function(TParams params)? cacheKey,  // 缓存键生成函数
  Duration? cacheTime,              // 缓存有效期
  Duration? staleTime,              // 数据新鲜期（过期后静默刷新）

  // ========== 并发与加载更多 ==========
  String Function(TParams params)? fetchKey,  // 并发隔离键
  TParams Function(TParams lastParams, TData? data)? loadMoreParams,  // 下一页参数
  TData Function(TData? previous, TData next)? dataMerger,  // 数据合并函数
  bool Function(TData? data)? hasMore,  // 是否还有更多数据

  // ========== 取消与回调 ==========
  CancelToken? cancelToken,         // Dio 取消令牌
  OnBefore<TParams>? onBefore,      // 请求前回调
  OnSuccess<TData, TParams>? onSuccess,  // 成功回调
  OnError<TParams>? onError,        // 失败回调
  OnFinally<TData, TParams>? onFinally,  // 完成回调（无论成功失败）
})
```

- 自动请求：`manual=false` 且提供 `defaultParams` 时，`ready=true` 时挂载后自动拉取
- 就绪态：`ready=false` 时阻止自动请求/轮询；设为 `true` 后再进入正常流程
- 依赖刷新：`refreshDeps` 变动时自动刷新（Hook 版），可用 `refreshDepsAction` 自定义行为
- 缓存与复用：显式传入 `cacheKey` 开启缓存；`cacheTime` 控制缓存有效期（null 表示不过期），`staleTime` 超时后会在保留缓存的同时重新请求
- 并发隔离：`fetchKey` 将不同 key 的请求计数/取消令牌隔离；但状态仍是单态，只有最后一次 `run` 的 key（active key）会更新 UI，其它 key 的结果视为被覆盖
- 加载更多：提供 `loadMoreParams` 生成下一页参数、`dataMerger` 合并数据、`hasMore` 判定是否还有更多；`UseRequestResult` 暴露 `loadingMore`、`hasMore` 与 `loadMore`/`loadMoreAsync`
- 轮询策略：`pollingWhenHidden=false` 失焦暂停、前台恢复；`pausePollingOnError` 遇错暂停，若设置 `pollingRetryInterval` 会在该间隔后自动尝试恢复；`refreshOnReconnect` + `reconnectStream` 可在网络恢复时刷新
- 轮询：`pollingInterval` 不为 `null` 时开启（Hook 版自动轮询；Riverpod 版 additionally 提供 `startPolling()`/`stopPolling()`）
- 频率控制：`debounceInterval` / `throttleInterval` 二选一
- 重试：`retryCount` 与 `retryInterval` 控制失败重试
- 延迟 loading：`loadingDelay` 控制进入 loading 的延时，避免闪烁
- 刷新策略：`refreshOnFocus`、`refreshOnReconnect`（后者为占位，跨平台网络重连尚未统一）
- 取消令牌：可传入自定义 `CancelToken` 与 `cancel()` 配合使用
- 生命周期回调：`onBefore`、`onSuccess`、`onError`、`onFinally`

### 返回对象：`UseRequestResult<TData, TParams>`（`lib/src/types.dart:124`）

- 状态字段：`loading`、`data`、`error`、`params`
- 方法：
  - `runAsync(params)` / `run(params)`
  - `refreshAsync()` / `refresh()`（使用上一次参数）
  - `mutate((old) => new)` 直接变更数据
  - `cancel()` 取消进行中的请求

### 内部状态：`UseRequestState<TData, TParams>`（`lib/src/types.dart:170`）

- 字段：`loading`、`data`、`error`、`params`、`requestCount`
- 说明：用于内部状态维护与 Riverpod 暴露；一般无需直接操作

### Riverpod 能力（`lib/src/use_request_riverpod.dart`）

- `UseRequestNotifier<TData, TParams>`：核心状态机（请求、轮询、重试、取消等）定义见 `:14` 起
- `createUseRequestProvider<TData, TParams>()`：Provider 工厂（`:286`）
- `UseRequestBuilder<TData, TParams>`：Builder 组件（`:345`）
- `UseRequestMixin<TData, TParams>`：在 `ConsumerWidget` 中获得 Hook 风格 API（`:299`）

---

## 功能详解与示例

### 自动/手动请求

```dart
// 自动：提供 defaultParams 且 manual=false
UseRequestOptions(
  manual: false,
  defaultParams: UserParams(1),
);

// 手动：manual=true，不会在挂载时触发
UseRequestOptions(
  manual: true,
);
```

### 防抖/节流

```dart
// 搜索输入防抖
UseRequestOptions(
  manual: true,
  debounceInterval: const Duration(milliseconds: 300),
);
// 滚动事件节流
UseRequestOptions(
  manual: true,
  throttleInterval: const Duration(milliseconds: 500),
);
```

### 轮询

```dart
// Hook 版：挂载后按间隔自动执行
UseRequestOptions(
  manual: false,
  defaultParams: UserParams(1),
  pollingInterval: const Duration(seconds: 10),
);
// 若 manual=true，调用一次 run/runAsync 成功后会自动进入轮询

// Riverpod 版：可手动开始/停止
final provider = createUseRequestProvider<User, UserParams>(
  service: fetchUser,
  options: const UseRequestOptions(
    manual: true,
    pollingInterval: Duration(seconds: 10),
  ),
);
// 在组件中：
final notifier = ref.read(provider.notifier);
notifier.startPolling();
// ...
notifier.stopPolling();
```

### 失败重试

```dart
UseRequestOptions(
  retryCount: 3,
  retryInterval: const Duration(seconds: 1),
);
```

### 延迟 loading 与聚焦刷新

```dart
UseRequestOptions(
  loadingDelay: const Duration(milliseconds: 200),
  refreshOnFocus: true,
);
```

### 取消请求与数据变更

```dart
// 取消当前进行中的请求
notifier.cancel();

// 直接变更数据（不触发请求）
notifier.mutate((old) => old == null ? old : old.copyWith(name: '新名字'));
```

---

## 最佳实践

- 强类型：为 `TData` 与 `TParams` 提供精确类型，避免使用 `dynamic`
- ProviderScope：使用 `UseRequestBuilder` 或 Riverpod Provider 时务必添加 `ProviderScope`
- 回调与副作用：首推在 `onSuccess` 中做后续处理，避免在 UI 中到处散落逻辑
- 刷新与轮询：合理设置间隔，避免高频请求造成压力；必要时结合节流
- 错误处理：统一在 `onError` 或 UI 层进行错误展示与埋点
- 取消请求：页面切换或重复点击场景建议及时调用 `cancel()`

---

## 真实示例（摘自示例文件）

- 完整示例 App 见：`example/lib/main.dart`
- Demo 首页与各功能示例见：`example/lib/demo/use_request_demo_page.dart`
- 具体功能组件示例见：`example/lib/demo/widgets/`

---

## Flutter Web Demo 与渲染器选择

示例 App 支持 Flutter Web，可用不同渲染器对比首屏与包体：

```bash
cd example
flutter run -d chrome --web-renderer html
flutter run -d chrome --web-renderer canvaskit
```

构建并查看产物大小：

```bash
flutter build web --release --web-renderer html
flutter build web --release --web-renderer canvaskit
```

经验上：
- `html` 渲染首屏包体更小、加载更快，适合信息展示/表单类应用。
- `canvaskit` 视觉一致性更好（与移动端接近），但产物更大、首屏更慢。

建议在自己的 Web 项目中按场景权衡选择。

---

## 常见问题（FAQ）

- Q：`UseRequestBuilder` 必须在 `ProviderScope` 下吗？
  - A：是的，它是 `ConsumerStatefulWidget`，建议在根部包裹 `ProviderScope`。
- Q：Hook 版如何在普通 `StatelessWidget` 使用？
  - A：Hook 版需要 `HookWidget` 或在 `HookBuilder` 环境中使用。
- Q：`refreshOnReconnect` 是否生效？
  - A：该选项目前为占位，跨平台网络重连检测未统一实现。

---

## 参考实现位置

### 核心入口
- `useRequest`：`lib/src/use_request.dart`
- `UseRequestNotifier`：`lib/src/use_request_riverpod.dart`
- `createUseRequestProvider`：`lib/src/use_request_riverpod.dart`
- `UseRequestBuilder`：`lib/src/use_request_riverpod.dart`

### 类型定义
- `UseRequestOptions`：`lib/src/types.dart`
- `UseRequestResult`：`lib/src/types.dart`
- `UseRequestState`：`lib/src/types.dart`

### HTTP 适配器（v2.0 新增）
- `DioHttpAdapter`：`lib/src/utils/dio_adapter.dart`
- `HttpMethod`：`lib/src/utils/dio_adapter.dart`
- `HttpRequestConfig`：`lib/src/utils/dio_adapter.dart`
- `createDioService`：`lib/src/utils/dio_adapter.dart`

### 工具类
- `Debouncer` / `createDebouncer`：`lib/src/utils/debounce.dart`
- `Throttler` / `createThrottler`：`lib/src/utils/throttle.dart`
- `PollingController` / `createPolling`：`lib/src/utils/polling.dart`
- `RetryExecutor` / `executeWithRetry`：`lib/src/utils/retry.dart`
- `RequestCache`：`lib/src/utils/cache.dart`

> 如需扩展，请先查阅 `use_request_exports.dart` 的统一导出（`lib/src/use_request_exports.dart`）。

### 补充说明

- 示例 App 已包裹 ProviderScope （ example/lib/main.dart:6-8 ），可直接运行
- 示例依赖本地包路径（ example/pubspec.yaml:37-43 ），在示例中运行可实时验证库改动
- 库统一导出入口： lib/use_request.dart:1 （项目中引用 package:use_request/use_request.dart ）
