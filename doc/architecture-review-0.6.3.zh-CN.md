# use_request 0.6.3：定位与演进审查

审查日期：2026-09-10。基线：本仓库 0.6.3。参考 ahooks 的 useRequest 官方文档与官方仓库；GitHub 源码按本次读取的 master 分支比较，不等同于逐项承诺兼容某个 npm 发布版本。

## 本次执行的提示词

> 以当前 0.6.3 为基线，对照 ahooks 3 的 useRequest，而非照搬整个 React Hooks 库。审查产品定位、公开 API、请求状态机、HTTP 耦合、缓存与取消语义、示例组织和发布流程。逐项区分“已有能力、真实缺口、可精简部分”，给出代码证据、目标边界、兼容迁移顺序与验收标准。特别区分同仓分目录、独立 package 和独立仓库的作用，形成可执行的演进建议。此轮交付审查与方案；拆仓、删除公开接口和重新发布属于后续实施。

## 结论

项目已具备自动/手动请求、ready、依赖刷新、轮询、防抖、节流、重试、延迟 loading、缓存、取消和 mutate，基础功能并不匮乏。优先事项是明确产品边界、统一行为和减少维护重复。

建议定位：面向 Flutter 的异步任务状态管理库，优先提供易用的 Hooks API，支持任意 Future service；HTTP 客户端、业务响应解析和认证策略由调用方或可选适配器负责。

如果最终目标是覆盖整个 ahooks，则还涉及大量状态、生命周期、事件、存储等 Hooks。这是更大的产品方向，不能通过继续给 UseRequestOptions 添加字段来实现。当前先做好 useRequest 这一块。

## 现状与证据

| 观察 | 当前代码 | 意义 |
| --- | --- | --- |
| 两套完整请求实现 | `lib/src/use_request.dart` 1,099 行；`lib/src/use_request_riverpod.dart` 1,231 行 | 文件还包含注释和适配逻辑，不能全部算重复；但 fetch、pending、缓存、取消和回调分支明显重复维护 |
| HTTP 已进入状态层 | `lib/src/types.dart` 导入 Dio；两个请求实现识别 HttpRequestConfig、复制超时与 CancelToken | 移动 Dio 文件或修改 export 无法解除耦合 |
| 多种入口与底层工具全部导出 | `lib/src/use_request_exports.dart` | Hook、Provider、Builder、Mixin 和工具类混在统一入口，用户难以区分推荐 API 与实现细节 |
| 两套 Demo 共存 | `example/lib/main.dart` 3,859 行；`example/lib/demo/` 为旧演示集合 | main 和当前 example/test 没有引用旧集合，但 README 仍推荐它 |
| 示例中再次存储源码文本 | main.dart 的 `_sourceLevel1` 等字符串，以及动态源码拼接 | 同一行为同时维护可执行代码与展示文本，增加不一致风险 |
| README 承担整站职责 | 中文 1,258 行、英文 978 行 | 新用户须从大量参数解释和 HTTP 配置中寻找最小用法 |
| 主 CI 没运行示例测试 | `.github/workflows/dart.yml` 安装、分析 example，但只在根目录执行测试 | 已有 example/test 不能成为稳定的合并保障 |
| Web 发布触发范围缺口 | `.github/workflows/deploy-pages.yml` paths 未包含 `lib/**` | 仅修改库代码时，依赖本地 path 的在线 Demo 不会自动更新 |

以上行数包含注释与空行，只用于说明维护规模，不能用于断言运行时包体或性能损耗。

## 与 ahooks useRequest 相比的真实缺口

### 1. 缓存共享只有一部分

当前支持静态缓存、pending Future 去重、staleTime、cacheTime、手动清除和 LRU 容量控制。缺少同 cacheKey 的实例间订阅：RequestCache.set 只更新 Map，组件 A 的 mutate 不会主动更新已挂载的组件 B。

RequestCacheEntry 只有 data 和 timestamp，没有 params；主 options 也没有可替换缓存存储的入口。ahooks 提供同键数据同步、参数缓存和自定义 getCache/setCache。

