简体中文 | [English](guide.en.md)

[![GitHub](https://img.shields.io/badge/GitHub-use__request__dio-181717?logo=github)](https://github.com/wildcatDownstairs/use_request_dio)
[![pub package](https://img.shields.io/pub/v/use_request.svg)](https://pub.dev/packages/use_request)
[![likes](https://img.shields.io/pub/likes/use_request)](https://pub.dev/packages/use_request/score)
[![pub points](https://img.shields.io/pub/points/use_request)](https://pub.dev/packages/use_request/score)
[![popularity](https://img.shields.io/pub/popularity/use_request)](https://pub.dev/packages/use_request/score)
[![Flutter CI](https://github.com/wildcatDownstairs/use_request_dio/actions/workflows/dart.yml/badge.svg)](https://github.com/wildcatDownstairs/use_request_dio/actions/workflows/dart.yml)
[![Web Demo](https://img.shields.io/badge/Web%20Demo-GitHub%20Pages-0ea5a4)](https://wildcatdownstairs.github.io/use_request_dio/)

# useRequest 组件库文档

> 面向 Flutter 的通用异步请求管理库，借鉴 ahooks 的 `useRequest` 思路，提供自动/手动请求、轮询、防抖/节流、聚焦刷新、失败重试、延迟 loading、取消请求、数据变更等能力。

- Hook 版入口：`useRequest`（参数模式） / `useRequestFn`（闭包模式）（`lib/src/use_request.dart`）
- Riverpod 版入口：`UseRequestNotifier` / `createUseRequestProvider` / `UseRequestBuilder`（`lib/src/use_request_riverpod.dart`）
- HTTP 适配器：`DioHttpAdapter`（`lib/src/utils/dio_adapter.dart`）
- 类型与配置：`UseRequestOptions`、`UseRequestResult`、`UseRequestState`（`lib/src/types.dart`）

> **⚠️ 必读：[参数从哪来——闭包模式、参数模式与 refreshDeps](#参数从哪来闭包模式参数模式与-refreshdeps)**
> `refreshDeps` 只决定"什么时候重新请求"，不负责"用什么参数请求"。
> 在 Hook 场景里，筛选/搜索这类"依赖变了参数也要变"的情况请用闭包模式 `useRequestFn`；
> 纯 Riverpod Provider / Builder 路径则用 `refreshDepsAction` 或 notifier 的
> `refreshDeps(..., action: ...)` 显式带新参数，否则会遇到"tab 切了但请求参数不变"的经典问题。

## 目录

- [Demo](#demo)
- [给 LLM Agent 看的](#给-llm-agent-看的)
- [特性概览](#特性概览)
- [安装与引入](#安装与引入)
- [快速上手](#快速上手)
- [参数从哪来：闭包模式、参数模式与 refreshDeps](#参数从哪来闭包模式参数模式与-refreshdeps)
- [HTTP 语义层（DioHttpAdapter）](#http-语义层diohttpadapter)
- [API 参考](#api-参考)
- [功能详解与示例](#功能详解与示例)
- [最佳实践](#最佳实践)
- [真实示例（摘自示例文件）](#真实示例摘自示例文件)
- [Flutter Web Demo 与渲染器选择](#flutter-web-demo-与渲染器选择)
- [常见问题（FAQ）](#常见问题faq)
- [参考实现位置](#参考实现位置)

---

## Demo

- 在线体验（GitHub Pages）：https://wildcatdownstairs.github.io/use_request_dio/
- 进入展示站目录并安装依赖： `cd website && flutter pub get`
- 按平台启动：
- Web（Chrome）： `flutter run -d chrome`
- macOS 桌面： `flutter run -d macos`
- iOS 模拟器： `flutter run -d ios` （需安装 Xcode）
- Android： `flutter run -d android` （需已启动模拟器或连接设备）
- 完整展示站：`website/lib/main.dart`
- 最小可复制示例：`example/lib/main.dart`

---

## 给 LLM Agent 看的

### 给人类看的（复制给 Agent）

把下面这段发给你的 Agent（Codex / Claude Code / Cursor 等）。
复制后，Agent 会做三件事：
1. 在你当前项目安装/配置 `use_request` 依赖；
2. 自动挑选并试点改造 1 个"最小网络请求模块"；
3. 输出改造结果与是否继续扩展的建议。

```text
Please follow this guide in my current project (not in use_request package repo), install use_request, and migrate one smallest network module first:
https://raw.githubusercontent.com/wildcatDownstairs/use_request_dio/main/doc/llm-agent-quickstart.zh-CN.md
```

### 给 LLM Agent 看的（直接执行）

```bash
curl -fsSL https://raw.githubusercontent.com/wildcatDownstairs/use_request_dio/main/doc/llm-agent-quickstart.zh-CN.md
```

---

## 特性概览

### 核心功能
- 自动/手动/就绪：通过 `manual` 与 `defaultParams` 控制初始请求，`ready=false` 时延迟首次请求/轮询
- 轮询：`pollingInterval` 周期拉取，支持开始/停止（Riverpod 版提供控制方法）
- 轮询可见性：`pollingWhenHidden=false` 时应用失焦/后台会暂停轮询，回到前台恢复
- 轮询错误策略：`pausePollingOnError` 遇错自动暂停；可配合 `pollingRetryInterval` 自动恢复（否则手动恢复）
- 防抖/节流：`debounceInterval` / `throttleInterval`（二选一），支持 leading/trailing、debounce 的 maxWait
- 聚焦刷新：`refreshOnFocus` 在应用重新获得焦点时自动刷新
- 依赖刷新：`refreshDeps` / `refreshDepsAction`（Hook 版自动监听；Riverpod 版也支持，可通过 notifier 的 `refreshDeps(...)` 手动触发）
- 缓存与并发控制：`cacheKey` + `cacheTime`/`staleTime` 缓存结果，`fetchKey` 按 key 隔离取消/计数（状态以最后一次触发的 key 为准）
- 加载更多：`loadMoreParams` + `dataMerger` + `hasMore`，提供 `loadMore`/`loadingMore`
- 失败重试：`retryCount` + `retryInterval`，网络不稳定场景更鲁棒
- 延迟 loading：`loadingDelay` 优化短请求的"闪烁"体验
- 取消请求：`cancel()` 与自定义 `CancelToken`
- 数据变更：`mutate()` 直接修改数据不触发请求
- 回调钩子：`onBefore`、`onSuccess`、`onError`、`onFinally`
- 观察者机制：`UseRequestObserver` 回调异常会被隔离，不会中断请求主流程
- 缓存一致性：`mutate((_) => null)` 会同步清理对应 `cacheKey` 的缓存条目
- 分页辅助：`PaginationHelpers.pageParams` 支持 `shouldReset`，可在筛选/刷新场景重置页码计数

### 高级功能
- **HTTP 语义层**：`DioHttpAdapter` 提供 GET/POST/PUT/DELETE/PATCH 等语义化方法
- **超时配置**：配合 `HttpRequestConfig` / `DioHttpAdapter` 使用 `connectTimeout`/`receiveTimeout`/`sendTimeout` 精细控制超时
- **文件上传/下载**：支持进度回调的文件传输功能
- **重试回调**：`onRetryAttempt` 实时追踪重试进度

### 闭包驱动版（v0.6.0 新增）
- **`useRequestFn`**：service 为零参闭包，请求条件直接从闭包捕获的外部状态读取；`refreshDeps` 只负责触发时机，天然规避"依赖变化后仍复用旧参数"的问题。详见 [参数从哪来](#参数从哪来闭包模式参数模式与-refreshdeps)。

---

## 安装与引入

在 `pubspec.yaml` 添加依赖（项目已经包含）：

```yaml
dependencies:
  dio: ^5.9.0
  flutter_hooks: ^0.21.3+1
  flutter_riverpod: ^3.0.3
  # 可选：若你在 UI 里使用 HookConsumerWidget / hooks_riverpod
  hooks_riverpod: ^3.0.3
```

统一从导出入口引入：

```dart
import 'package:use_request/use_request.dart';
```

若使用 Riverpod Provider 版本（`createUseRequestProvider`），请确保在根部包裹 `ProviderScope`。`UseRequestBuilder` 内部自管 notifier，本身不依赖 `ProviderScope`：

```dart
void main() {
  runApp(const ProviderScope(child: MyApp()));
}
```

---

## 快速上手

### Hook 版 —— 参数模式（`useRequest`）

适合 `HookWidget` 或 `HookConsumerWidget` 中的本地状态管理，参数由 `run(params)` 显式传入。

```dart
class UserParams { final int id; const UserParams(this.id); }
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
    if (result.error != null) return Text('错误: ${result.error}');
    return Column(
      children: [
        Text(result.data?.name ?? ''),
        ElevatedButton(onPressed: () => result.run(UserParams(2)), child: const Text('再拉一次')),
      ],
    );
  }
}
```

函数定义参考：`lib/src/use_request.dart`。

### Hook 版 —— 闭包模式（`useRequestFn`）

适合"挂载即请求、且不需要外部显式传参"的场景，或者请求条件来自 `useState`/Provider/Riverpod 等外部状态、且希望状态一变就自动带新条件重新请求：

```dart
Future<List<User>> fetchUsers() async => ...;

@override
Widget build(BuildContext context) {
  final request = useRequestFn(fetchUsers);   // 零配置自动触发，无需处理 params

  if (request.loading) return const CircularProgressIndicator();
  return ListView(children: ...);
}
```

```dart
final keyword = useState('');

final request = useRequestFn(
  () => searchUsers(keyword.value),   // 闭包读最新 keyword
  options: UseRequestOptions(refreshDeps: [keyword.value]),
);
```

两种模式怎么选、`refreshDeps` 到底如何生效，见下一章 [参数从哪来](#参数从哪来闭包模式参数模式与-refreshdeps)——这是全库最容易踩坑的部分。

### 组件版（`UseRequestBuilder`）

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

组件定义参考：`lib/src/use_request_riverpod.dart`。

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

Provider 工厂参考：`lib/src/use_request_riverpod.dart`。

---

## 参数从哪来：闭包模式、参数模式与 refreshDeps

> 这是全库最容易踩坑的一块。如果你只看一章，看这章。
>
> 一句话总结：**refreshDeps 只决定"什么时候重新请求"，从来不负责"用什么参数请求"。**
> 参数要么来自闭包（推荐给自动刷新场景），要么来自 `run(params)`（推荐给手动动作）。

### 两种模式速查

| | 闭包模式 `useRequestFn` | 参数模式 `useRequest` + `run(params)` |
|---|---|---|
| service 签名 | `() => api(query)` 零参闭包 | `(params) => api(params)` 显式接参 |
| 参数来源 | 闭包捕获的外部状态 | 每次 `run(params)` 显式传入 |
| 依赖变化自动刷新 | ✅ `refreshDeps` 直接可用 | ⚠️ 需要 `refreshDepsAction`，否则复用旧参数 |
| 分页 `loadMore` | ❌ 把 page 放进外部状态 | ✅ `loadMoreParams` 自动推导下一页 |
| 典型场景 | 搜索输入、筛选 tab、Hook 上下文里的 Provider/Riverpod 派生条件 | 点击搜索按钮、表单提交、手动刷新 |
| 可用范围 | `HookWidget` / `HookConsumerWidget` | Hook 版 / 组件版 / Riverpod Provider 版通用 |

### 为什么是两个入口，不是一个 `useRequest(fn)`

这不是为了多造一个 API，而是 Dart 这边确实需要把两种语义拆开。

如果你完全不关心 JS/TS，可以只记这一句：

- `useRequest`：库会在你调用 `run(params)` 时，把这份 `params` 传给 service
- `useRequestFn`：库不会给 service 传参数，service 自己去读外部状态

- 参数模式需要的 service 签名是 `Future<T> Function(TParams)`。
- 闭包模式需要的 service 签名是 `Future<T> Function()`。
- 如果把两者硬塞进一个 `useRequest(fn)`，公开签名就只能放宽成 `Function` 或类似 `Object?` 的写法，再在内部做运行时分流。

可以把它理解成下面这两种完全不同的调用过程：

```dart
// 参数模式：库负责把参数传进去
final request = useRequest(fetchUser);
request.run(123); // 内部效果接近 fetchUser(123)

// 闭包模式：库只负责“再执行一次这个函数”
final request = useRequestFn(() => fetchUser(userId.value));
request.refresh(); // 内部效果接近 (() => fetchUser(userId.value))()
```

对初学者来说，关键区别不是“函数”和“闭包”这几个字，而是：

- **参数模式**：请求参数放在 `run(...)` 里
- **闭包模式**：请求参数放在 `() => ...` 里面

这样做的问题有两个：

- **静态类型关系会被冲淡**。现在 `useRequest<TData, TParams>` 里，`params`、`defaultParams`、`cacheKey`、`loadMoreParams`、`onSuccess(data, params)` 这些能力是连在一起的。若 service 改成宽泛的 `Function`，这一整串类型约束都会变弱。
- **运行时分流在 Dart 里并不适合作为公开 API 的基础**。Flutter release/AOT 下 `dart:mirrors` 不可用；而且就算不谈反射，命名函数、匿名函数、捕获外部状态的闭包，在运行时看到的都是 callable 对象，API 设计也不该依赖“这个值看起来像哪种函数”去猜语义。

所以这里的选择是：

- `useRequest`：参数由 `run(params)` 传进来。
- `useRequestFn`：参数来自闭包捕获的外部状态。

这比“一个入口里自动猜”更明确，也能把类型检查保住。

### 闭包模式

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

**心智模型：条件即状态，状态变了就重新请求，请求永远读最新状态。**

- service 是零参闭包，每次 widget rebuild 都会重新创建，闭包捕获的
  `keyword.value` / `status.value` 天然是最新值。
- `refreshDeps` 里的值只用来做一件事：变了就触发一次重新执行闭包。
  它不向 service 传任何东西。
- 因为参数不经过 `params` 机制，"refreshDeps 复用上一次参数"的语义
  对闭包模式完全无感——这就是它稳的原因。

适用于：

- **搜索**：输入框内容变化自动搜（配 `debounceInterval`）
- **筛选**：状态 tab、下拉筛选、日期区间变化自动刷新列表
- **Provider / Riverpod（Hook 上下文）**：在 `HookWidget` / `HookConsumerWidget` 里，把
  `context.watch` / `ref.watch` 出来的条件写进闭包即可自动刷新

> **⚠️ 闭包模式是 Hook 入口**：`useRequestFn` 只能在 `HookWidget` /
> `HookConsumerWidget`（`hooks_riverpod`）里用。若你走的是纯 Provider 路径
> （`createUseRequestProvider` / `UseRequestBuilder`），service 在 provider
> 创建时就固定成 `Service<TData, TParams>`，没有"每帧重建闭包"这一环——
> 此时用 notifier 的 `refreshDeps(deps, action: ...)` 显式带最新参数重发，
> 等价于 Hook 侧的 `refreshDepsAction`（见下文 [参数模式的组合陷阱](#-参数模式--refreshdeps-的组合陷阱)）。

如果你写过 React 管理后台，这就是你熟悉的那套：

```tsx
// ahooks 等价写法，同一个心智模型
const { data } = useRequest(() => fetchOrderList(keyword, status), {
  refreshDeps: [keyword, status],
});
```

#### 闭包模式下的分页

`loadMoreParams` 在闭包模式下无意义（params 恒为 null）。
把 page 也放进外部状态即可：

```dart
final page = useState(1);

final result = useRequestFn(
  () => fetchList(page: page.value, keyword: keyword.value),
  options: UseRequestOptions(
    refreshDeps: [page.value, keyword.value],
  ),
);

// 翻页：
onNextPage: () => page.value++;
// 改筛选条件时记得回到第一页：
onKeywordChange: (v) { keyword.value = v; page.value = 1; }
```

### 参数模式

```dart
final result = useRequest<OrderDetail, int>(
  fetchOrderDetail,           // (orderId) => Future<OrderDetail>
  options: UseRequestOptions(manual: true),
);

// 用户点了某一行：
onTap: (order) => result.run(order.id);
```

**心智模型：参数是动作的一部分，每次动作显式带参。**

- service 显式声明参数类型，`run(params)` / `runAsync(params)` 每次传入。
- `refresh()` 会复用上一次 `run` 的参数原样重发——这在参数模式下是
  合理的："把刚才那次请求再来一遍"。
- 类型安全完整：`params`、`cacheKey`、`loadMoreParams`、`onSuccess`
  拿到的都是强类型参数。

适用于：

- **点击搜索**：用户点按钮才发请求，参数从表单收集
- **提交**：创建/更新/删除等动作，`manual: true` + `run(payload)`
- **手动刷新**：`refresh()` 重发上一次请求

#### ⚠️ 参数模式 + refreshDeps 的组合陷阱

**不要这样写**（这是最常见的错误用法）：

```dart
// ❌ 错误：以为 refreshDeps 变化会带上新的 defaultParams
final params = useMemoized(() => buildParams(status), [status]);
final result = useRequest(
  fetchList,
  options: UseRequestOptions(
    defaultParams: params,
    refreshDeps: [status],   // status 变了 → refresh() → 复用【旧】params！
  ),
);
```

`refreshDeps` 变化触发的是 `refresh()`，而 `refresh()` 的定义是
"用上一次请求的参数重发"。新算出来的 `defaultParams` 只在首次自动
请求时被读取，之后不会再被 `refreshDeps` 路径使用。上面这段代码里
`status` 切换后，请求带的还是旧 status。

还有一种更隐蔽的错法：**表面上在用参数模式，实际上请求参数来自闭包**。

```dart
// ❌ 能执行，但 run(params) 与真实请求条件已经脱钩
final keyword = useState('banana');

final result = useRequest<List<User>, String>(
  (_) => searchUsers(keyword.value),
  options: UseRequestOptions(manual: true),
);

result.run('apple');
```

这段代码里：

- `run('apple')` 记录下来的 params 是 `'apple'`
- service 真正发请求时读的是 `keyword.value`
- 如果此时 `keyword.value == 'banana'`，请求实际发出去的是 `banana`

于是 `onSuccess(data, params)` 里拿到的 `params` 是 `'apple'`，但服务端查询条件
其实是 `banana`。代码不会报错，语义却已经错位。遇到这种需求，要么改成真正的
参数模式 `useRequest(searchUsers)`，要么直接改成闭包模式 `useRequestFn(() => searchUsers(keyword.value))`。

#### `defaultParams` 和 `refreshDepsAction` 该怎么理解

这两个属性不是“参数自动跟着状态更新”的通用开关，作用范围都比较明确。

- `defaultParams`：主要用于**首次自动请求**。另外，在少数“框架需要一个参数，但当前没有可用的上一次参数”的路径里，它会作为后备参数使用，例如首次 `refresh()` / 首次 `refreshDeps` 触发前还没有成功记录过参数时。
- `refreshDepsAction`：它不是默认推荐写法，而是**参数模式下给依赖变化指定明确动作**。因为 `refreshDeps` 的默认行为是调用 `refresh()`，而 `refresh()` 天生就是“用上一次参数再请求一次”。

初学者可以这样记：

- `defaultParams` 像“页面第一次加载时先用哪份参数”
- `refreshDepsAction` 像“依赖变了以后，不要用默认动作，改成我自己指定这次怎么发”

换句话说：

- 依赖变了，而且**请求参数也要跟着变**：优先用 `useRequestFn`
- 依赖变了，但**参数本来就不该变**：直接用 `refreshDeps`
- 依赖变了，而且**你必须留在参数模式里自己决定新参数**：再写 `refreshDepsAction`

`refreshDepsAction` 常见于两类场景：

- 纯 Riverpod Provider / Builder 路径，没有 `useRequestFn` 这种“每次 rebuild 重建闭包”的入口
- 你明确要保留参数模式能力，例如 `loadMoreParams`、`cacheKey(params)`、`run(payload)` 这些都还要继续按强类型参数工作

如果确实需要参数模式 + 依赖自动刷新，用 `refreshDepsAction` 显式带新参数：

```dart
// ✅ 正确：refreshDepsAction 里自己决定用什么参数
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

但一般来说——**需要写 refreshDepsAction 的时候，先问自己是不是该用闭包模式**。
上面这坨 ref 中转代码，用 `useRequestFn` 一行就没了。

### refresh 与 refreshDeps

这两个名字都带 refresh，语义完全不同，值得单独讲清楚。

#### refresh()：同一份查询，再问一遍

```dart
result.refresh();   // = run(上一次的参数)
```

`refresh()` 不接受参数，永远复用上一次 `run`/`runAsync` 的参数。
它回答的问题是"**同样的条件，服务端现在的数据是什么**"，不是
"条件变了帮我用新条件查"。这与 ahooks 完全一致。

#### refreshDeps：外部世界变了，该重新问了

`refreshDeps` 数组里任何一项变化 → 默认触发 `refresh()`。

注意默认动作是 `refresh()`——所以它继承了"复用上一次参数"的语义。
这个设计**不是缺陷**，它对应的正确场景是：**依赖项和请求参数是两件事**，
依赖变了但参数没变，你要的只是"重新拿一次数据"。例如：

- **切换语言**：查询参数一个没变，变的是请求头里的 `Accept-Language`，
  原样重发拿到新语言的文案，正确。
- **重新登录 / 切换租户**：token/租户上下文在拦截器里，参数不变，重发即可。
- **手动刷新信号**：一个自增的 counter 放进 refreshDeps，参数不变。

而当"依赖项**就是**请求参数"时（筛选、搜索、翻页），复用旧参数就成了 bug。
这种场景请用闭包模式，让参数走闭包、refreshDeps 只当触发器。

#### 判断口诀

```
依赖变化后，参数需要跟着变吗？
├─ 需要 → 闭包模式 useRequestFn（或 refreshDepsAction）
└─ 不需要（参数不变，只是要新数据）→ 参数模式 + refreshDeps 直接用
```

### 完整示例（企业后台常见形态）

以下四个 Demo 都按企业管理后台的常见形态编写，可直接复制改造。

#### 1. CRUD（列表 + 新增 + 删除 + 编辑）

```dart
class UserManagePage extends HookWidget {
  const UserManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 列表：闭包模式，无条件参数，挂载即加载
    final list = useRequestFn(
      () => api.getUserList(),
    );

    // 新增：参数模式 + manual，成功后刷新列表
    final create = useRequest<void, CreateUserPayload>(
      api.createUser,
      options: UseRequestOptions(
        manual: true,
        onSuccess: (_, __) => list.refresh(),
      ),
    );

    // 删除：同上
    final remove = useRequest<void, int>(
      api.deleteUser,
      options: UseRequestOptions(
        manual: true,
        onSuccess: (_, __) => list.refresh(),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: list.refresh),
        ],
      ),
      body: ListView(
        children: [
          for (final user in list.data ?? const <User>[])
            ListTile(
              title: Text(user.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => remove.run(user.id),
              ),
            ),
        ],
      ),
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

要点：读操作用闭包模式；写操作（增删改）用参数模式 + `manual: true`，
`onSuccess` 里 `list.refresh()` 复用原查询条件刷新——这正是
"refresh 复用上一次参数"语义的正确用武之地。

#### 2. 分页（页码翻页表格）

```dart
class OrderTablePage extends HookWidget {
  const OrderTablePage({super.key});

  @override
  Widget build(BuildContext context) {
    final page = useState(1);
    final pageSize = useState(20);
    final status = useState<int?>(null);   // 顶部状态筛选

    final table = useRequestFn(
      () => api.getOrderPage(
        page: page.value,
        size: pageSize.value,
        status: status.value,
      ),
      options: UseRequestOptions(
        refreshDeps: [page.value, pageSize.value, status.value],
        keepPreviousData: true,   // 翻页时旧数据留在屏上，避免闪白
      ),
    );

    return Column(
      children: [
        StatusFilterTabs(
          value: status.value,
          onChanged: (v) {
            status.value = v;
            page.value = 1;       // 换筛选条件必须回第一页
          },
        ),
        Expanded(
          child: OrderDataTable(
            rows: table.data?.records ?? const [],
            loading: table.loading,
          ),
        ),
        PaginationBar(
          page: page.value,
          total: table.data?.total ?? 0,
          pageSize: pageSize.value,
          onPageChanged: (p) => page.value = p,
          onPageSizeChanged: (s) {
            pageSize.value = s;
            page.value = 1;
          },
        ),
      ],
    );
  }
}
```

要点：page/pageSize/status 全部是外部状态，全部进 `refreshDeps`；
任何一个变化自动带最新值重新请求。`keepPreviousData: true` 让翻页
体验平滑。**换筛选条件时手动把 page 归 1**——这是业务规则，库不猜。

#### 3. 无限加载（滚动到底自动追加）

无限加载需要"把每页结果追加到已有列表"，这依赖 `loadMoreParams` +
`dataMerger`，属于参数模式的地盘：

```dart
class MessageFeedPage extends HookWidget {
  const MessageFeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final result = useRequest<PageData<Message>, PageQuery>(
      api.getMessagePage,
      options: UseRequestOptions(
        defaultParams: const PageQuery(page: 1, size: 20),
        // 下一页参数：上一次参数 page + 1
        loadMoreParams: (last, _) => last.copyWith(page: last.page + 1),
        // 新页追加到已有列表
        dataMerger: (prev, next) => PageData(
          records: [...?prev?.records, ...next.records],
          total: next.total,
        ),
        hasMore: (data) =>
            data != null && data.records.length < (data.total ?? 0),
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final nearBottom =
            n.metrics.pixels >= n.metrics.maxScrollExtent - 200;
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
                : const Center(child: Text('没有更多了'));
          }
          return MessageTile(records[i]);
        },
      ),
    );
  }
}
```

要点：`loadMoreParams` 在参数模式下才有意义——它需要"上一次的参数"
来推导下一页，这里"复用上一次参数"恰好是分页的本质。

#### 4. 搜索 + 筛选 + refreshDeps（最容易踩坑场景的标准答案）

企业后台最典型的组合：搜索框 + 状态 tab + 分页表格，全自动刷新。

```dart
class CouponSearchPage extends HookWidget {
  const CouponSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final keyword = useState('');
    final statusTab = useState(0);          // 0=全部 1=可使用 2=待确认...
    final page = useState(1);

    const statusMap = [-1, 1, 2, 3, 4];     // tab 索引 → 接口 orderStatus

    final list = useRequestFn(
      // 所有条件从闭包读，永远是最新值
      () => api.getCouponList(
        page: page.value,
        size: 10,
        orderStatus: statusMap[statusTab.value],
        keyword: keyword.value.isEmpty ? null : keyword.value,
      ),
      options: UseRequestOptions(
        // 任何条件变化 → 自动重新请求（带最新条件）
        refreshDeps: [keyword.value, statusTab.value, page.value],
        // 输入搜索防抖，tab 快速切换也顺带去抖
        debounceInterval: const Duration(milliseconds: 300),
        keepPreviousData: true,
      ),
    );

    void resetToFirstPage() => page.value = 1;

    return Column(
      children: [
        SearchField(
          onChanged: (v) {
            keyword.value = v;
            resetToFirstPage();
          },
        ),
        StatusTabs(
          index: statusTab.value,
          onChanged: (i) {
            statusTab.value = i;
            resetToFirstPage();
          },
        ),
        Expanded(
          child: CouponListView(
            items: list.data?.records ?? const [],
            loading: list.loading,
          ),
        ),
      ],
    );
  }
}
```

对照错误写法再看一遍（真实项目里踩过的原样）：

```dart
// ❌ 参数模式 + refreshDeps：tab 切了，请求参数不变
final params = useMemoized(
  () => CouponListParams(orderStatus: statusMap[statusTab.value]),
  [statusTab.value],
);
final list = useRequest(
  api.getCouponList,
  options: UseRequestOptions(
    defaultParams: params,          // 只有第一次请求用它
    refreshDeps: [statusTab.value], // 之后每次都 refresh() 复用旧参数
  ),
);
```

症状：tab 高亮切换正常、请求也发出去了，但抓包发现 `orderStatus`
永远是上一个 tab 的值。修法：改成上面的闭包模式，或参数模式 +
`refreshDepsAction`（见上文"组合陷阱"一节）。

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
final http = DioHttpAdapter.withBaseUrl('https://jsonplaceholder.typicode.com');

// 创建 Service：参数使用 HttpRequestConfig（推荐）
final fetchUsers = createDioService<List<dynamic>>(
  http,
  transformer: (res) => (res.data as List<dynamic>?) ?? const [],
);

final result = useRequest<List<dynamic>, HttpRequestConfig>(
  fetchUsers,
  options: const UseRequestOptions(
    manual: true,
    // 可选：作为默认超时（当 config 未显式指定时才会生效）
    connectTimeout: Duration(seconds: 5),
    receiveTimeout: Duration(seconds: 15),
    sendTimeout: Duration(seconds: 15),
  ),
);

// 发起 GET
result.run(HttpRequestConfig.get('/users'));
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

// 方式二：在 HttpRequestConfig 中配置（单次请求，推荐）
final config = HttpRequestConfig.get(
  '/users',
  connectTimeout: Duration(seconds: 5),
  receiveTimeout: Duration(seconds: 15),
);

// 方式三：在 UseRequestOptions 中配置（仅当 TParams=HttpRequestConfig 时，会自动合并到 config）
final options = UseRequestOptions(
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

- `Service<TData, TParams>`：`Future<TData> Function(TParams params)`（`lib/src/types.dart`）
- `OnBefore` / `OnSuccess` / `OnError` / `OnFinally` 回调类型（`lib/src/types.dart`）

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

  // ========== 超时配置（v2.0 新增；当 TParams=HttpRequestConfig 时生效）==========
  Duration? connectTimeout,         // 连接超时
  Duration? receiveTimeout,         // 接收超时
  Duration? sendTimeout,            // 发送超时

  // ========== 加载与刷新 ==========
  Duration? loadingDelay,           // 延迟显示 loading（避免闪烁）
  bool refreshOnFocus = false,      // 应用获得焦点时自动刷新
  bool refreshOnReconnect = false,  // 网络恢复时自动刷新，需提供 reconnectStream
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
- 就绪态：`ready=false` 时阻止自动请求/轮询；但手动 `run/runAsync` 不受影响；设为 `true` 后再进入正常流程
- 依赖刷新：`refreshDeps` / `refreshDepsAction`（Hook 版自动监听 deps；Riverpod 版可通过 notifier 的 `refreshDeps(...)` 触发）——详细语义与选型见 [参数从哪来](#参数从哪来闭包模式参数模式与-refreshdeps)
- 缓存与复用：显式传入 `cacheKey` 开启缓存；`cacheTime` 控制缓存有效期（null 表示不过期），`staleTime` 超时后会在保留缓存的同时重新请求
- 并发隔离：`fetchKey` 将不同 key 的请求计数/取消令牌隔离；但状态仍是单态，只有最后一次 `run` 的 key（active key）会更新 UI，其它 key 的结果视为被覆盖
- 加载更多：提供 `loadMoreParams` 生成下一页参数、`dataMerger` 合并数据、`hasMore` 判定是否还有更多；`UseRequestResult` 暴露 `loadingMore`、`hasMore` 与 `loadMore`/`loadMoreAsync`
- 分页重置：`PaginationHelpers.pageParams(...)` 可通过 `shouldReset` 回调在条件变化时重置到 `startPage`
- 轮询策略：`pollingWhenHidden=false` 失焦暂停、前台恢复；`pausePollingOnError` 遇错暂停，若设置 `pollingRetryInterval` 会在该间隔后自动尝试恢复；`refreshOnReconnect` + `reconnectStream` 可在网络恢复时刷新
- 轮询：`pollingInterval` 不为 `null` 时开启（Hook 版自动轮询；Riverpod 版 additionally 提供 `startPolling()`/`stopPolling()`）
- 频率控制：`debounceInterval` / `throttleInterval` 二选一
- 重试：`retryCount` 与 `retryInterval` 控制失败重试
- 延迟 loading：`loadingDelay` 控制进入 loading 的延时，避免闪烁
- 刷新策略：`refreshOnFocus`、`refreshOnReconnect`（后者需外部提供 reconnectStream）
- 取消令牌：可传入自定义 `CancelToken` 与 `cancel()` 配合使用
- 生命周期回调：`onBefore`、`onSuccess`、`onError`、`onFinally`

### 返回对象：`UseRequestResult<TData, TParams>`（`lib/src/types.dart`）

- 状态字段：`loading`、`data`、`error`、`params`
- 方法：
  - `runAsync(params)` / `run(params)`
  - `refreshAsync()` / `refresh()`（使用上一次参数）
  - `mutate((old) => new)` 直接变更数据
  - `cancel()` 取消进行中的请求

### 内部状态：`UseRequestState<TData, TParams>`（`lib/src/types.dart`）

- 字段：`loading`、`data`、`error`、`params`、`requestCount`
- 说明：用于内部状态维护与 Riverpod 暴露；一般无需直接操作

### Riverpod 能力（`lib/src/use_request_riverpod.dart`）

- `UseRequestNotifier<TData, TParams>`：核心状态机（请求、轮询、重试、取消等）见对应类定义
- `createUseRequestProvider<TData, TParams>()`：Provider 工厂
- `UseRequestBuilder<TData, TParams>`：Builder 组件
- `UseRequestMixin<TData, TParams>`：在 `ConsumerWidget` 中获得 Hook 风格 API

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
- 参数来源先想清楚：依赖变化需要带新参数就用 `useRequestFn`（闭包模式），依赖变化只是"重新问一遍"就用参数模式 + `refreshDeps`（见 [参数从哪来](#参数从哪来闭包模式参数模式与-refreshdeps)）
- ProviderScope：仅 Riverpod Provider 路径（`createUseRequestProvider` / `ConsumerWidget`）需要；`UseRequestBuilder` 本身不需要
- 回调与副作用：首推在 `onSuccess` 中做后续处理，避免在 UI 中到处散落逻辑
- 刷新与轮询：合理设置间隔，避免高频请求造成压力；必要时结合节流
- 错误处理：统一在 `onError` 或 UI 层进行错误展示与埋点
- 取消请求：页面切换或重复点击场景建议及时调用 `cancel()`

---

## 真实示例（摘自示例文件）

- 完整展示站（由易到难，含 GitHub API + Record 解构）见：`website/lib/main.dart`
- 两个最小可复制用法见：`example/lib/main.dart`
- 旧 Demo 场景盘点见：`example-inventory.zh-CN.md`

---

## Flutter Web Demo 与渲染器选择

示例 App 支持 Flutter Web，可用不同渲染器对比首屏与包体：

```bash
cd website
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
  - A：不需要。`UseRequestBuilder` 内部直接管理 `UseRequestNotifier`，本身不依赖 Riverpod 容器。
- Q：什么时候必须加 `ProviderScope`？
  - A：当你用 `createUseRequestProvider`、`ConsumerWidget`、`WidgetRef` 这类 Riverpod Provider 路径时需要；纯 Hook 路径和 `UseRequestBuilder` 不需要。
- Q：Hook 版如何在普通 `StatelessWidget` 使用？
  - A：Hook 版需要 `HookWidget` 或在 `HookBuilder` 环境中使用。
- Q：`refreshOnReconnect` 是否生效？
  - A：生效，但需要同时提供 reconnectStream；库不内置跨平台网络检测。
- Q：为什么筛选 tab 切换了，接口参数还是旧的？
  - A：大概率是参数模式下只写了 `refreshDeps` 没写 `refreshDepsAction`——`refreshDeps` 触发的默认 `refresh()` 会复用上一次参数。改用闭包模式 `useRequestFn`，或参照 [组合陷阱](#-参数模式--refreshdeps-的组合陷阱) 手写 `refreshDepsAction`。

---

## 参考实现位置

### 核心入口
- `useRequest` / `useRequestFn`：`lib/src/use_request.dart`
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

- 展示站已包裹 `ProviderScope`（`website/lib/main.dart`），这样 Provider 示例可以直接运行；但这不是 `UseRequestBuilder` 的前置条件
- 最小示例与展示站都依赖本地包路径，在仓库内运行可实时验证库改动
- 库统一导出入口： lib/use_request.dart:1 （项目中引用 package:use_request/use_request.dart ）
