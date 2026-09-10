# 未来可选依赖拆包方案

[English](package-migration.en.md)

本轮是 0.7.0 兼容演进：统一请求状态机、整理示例并明确契约。Dio、Riverpod、flutter_hooks 和 Web 可见性支持仍在主包依赖中；未新建独立适配包或仓库，本次仍发布主包。拆 export 文件不能解除 pubspec 依赖。

## 后续边界

| 单元 | 职责 |
| --- | --- |
| 核心与 Flutter Hook 接入 | service 调用、状态、竞争隔离、缓存、调度和生命周期；底层控制器不依赖 Riverpod 的 StateNotifier 或 Dio token |
| Dio 可选 package | HTTP 配置、Dio 错误分类、token 及 transport 取消桥接 |
| Riverpod 可选 package | Provider/Notifier 接入核心与销毁生命周期 |
| website | 同仓完整演示与部署，验证本地 path 依赖；可后续独立仓库，但不能借此解除库依赖 |

包名只是职责占位，需先核实注册可用性。不要为这一方案先加入通用插件框架。

## 迁移顺序与版本

1. 保持 0.7.0 旧统一入口和公开 API；文档优先任意 Future service。
2. 在后续明确标注破坏性变化的版本中，将当前基于 StateNotifier 的核心改为与 Dio/Riverpod 无关的控制器，并迁移专属公开类型；提供从旧 import 到新 package 的逐项对照。
3. 可提供过渡兼容 facade 重新导出旧入口；它仍依赖各适配包，不能宣称 facade 消费者已经摆脱依赖。
4. 用真实最小消费者只安装核心，检查依赖图不含 Dio/Riverpod；分别验证 Hook、Dio、Riverpod 消费者的分析、测试和构建。
5. 对每个候选包执行发布 dry-run、版本约束与迁移示例检查后，再决定发布；独立仓库不是前提。

缓存持久化、参数恢复、分页组合拆分和完整 ahooks 的其他 Hook 集合均需要独立需求与验收，不在本次演进中提前实现。