优先补同键同步及其取消/销毁契约；参数恢复和持久化接口按实际使用场景推进。跨账号隔离仍需业务定义缓存键/清理策略，不能由请求库猜测。

### 2. 通用 Future 与实际重试策略不一致

Service 的公开签名是任意 Future，但 `utils/retry.dart` 的默认策略仅接受部分 DioException；其他异常返回 false。底层 RetryConfig 有 shouldRetry，UseRequestOptions 却没有透传此策略。

因此“设置 retryCount 就会重试任意异步任务”不是当前真实契约。应允许调用方指定可重试错误，将 HTTP 分类留给 Dio 接入层；保留取消不重试的约束，不默认重试所有写操作。

### 3. 聚焦刷新缺少最小间隔

当前 AppFocusManager 能处理生命周期/页面可见性，但没有类似 ahooks focusTimespan 的刷新冷却。可增加最小刷新间隔以避免短时间前后台切换导致重复刷新，不必增加另一套网络客户端。

### 4. 取消的对外契约需要定清楚

应分别说明：取消 UI 结果接收、使 runAsync 的等待结束、真正中止底层 I/O。普通 Future 无法被库直接中断；Dio 需要每次调用独立的取消通道。当前自动注入 CancelToken 的路径依赖 HttpRequestConfig。

提取核心时必须定义过期请求、卸载、用户取消以及共享 pending 的行为。尤其要验证 A/B 共用请求时，A 退出是否应终止 B 仍需要的请求。不能简单把 Dio CancelToken 换个类名就视为解耦完成。

### 5. 模块组合与平台适配需要收敛

ahooks 的 Hook 包装维护一个 Fetch 实例，轮询、缓存等通过插件参与流程。当前 Hook 和 Notifier 分别编排同类逻辑。

优先提取一个内部请求控制器供两种适配层复用，保留现有工具类。先统一成功、失败、pending、取消及配置更新规则；没有外部扩展需求时，不发布通用插件框架。

分页也是组合边界：当前已有 loadMoreParams/dataMerger/hasMore，不算缺失。但分页会同时影响普通 fetch 与轮询。可逐步将页码、合并、重置策略移到复用请求控制器的分页组合层；不要为此复制第三套请求状态机。ahooks 的 usePagination 本身也是基于 useRequest 的组合。

## HTTP 和 Web 应如何处理

`DioHttpAdapter` 是跨平台 HTTP 适配器，并非 Web 专属功能。它的 GET/POST/上传/下载等便捷方法与 Dio 的能力重叠；连接超时、上传文件路径等不应占据通用异步库的主要 API。

目标边界：

- 核心负责调用 service、状态、竞争处理、缓存、调度、回调。
- Dio 接入负责请求配置、错误分类和真实 I/O 取消，尽量调用 Dio 原生能力。
- service 负责接口路径、鉴权上下文、JSON/业务响应转换。
- Flutter 平台适配负责生命周期与可见性。

`package:web` 目前用于监听 document.visibilitychange，使后台暂停轮询等行为生效。它不是 HTTP 包装，不能和 DioHttpAdapter 一起删除；若删除其依赖，需要先提供等效且经过验证的平台实现。

0.6.x 保持公开 API 兼容，先降低文档中适配器的地位。若要解除对 Dio、Riverpod 的强制依赖，再拆成独立 package。仅增加 `dio.dart`、`riverpod.dart` 导出入口不能减少 pubspec 的必需依赖。

## Example 是否独立仓库

ahooks 仓库本身包含 docs、example，以及 hook 目录下的文档和 demo。Dart 也明确推荐 example/。问题不在于示例与源码同仓，而在于两套演示、过长入口和发布范围混杂。

| 方案 | 解决的问题 | 代价与判断 |
| --- | --- | --- |
| 同仓分目录 | 清晰区分库、最小示例、展示站 | 当前最合适；同一修改可同时验证库和示例 |
| 同仓多个 package | 可选依赖、独立公开 API 和发布单元 | Dio/Riverpod 真正可选时采用；需要版本协调 |
| 独立 Demo 仓库 | 单独开发/部署展示站、验证已发布版本 | 需处理同步升级与跨仓联调；不解决库内部的 HTTP 耦合 |

