# use_request 演进 TodoList

基线：0.6.3 / `846fd04`，目标版本 0.7.0。保留现有公开 API，不新增独立适配 package 或远端仓库。初段实现：GPT-5.6 Sol（high）；后段接手、回归修复与收尾：GPT-6 Astra；独立 Code Review：另一 GPT-6 Astra。用户于 2026-09-11 授权最终提交、推送并发布主包 0.7.0，由根代理在审查闭环后执行。

- [x] 1. 精简中文/英文 README：突出异步状态管理定位，提供闭包与显式参数两个最小示例，详细 API 和 Dio 接入说明移入 doc，修正文档链接。
- [x] 2. 整理 Example：保留最小可运行用法；完整展示站移到独立目录；盘点旧 Demo 的独有场景后删除重复集合；控制 pub.dev 归档内容。
- [x] 3. 统一请求执行：Hook、Notifier、Builder 复用内部控制逻辑；保留现有公开 API、最新 service/options、ready/deps、防抖、轮询和缓存行为。
- [x] 4. 完善契约：同 cacheKey 的已挂载实例同步数据；透传 shouldRetry；增加聚焦刷新最小间隔；明确普通 Future、Dio、共享 pending 的取消/卸载边界，并验证实际实现。
- [x] 5. 补充验证与 CI：执行库、最小 Example、展示站测试；覆盖 lib 变更后的 Web 部署；完成静态分析、Web 构建和发布清单检查。
- [x] 6. 提供迁移方案：说明未来 Dio/Riverpod 可选 package 的职责、旧入口兼容路径、版本边界；不把拆导出文件描述成解除依赖。
- [x] 7. GPT-6 Astra 独立 Code Review；GPT-6 Astra 修复发现；复核并记录剩余限制。
- [ ] 8. 根代理按用户授权提交、打 v0.7.0 tag、推送、发布 pub.dev 并验证远端版本。

## 验收约束

- 保护现有审查文档与工作区变动；发布遵循用户最新的 0.7.0 授权。
- 默认使用 FVM。若本项目 FVM 未配置/不能执行，记录原因并使用已验证的项目 SDK，不静默升级依赖。
- 原有 115 项库测试应保持通过；新增测试验证用户可观察的契约，避免只复述实现。
- 每项实际完成后再勾选，记录验证命令、结果和未覆盖边界。
- 不为解耦新增通用插件框架；优先复用现有工具和 Flutter/Dart 标准能力。

## 执行与验证记录

- FVM 未配置且此前本机调用无输出；使用已验证的 `/Users/aminoas/Downloads/flutter/bin/flutter`（Dart 3.13）。未运行 `pub upgrade`；使用现有 SDK 执行 `pub get`，示例/展示站锁文件随依赖精简、SDK 约束解析及 path 包版本更新。
- 库 `flutter test`：133 项通过（原 115 项保留），日志 `/tmp/astra-final-root-test.log`。新增契约检查包括缓存同步/清空、共享消费者取消、retry、focus、ready/deps、loadingDelay，以及共享分页只合并一次且保留 pending mutate。
- 库、example、website 的 `flutter analyze` 均无问题；日志 `/tmp/astra-final-root-analyze.log`、`/tmp/astra-final-example-analyze.log`、`/tmp/astra-final-website-analyze.log`。
- example `flutter test`：1 项通过；website：94 项通过，保留迁移前的断言。日志 `/tmp/astra-final-example-test.log`、`/tmp/astra-final-website-test.log`。
- 展示站交互测试沿用原有 HTTP mock、布局溢出过滤与异常队列清理；日志中的 mock 头像解码错误不影响这些交互断言。上述测试不等同于图片、布局或真机视觉验收。
- example `flutter build web --release` 与 website `flutter build web --release --base-href /use_request_dio/` 均成功；日志 `/tmp/astra-final-example-build.log`、`/tmp/astra-final-website-build.log`。SDK 提示缺少未使用的 CupertinoIcons 字体，不影响构建；本轮未做真机或浏览器视觉验收。
- CI 增加两个子项目的独立分析/测试及最小 Web 构建；Pages 改用 website，监听 lib、website、依赖和工作流变更，保留原 base-href 与部署权限。
- 根代理独立核验 15 份文档的 Markdown 本地链接，零缺失；原 example 除 11 个旧 demo 文件外均完整迁入 website。旧 HTTP POST/PUT/DELETE 独有场景已保留于双语 Dio 文档。展示站仍是原完整展示的迁移，内嵌源码文本去重留待后续。
- 0.7.0 `flutter pub publish --dry-run` 检查归档为 117 KB，保留最小 example，排除 website、build、锁文件和内部审查/Todo。日志 `/tmp/astra-final-publish-dryrun.log`；唯一警告为尚未提交的 Git 修改，需根代理提交后重跑至零警告再实发。
- 独立 Astra 复核已闭环：mutate(null) 不误清 pending、不保留 null 缓存条目；clear 结束 loadingDelay；ready 下降同帧不误执行；最后消费者退出停止 retry；共享分页不重复合并。最终未发现剩余产品阻塞。
- 尚待根代理执行授权的提交、tag、推送、pub.dev 发布及远端验证；本文件勾选的是演进与 review 工作，不代表发布已完成。
