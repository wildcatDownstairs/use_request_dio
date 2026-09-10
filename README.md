简体中文 | [English](README_EN.md)

# useRequest

面向 Flutter 的异步任务状态管理库，提供自动/手动执行、loading/error/data、刷新、轮询、防抖、节流、重试、缓存、取消和本地数据更新。service 可以是任意 `Future`；Dio 与 Riverpod 是当前 0.7.0 的内置集成。

## 安装

```yaml
dependencies:
  use_request: ^0.7.0
```

## 闭包模式

筛选条件或页面状态变化时，优先使用 `useRequestFn`：

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

## 显式参数模式

按钮、提交或搜索等一次性动作使用 `run(params)`：

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

`refreshDeps` 只决定何时刷新；参数模式的 `refresh()` 会复用最近一次参数。条件本身就是参数时使用闭包模式。

## 文档与示例

- [完整中文指南](doc/guide.zh-CN.md)
- [API、缓存、重试与取消契约](doc/contracts.zh-CN.md)
- [Dio 可选接入说明](doc/dio-integration.zh-CN.md)
- [未来 Dio/Riverpod 拆包方案](doc/package-migration.zh-CN.md)
- [给代码 Agent 的接入说明](doc/llm-agent-quickstart.zh-CN.md)
- [最小可复制示例](example/lib/main.dart)
- [完整 Web 展示站](website/lib/main.dart) · [在线 Demo](https://wildcatdownstairs.github.io/use_request_dio/)

```dart
import 'package:use_request/use_request.dart';
```

0.7.0 保持现有统一入口和公开 API。主包目前仍直接依赖 Dio、flutter_hooks、Riverpod 与 Web 可见性支持；仅调整导出文件不会让这些依赖变为可选。

## 验证

```bash
flutter analyze
flutter test
cd example && flutter test
cd ../website && flutter test && flutter build web
```

许可证见 [LICENSE](LICENSE)。