建议先采用以下目录职责，名称为方案示意：

```text
lib/          稳定入口和内部实现
test/         库行为与适配契约测试
example/      最小、可直接复制的用法
website/      单一完整演示站及其测试、部署配置
doc/          逐功能文档、迁移说明、设计约定
```

主示例优先展示 `useRequestFn(() => api.fetchUsers())`，另给一个 `manual + run(params)` 示例。完整展示站按功能组织短示例，复用真实源码作为展示内容；删除旧集合前盘点其独有场景并迁移需要的内容。

如果你希望展示站独立仓库，可将 website/ 整体迁出并依赖已发布版本；库中仍保留小型 example/。其依赖更新、CI 和 Pages 路径要一起调整。

发布包范围与仓库边界分别控制。可以用 .pubignore 排除展示站，而保留最小示例。example/ 与根 lib/ 分离，不会因为出现在发布包中就自动编译进使用方 App；发布归档体积与 App 编译体积是两个指标。

## 推荐实施顺序与验收

1. **先整理文档和演示，不改请求行为。** 主 README 保留定位、安装、两个最小示例和导航；HTTP 教学移入可选集成文档。展示站仅保留一套实现；在 CI 显式执行示例测试，修正仅 lib 变化不部署的问题，dry-run 验证发布文件清单。验收：旧文档入口可迁移、示例测试通过、部署产物引用本次库代码。
2. **再统一内部请求控制器。** 保留 Hook、Provider、Builder 的外部入口，使它们委托同一执行流程。验收：同一组契约场景覆盖各适配层，原有测试通过；核心流程不再重复维护。兼容性重构阶段可暂时保留 Dio 依赖。
3. **明确契约并补高价值缺口。** 先缓存同键同步、通用重试策略、聚焦刷新间隔，再按需求提供缓存后端。验收：两组件同键 mutate 同步；一般 Future 可使用指定重试规则；快速前后台切换有刷新上限；缓存命中、pending、卸载、取消与回调顺序有自动化检查。
4. **在明确的兼容迁移版本中拆可选依赖。** 让 Dio/Riverpod 成为独立 package，并处理旧导出、废弃项和迁移文档；不预设这些候选包名已可注册。验收：只安装主包的最小消费者不再强制依赖 Dio/Riverpod；各适配器独立完成发布校验，现有用户有可执行迁移示例。

版本边界：0.6.x 优先兼容整理；删除公开字段、迁移包或改变取消语义，应安排明确标注破坏性变化的后续版本。此方案不要求下一版同时完成全部阶段。

## 证据与范围

- 本次读取当前源码、导出、pubspec、README、两套示例与两个 workflow；未修改库行为或执行拆仓。
- 上一轮发布已验证 115 项库测试通过。本轮是架构审查，没有重新运行测试或做运行时性能测量。
- 新发现的契约差异按源码判断；后续实现前应补相应行为检查，不能把静态推断当成真机性能验收。

参考来源：

- [ahooks useRequest 官方入口](https://ahooks.js.org/hooks/use-request/index)
- [ahooks useRequest 实现](https://github.com/alibaba/hooks/blob/master/packages/hooks/src/useRequest/src/useRequestImplement.ts)
- [ahooks 缓存文档](https://github.com/alibaba/hooks/blob/master/packages/hooks/src/useRequest/doc/cache/cache.en-US.md)
- [ahooks 聚焦刷新文档](https://github.com/alibaba/hooks/blob/master/packages/hooks/src/useRequest/doc/refreshOnWindowFocus/refreshOnWindowFocus.en-US.md)
- [ahooks usePagination 实现](https://github.com/alibaba/hooks/blob/master/packages/hooks/src/usePagination/index.ts)
- [ahooks 仓库目录](https://github.com/alibaba/hooks)
- [Dart 包布局](https://dart.dev/tools/pub/package-layout)
- [Dart 发布说明](https://dart.dev/tools/pub/publishing)
