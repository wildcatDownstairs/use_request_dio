import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:use_request/use_request.dart';

void main() {
  runApp(const ProviderScope(child: UseRequestShowcaseApp()));
}

const String _githubBaseUrl = 'https://api.github.com';
const Map<String, dynamic> _githubHeaders = {
  'Accept': 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'use-request-showcase',
};

/// useRequest 渐进式展示站点。
///
/// 页面目标：
/// 1. 所有示例都使用 GitHub 公共 API。
/// 2. 示例从简单到复杂，覆盖常见到高级能力。
/// 3. 每个示例支持直接看到效果，并可展开源码。
/// 4. 提供可交互的 Options 控制面板，便于试参。
class UseRequestShowcaseApp extends StatelessWidget {
  const UseRequestShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0EA5A4),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'useRequest Progressive GitHub Showcase',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF0F5FB),
        fontFamily: 'Avenir',
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const ProgressiveExamplePage(),
    );
  }
}

class ProgressiveExamplePage extends StatefulWidget {
  const ProgressiveExamplePage({super.key});

  @override
  State<ProgressiveExamplePage> createState() => _ProgressiveExamplePageState();
}

class _ProgressiveExamplePageState extends State<ProgressiveExamplePage> {
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;

  late final List<_DemoSection> _sections = [
    _DemoSection(
      key: GlobalKey(),
      level: 'Level 1',
      title: '基础自动请求 + 状态三态',
      subtitle: 'manual=false + ready + refreshDeps + loadingDelay',
      description: '默认自动请求 GitHub 用户资料，展示 loading/error/data 的最小闭环。',
      tags: const ['manual', 'ready', 'defaultParams', 'refreshDeps'],
      initialSourceCode: _sourceLevel1,
      demoBuilder: (onSourceChanged) =>
          _BasicAutoRequestDemo(onSourceChanged: onSourceChanged),
    ),
    _DemoSection(
      key: GlobalKey(),
      level: 'Level 2',
      title: '搜索频率控制（防抖 / 节流）',
      subtitle: 'debounce / throttle + keepPreviousData + loadingDelay',
      description: '输入仓库关键字后自动搜索，并用开关实时调节请求节奏。',
      tags: const ['debounceInterval', 'throttleInterval', 'keepPreviousData'],
      initialSourceCode: _sourceLevel2,
      demoBuilder: (onSourceChanged) =>
          _SearchRateControlDemo(onSourceChanged: onSourceChanged),
    ),
    _DemoSection(
      key: GlobalKey(),
      level: 'Level 3',
      title: '轮询 + 重试 + 超时 + 取消',
      subtitle: 'polling / retry / timeout / cancel 全链路演示',
      description: '持续观察仓库指标，支持错误重试、超时控制和手动暂停/恢复轮询。',
      tags: const [
        'pollingInterval',
        'retryCount',
        'connectTimeout',
        'cancelToken',
      ],
      initialSourceCode: _sourceLevel3,
      demoBuilder: (onSourceChanged) =>
          _PollingRetryDemo(onSourceChanged: onSourceChanged),
    ),
    _DemoSection(
      key: GlobalKey(),
      level: 'Level 4',
      title: 'Options 全配置实验台',
      subtitle: '按功能分组覆盖几乎全部 UseRequestOptions',
      description: '通过分组开关与滑杆统一调参，验证从基础配置到并发加载更多的组合行为。',
      tags: const ['cache', 'fetchKey', 'loadMoreParams', 'callbacks'],
      initialSourceCode: _sourceLevel4,
      demoBuilder: (onSourceChanged) =>
          _OptionsWorkbenchDemo(onSourceChanged: onSourceChanged),
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(int index) {
    setState(() {
      _selectedIndex = index;
    });
    final context = _sections[index].key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1080;

    return Scaffold(
      body: Stack(
        children: [
          const _DecorativeBackdrop(),
          SafeArea(
            child: Row(
              children: [
                if (isDesktop)
                  SizedBox(
                    width: 292,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 8, 18),
                      child: _GlassPanel(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSidebarHeader(context),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _sections.length,
                                itemBuilder: (context, index) {
                                  final section = _sections[index];
                                  final selected = _selectedIndex == index;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () => _scrollToSection(index),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          color: selected
                                              ? const Color(0x3328C5B8)
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: selected
                                                ? const Color(0xFF27B6A9)
                                                : const Color(0x33FFFFFF),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              section.level,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: selected
                                                    ? const Color(0xFF0F766E)
                                                    : const Color(0xFF64748B),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              section.title,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: selected
                                                    ? const Color(0xFF0F4D54)
                                                    : const Color(0xFF1E293B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Scrollbar(
                    controller: _scrollController,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        isDesktop ? 14 : 16,
                        18,
                        isDesktop ? 22 : 16,
                        26,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHero(context),
                          if (!isDesktop) ...[
                            const SizedBox(height: 14),
                            _buildTopNav(),
                          ],
                          const SizedBox(height: 16),
                          ..._sections.asMap().entries.map((entry) {
                            final index = entry.key;
                            final section = entry.value;
                            return Padding(
                              key: section.key,
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _DemoSectionCard(
                                section: section,
                                index: index,
                                isSelected: _selectedIndex == index,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5A4), Color(0xFF22D3EE)],
                ),
              ),
              child: const Text(
                'useRequest',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: const Color(0x3328C5B8),
              ),
              child: const Text('GitHub API', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '渐进式示例导航',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'useRequest Progressive Demo · GitHub Public API',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F766E),
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '从基础请求到全量 Options 实验台',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF102A43),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '每个示例默认先展示运行效果，底部面板可展开查看源码（含关键字高亮）。\n右侧示例均为真实 GitHub REST API 请求。',
            style: TextStyle(
              height: 1.42,
              color: Color(0xFF475569),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _TopBadge(label: '自动/手动请求'),
              _TopBadge(label: '防抖/节流'),
              _TopBadge(label: '轮询/重试/超时'),
              _TopBadge(label: '缓存/并发/加载更多'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopNav() {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _sections.asMap().entries.map((entry) {
            final index = entry.key;
            final section = entry.value;
            final selected = _selectedIndex == index;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: selected
                      ? const Color(0xFF0EA5A4)
                      : const Color(0x33FFFFFF),
                  foregroundColor: selected
                      ? Colors.white
                      : const Color(0xFF0F172A),
                ),
                onPressed: () => _scrollToSection(index),
                child: Text('${section.level} · ${section.title}'),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DemoSection {
  const _DemoSection({
    required this.key,
    required this.level,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.tags,
    required this.initialSourceCode,
    required this.demoBuilder,
  });

  final GlobalKey key;
  final String level;
  final String title;
  final String subtitle;
  final String description;
  final List<String> tags;
  final String initialSourceCode;
  final Widget Function(ValueChanged<String> onSourceChanged) demoBuilder;
}

class _DemoSectionCard extends StatefulWidget {
  const _DemoSectionCard({
    required this.section,
    required this.index,
    required this.isSelected,
  });

  final _DemoSection section;
  final int index;
  final bool isSelected;

  @override
  State<_DemoSectionCard> createState() => _DemoSectionCardState();
}

class _DemoSectionCardState extends State<_DemoSectionCard> {
  late String _sourceCode = widget.section.initialSourceCode;
  String? _queuedSourceCode;
  bool _sourceFlushScheduled = false;

  void _handleSourceChanged(String code) {
    if (_sourceCode == code || _queuedSourceCode == code) return;
    _queuedSourceCode = code;
    if (_sourceFlushScheduled) return;

    _sourceFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sourceFlushScheduled = false;
      final nextCode = _queuedSourceCode;
      _queuedSourceCode = null;
      if (!mounted || nextCode == null || nextCode == _sourceCode) return;
      scheduleMicrotask(() {
        if (!mounted || nextCode == _sourceCode) return;
        setState(() {
          _sourceCode = nextCode;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              gradient: LinearGradient(
                colors: [
                  widget.index.isEven
                      ? const Color(0x3315B4C7)
                      : const Color(0x33239BEA),
                  const Color(0x19FFFFFF),
                ],
              ),
              border: Border(
                bottom: BorderSide(
                  color: widget.isSelected
                      ? const Color(0xFF31B8AC)
                      : const Color(0x33A7B2C5),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _TopBadge(label: widget.section.level),
                    Text(
                      widget.section.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF526175),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.section.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.section.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.section.tags
                      .map((tag) => _OptionTag(label: tag))
                      .toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.section.demoBuilder(_handleSourceChanged),
                const SizedBox(height: 14),
                _SourceCodePanel(code: _sourceCode),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Level 1：自动请求与状态三态。
///
/// 这是最小的 useRequest 闭环：
/// - `manual: false` 自动请求
/// - `ready` 控制是否放行请求
/// - `refreshDeps` 监听用户名变化自动刷新
class _BasicAutoRequestDemo extends HookWidget {
  const _BasicAutoRequestDemo({required this.onSourceChanged});

  final ValueChanged<String> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final username = useState('octocat');
    final ready = useState(true);
    final loadingDelayMs = useState(120.0);
    final logs = useState<List<String>>(<String>[]);

    useEffect(() {
      onSourceChanged(
        _buildLevel1Source(
          username: username.value,
          ready: ready.value,
          loadingDelayMs: loadingDelayMs.value.toInt(),
        ),
      );
      return null;
    }, [username.value, ready.value, loadingDelayMs.value.toInt()]);

    void pushLog(String text) {
      logs.value = <String>[
        '${_clockNow()}  $text',
        ...logs.value,
      ].take(6).toList();
    }

    final adapter = useMemoized(
      () => DioHttpAdapter.withBaseUrl(_githubBaseUrl),
    );
    final service = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        adapter,
        transformer: (response) {
          final raw = response.data;
          if (raw is Map) {
            return raw.cast<String, dynamic>();
          }
          return <String, dynamic>{};
        },
      ),
      [adapter],
    );
    final defaultProfileParams = useMemoized(
      () => _searchConfig(query: 'user:${username.value}', page: 1, perPage: 1),
      [username.value],
    );

    final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: UseRequestOptions(
        manual: false,
        ready: ready.value,
        defaultParams: defaultProfileParams,
        refreshDeps: [username.value],
        loadingDelay: Duration(milliseconds: loadingDelayMs.value.toInt()),
        onBefore: (_) => pushLog('onBefore search user:${username.value}'),
        onSuccess: (data, _) =>
            pushLog('onSuccess items=${(data['items'] as List?)?.length ?? 0}'),
        onError: (error, _) => pushLog('onError $error'),
      ),
    );

    final profile = _toProfileRecord(request.data);
    final avatar = profile.avatarUrl.trim();

    void handleMutate() {
      request.mutate((old) {
        if (old == null) return old;
        final items = old['items'];
        if (items is! List || items.isEmpty || items.first is! Map) {
          return old;
        }
        final first = Map<String, dynamic>.from(items.first as Map);
        final currentCount = (old['_mutateCount'] as num?)?.toInt() ?? 0;
        final nextCount = currentCount + 1;
        final originalDescription = (first['description'] ?? '')
            .toString()
            .replaceFirst(RegExp(r'^\[mutate(?: x\d+)?\]\s*'), '');

        // 演示更接近真实业务的乐观更新：
        // 1) 文案只保留一个 mutate 前缀，并展示累计次数
        // 2) 同步给 stars 做本地 +1，便于观察 mutate 的可见效果
        first['description'] = '[mutate x$nextCount] $originalDescription';
        first['stargazers_count'] =
            ((first['stargazers_count'] as num?)?.toInt() ?? 0) + 1;
        return <String, dynamic>{
          ...old,
          '_mutateCount': nextCount,
          'items': <dynamic>[first, ...items.skip(1)],
        };
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                key: ValueKey(username.value),
                initialValue: username.value,
                decoration: const InputDecoration(
                  labelText: 'GitHub 用户',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'octocat', child: Text('octocat')),
                  DropdownMenuItem(value: 'torvalds', child: Text('torvalds')),
                  DropdownMenuItem(value: 'gaearon', child: Text('gaearon')),
                  DropdownMenuItem(value: 'flutter', child: Text('flutter')),
                ],
                onChanged: (v) {
                  if (v != null) username.value = v;
                },
              ),
            ),
            _SwitchOption(
              label: 'ready',
              description: 'false 时阻止自动请求',
              value: ready.value,
              onChanged: (v) => ready.value = v,
            ),
            SizedBox(
              width: 280,
              child: _SliderOption(
                label: 'loadingDelay',
                valueLabel: '${loadingDelayMs.value.toInt()}ms',
                value: loadingDelayMs.value,
                min: 0,
                max: 600,
                divisions: 12,
                onChanged: (v) => loadingDelayMs.value = v,
              ),
            ),
            SizedBox(
              width: 420,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    // 在 Row 的非弹性子项中，横向约束可能是无界的。
                    // 这里如果用 stretch，按钮列会尝试在无界宽度下拉伸，进而触发布局断言。
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: request.refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('refresh()'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: handleMutate,
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('mutate()'),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'refresh() 会重新请求 GitHub 并覆盖本地改动；mutate() 只改本地状态：stars +1，描述更新为 [mutate xN]。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!ready.value)
          const _InfoBanner(
            color: Color(0xFF92400E),
            message: 'ready=false：当前不会发起自动请求。',
          ),
        if (request.loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 4),
          ),
        if (request.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _InfoBanner(
              color: const Color(0xFFB91C1C),
              message: '请求失败：${request.error}',
            ),
          ),
        if (request.data != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _GlassPanel(
              padding: const EdgeInsets.all(14),
              blur: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFE2E8F0),
                    backgroundImage: avatar.isNotEmpty
                        ? NetworkImage(avatar)
                        : null,
                    child: avatar.isEmpty
                        ? const Icon(Icons.person_outline)
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${profile.login}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stars: ${profile.stars} · Forks: ${profile.forks}',
                          style: const TextStyle(color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          profile.bio,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        _EventLog(logs: logs.value),
      ],
    );
  }
}

/// Level 2：通过切换防抖/节流模式，观察请求节奏和 UI 稳定性。
class _SearchRateControlDemo extends HookWidget {
  const _SearchRateControlDemo({required this.onSourceChanged});

  final ValueChanged<String> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: 'flutter hooks');
    final query = useState(controller.text);
    final mode = useState(_RateMode.debounce);
    final intervalMs = useState(360.0);
    final maxWaitMs = useState(1000.0);
    final useMaxWait = useState(false);
    final leading = useState(false);
    final trailing = useState(true);
    final keepPrevious = useState(true);
    final loadingDelay = useState(120.0);
    final perPage = useState(6.0);

    useEffect(
      () {
        onSourceChanged(
          _buildLevel2Source(
            query: query.value,
            perPage: perPage.value.toInt(),
            mode: mode.value,
            intervalMs: intervalMs.value.toInt(),
            leading: leading.value,
            trailing: trailing.value,
            useMaxWait: useMaxWait.value,
            maxWaitMs: maxWaitMs.value.toInt(),
            keepPrevious: keepPrevious.value,
            loadingDelay: loadingDelay.value.toInt(),
          ),
        );
        return null;
      },
      [
        query.value,
        perPage.value.toInt(),
        mode.value,
        intervalMs.value.toInt(),
        leading.value,
        trailing.value,
        useMaxWait.value,
        maxWaitMs.value.toInt(),
        keepPrevious.value,
        loadingDelay.value.toInt(),
      ],
    );

    useEffect(() {
      void listener() {
        final text = controller.text.trim();
        query.value = text.isEmpty ? 'flutter' : text;
      }

      controller.addListener(listener);
      return () => controller.removeListener(listener);
    }, [controller]);

    final adapter = useMemoized(
      () => DioHttpAdapter.withBaseUrl(_githubBaseUrl),
    );
    final service = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        adapter,
        transformer: (response) {
          final raw = response.data;
          return raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
        },
      ),
      [adapter],
    );

    final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: UseRequestOptions(
        manual: false,
        defaultParams: useMemoized(
          () => _searchConfig(
            query: query.value,
            page: 1,
            perPage: perPage.value.toInt(),
          ),
          [query.value, perPage.value.toInt()],
        ),
        refreshDeps: [
          query.value,
          perPage.value.toInt(),
          mode.value,
          intervalMs.value.toInt(),
          leading.value,
          trailing.value,
          useMaxWait.value,
          maxWaitMs.value.toInt(),
        ],
        keepPreviousData: keepPrevious.value,
        debounceInterval: mode.value == _RateMode.debounce
            ? Duration(milliseconds: intervalMs.value.toInt())
            : null,
        debounceLeading: leading.value,
        debounceTrailing: trailing.value,
        debounceMaxWait: mode.value == _RateMode.debounce && useMaxWait.value
            ? Duration(milliseconds: maxWaitMs.value.toInt())
            : null,
        throttleInterval: mode.value == _RateMode.throttle
            ? Duration(milliseconds: intervalMs.value.toInt())
            : null,
        throttleLeading: leading.value,
        throttleTrailing: trailing.value,
        loadingDelay: Duration(milliseconds: loadingDelay.value.toInt()),
      ),
    );

    final repos = _toRepoItems(request.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '搜索仓库关键字',
            hintText: '例如 flutter hooks / riverpod',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: SegmentedButton<_RateMode>(
                segments: const [
                  ButtonSegment(
                    value: _RateMode.debounce,
                    label: Text('Debounce'),
                    icon: Icon(Icons.timer_outlined),
                  ),
                  ButtonSegment(
                    value: _RateMode.throttle,
                    label: Text('Throttle'),
                    icon: Icon(Icons.speed),
                  ),
                ],
                selected: {mode.value},
                onSelectionChanged: (value) {
                  mode.value = value.first;
                },
              ),
            ),
            _SwitchOption(
              label: 'keepPreviousData',
              description: '切参时保留旧列表',
              value: keepPrevious.value,
              onChanged: (v) => keepPrevious.value = v,
            ),
            _SwitchOption(
              label: 'leading',
              description: '首次变更立即触发',
              value: leading.value,
              onChanged: (v) => leading.value = v,
            ),
            _SwitchOption(
              label: 'trailing',
              description: '窗口末尾触发',
              value: trailing.value,
              onChanged: (v) => trailing.value = v,
            ),
            if (mode.value == _RateMode.debounce)
              _SwitchOption(
                label: 'debounceMaxWait',
                description: '限制最长等待时间',
                value: useMaxWait.value,
                onChanged: (v) => useMaxWait.value = v,
              ),
            SizedBox(
              width: 260,
              child: _SliderOption(
                label: mode.value == _RateMode.debounce
                    ? 'debounceInterval'
                    : 'throttleInterval',
                valueLabel: '${intervalMs.value.toInt()}ms',
                value: intervalMs.value,
                min: 80,
                max: 1200,
                divisions: 14,
                onChanged: (v) => intervalMs.value = v,
              ),
            ),
            if (mode.value == _RateMode.debounce && useMaxWait.value)
              SizedBox(
                width: 260,
                child: _SliderOption(
                  label: 'maxWait',
                  valueLabel: '${maxWaitMs.value.toInt()}ms',
                  value: maxWaitMs.value,
                  min: 500,
                  max: 3000,
                  divisions: 10,
                  onChanged: (v) => maxWaitMs.value = v,
                ),
              ),
            SizedBox(
              width: 260,
              child: _SliderOption(
                label: 'loadingDelay',
                valueLabel: '${loadingDelay.value.toInt()}ms',
                value: loadingDelay.value,
                min: 0,
                max: 600,
                divisions: 12,
                onChanged: (v) => loadingDelay.value = v,
              ),
            ),
            SizedBox(
              width: 260,
              child: _SliderOption(
                label: 'per_page',
                valueLabel: perPage.value.toInt().toString(),
                value: perPage.value,
                min: 3,
                max: 10,
                divisions: 7,
                onChanged: (v) => perPage.value = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (request.loading) const LinearProgressIndicator(minHeight: 4),
        if (request.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _InfoBanner(
              color: const Color(0xFFB91C1C),
              message: '查询失败：${request.error}',
            ),
          ),
        const SizedBox(height: 8),
        ...repos.map((repo) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(repo.fullName),
            subtitle: Text(
              '${repo.language} · ${repo.description}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text('★ ${repo.stars}'),
          );
        }),
      ],
    );
  }
}

/// Level 3：演示轮询、失败重试、超时与取消。
class _PollingRetryDemo extends HookWidget {
  const _PollingRetryDemo({required this.onSourceChanged});

  final ValueChanged<String> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final repo = useState('flutter/flutter');
    final pollingEnabled = useState(false);
    final pollingInterval = useState(8.0);
    final pollingWhenHidden = useState(true);
    final pausePollingOnError = useState(true);
    final pollingRetryInterval = useState(4.0);
    final retryCount = useState(2.0);
    final retryInterval = useState(1000.0);
    final retryExponential = useState(true);
    final timeoutSec = useState(3.0);
    final forceError = useState(false);
    final logs = useState<List<String>>(<String>[]);

    useEffect(
      () {
        onSourceChanged(
          _buildLevel3Source(
            repo: repo.value,
            pollingEnabled: pollingEnabled.value,
            pollingInterval: pollingInterval.value.toInt(),
            pollingWhenHidden: pollingWhenHidden.value,
            pausePollingOnError: pausePollingOnError.value,
            pollingRetryInterval: pollingRetryInterval.value.toInt(),
            retryCount: retryCount.value.toInt(),
            retryInterval: retryInterval.value.toInt(),
            retryExponential: retryExponential.value,
            timeoutSec: timeoutSec.value.toInt(),
            forceError: forceError.value,
          ),
        );
        return null;
      },
      [
        repo.value,
        pollingEnabled.value,
        pollingInterval.value.toInt(),
        pollingWhenHidden.value,
        pausePollingOnError.value,
        pollingRetryInterval.value.toInt(),
        retryCount.value.toInt(),
        retryInterval.value.toInt(),
        retryExponential.value,
        timeoutSec.value.toInt(),
        forceError.value,
      ],
    );

    void pushLog(String text) {
      logs.value = <String>[
        '${_clockNow()}  $text',
        ...logs.value,
      ].take(8).toList();
    }

    final adapter = useMemoized(
      () => DioHttpAdapter.withBaseUrl(_githubBaseUrl),
    );
    final service = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        adapter,
        transformer: (response) {
          final raw = response.data;
          return raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
        },
      ),
      [adapter],
    );

    final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: UseRequestOptions(
        manual: false,
        defaultParams: useMemoized(
          () => _repoConfig(repo.value, forceError: forceError.value),
          [repo.value, forceError.value],
        ),
        refreshDeps: [repo.value, forceError.value],
        pollingInterval: pollingEnabled.value
            ? Duration(seconds: pollingInterval.value.toInt())
            : null,
        pollingWhenHidden: pollingWhenHidden.value,
        pausePollingOnError: pausePollingOnError.value,
        pollingRetryInterval: Duration(
          seconds: pollingRetryInterval.value.toInt(),
        ),
        retryCount: retryCount.value.toInt(),
        retryInterval: Duration(milliseconds: retryInterval.value.toInt()),
        retryExponential: retryExponential.value,
        connectTimeout: Duration(seconds: timeoutSec.value.toInt()),
        receiveTimeout: Duration(seconds: timeoutSec.value.toInt()),
        sendTimeout: Duration(seconds: timeoutSec.value.toInt()),
        onRetryAttempt: (attempt, error) {
          pushLog('onRetryAttempt #$attempt -> $error');
        },
        onSuccess: (data, _) {
          pushLog('onSuccess repo=${repo.value}');
        },
        onError: (error, _) {
          pushLog('onError $error');
        },
      ),
    );

    final repoInfo = _toRepoMetricsRecord(request.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                key: ValueKey(repo.value),
                initialValue: repo.value,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '仓库',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'flutter/flutter',
                    child: Text('flutter/flutter'),
                  ),
                  DropdownMenuItem(
                    value: 'dart-lang/sdk',
                    child: Text('dart-lang/sdk'),
                  ),
                  DropdownMenuItem(
                    value: 'vercel/next.js',
                    child: Text('vercel/next.js'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) repo.value = v;
                },
              ),
            ),
            _SwitchOption(
              label: 'pollingEnabled',
              description: '是否开启轮询',
              value: pollingEnabled.value,
              onChanged: (v) => pollingEnabled.value = v,
            ),
            _SwitchOption(
              label: 'pollingWhenHidden',
              description: '后台是否继续轮询',
              value: pollingWhenHidden.value,
              onChanged: (v) => pollingWhenHidden.value = v,
            ),
            _SwitchOption(
              label: 'pausePollingOnError',
              description: '出错后暂停轮询',
              value: pausePollingOnError.value,
              onChanged: (v) => pausePollingOnError.value = v,
            ),
            _SwitchOption(
              label: 'retryExponential',
              description: '指数退避',
              value: retryExponential.value,
              onChanged: (v) => retryExponential.value = v,
            ),
            _SwitchOption(
              label: 'forceError',
              description: '模拟错误路径',
              value: forceError.value,
              onChanged: (v) => forceError.value = v,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 250,
              child: _SliderOption(
                label: 'pollingInterval',
                valueLabel: '${pollingInterval.value.toInt()}s',
                value: pollingInterval.value,
                min: 2,
                max: 20,
                divisions: 9,
                onChanged: (v) => pollingInterval.value = v,
              ),
            ),
            SizedBox(
              width: 250,
              child: _SliderOption(
                label: 'pollingRetryInterval',
                valueLabel: '${pollingRetryInterval.value.toInt()}s',
                value: pollingRetryInterval.value,
                min: 1,
                max: 12,
                divisions: 11,
                onChanged: (v) => pollingRetryInterval.value = v,
              ),
            ),
            SizedBox(
              width: 250,
              child: _SliderOption(
                label: 'retryCount',
                valueLabel: retryCount.value.toInt().toString(),
                value: retryCount.value,
                min: 0,
                max: 5,
                divisions: 5,
                onChanged: (v) => retryCount.value = v,
              ),
            ),
            SizedBox(
              width: 250,
              child: _SliderOption(
                label: 'retryInterval',
                valueLabel: '${retryInterval.value.toInt()}ms',
                value: retryInterval.value,
                min: 300,
                max: 4000,
                divisions: 12,
                onChanged: (v) => retryInterval.value = v,
              ),
            ),
            SizedBox(
              width: 250,
              child: _SliderOption(
                label: 'connect/receive/send timeout',
                valueLabel: '${timeoutSec.value.toInt()}s',
                value: timeoutSec.value,
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) => timeoutSec.value = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: request.refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('refresh()'),
            ),
            OutlinedButton.icon(
              onPressed: request.pausePolling,
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('pausePolling()'),
            ),
            OutlinedButton.icon(
              onPressed: request.resumePolling,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('resumePolling()'),
            ),
            OutlinedButton.icon(
              onPressed: request.cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('cancel()'),
            ),
            _StatusDot(
              label: request.isPolling ? 'Polling ON' : 'Polling OFF',
              active: request.isPolling,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (request.loading) const LinearProgressIndicator(minHeight: 4),
        if (request.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _InfoBanner(
              color: const Color(0xFFB91C1C),
              message: '请求失败：${request.error}',
            ),
          ),
        if (request.data != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _GlassPanel(
              padding: const EdgeInsets.all(14),
              blur: 8,
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('仓库: ${repoInfo.fullName}'),
                  Text('★ ${repoInfo.stars}'),
                  Text('Forks: ${repoInfo.forks}'),
                  Text('Issues: ${repoInfo.openIssues}'),
                  Text('Updated: ${repoInfo.pushedAt}'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        _EventLog(logs: logs.value),
      ],
    );
  }
}

/// Level 4：按分组控制几乎全部 UseRequestOptions，便于统一试参。
///
/// 这个实验台使用 GitHub 搜索接口，并把高频组合能力都放到一个页面：
/// - 基础配置、依赖刷新、轮询、频率控制
/// - 重试、超时、缓存、并发隔离
/// - 加载更多、回调、取消令牌、刷新策略
class _OptionsWorkbenchDemo extends HookWidget {
  const _OptionsWorkbenchDemo({required this.onSourceChanged});

  final ValueChanged<String> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final queryController = useTextEditingController(text: 'flutter');
    final query = useState(queryController.text);
    final sort = useState('stars');
    final order = useState('desc');
    final perPage = useState(6.0);

    // 基础配置
    final manual = useState(false);
    final ready = useState(true);
    final useInitialData = useState(true);
    final keepPreviousData = useState(true);

    // 依赖刷新
    final refreshDepsEnabled = useState(true);
    final customRefreshDepsAction = useState(false);
    final depsVersion = useState(0);

    // 轮询配置
    final pollingEnabled = useState(false);
    final pollingInterval = useState(10.0);
    final pollingWhenHidden = useState(true);
    final pausePollingOnError = useState(false);
    final pollingRetryInterval = useState(4.0);

    // 频率控制
    final rateMode = useState(_RateMode.debounce);
    final rateInterval = useState(450.0);
    final debounceLeading = useState(false);
    final debounceTrailing = useState(true);
    final debounceMaxWaitEnabled = useState(false);
    final debounceMaxWait = useState(1200.0);
    final throttleLeading = useState(true);
    final throttleTrailing = useState(true);

    // 重试配置
    final retryEnabled = useState(true);
    final retryCount = useState(2.0);
    final retryInterval = useState(900.0);
    final retryExponential = useState(true);

    // 超时配置
    final connectTimeout = useState(5.0);
    final receiveTimeout = useState(6.0);
    final sendTimeout = useState(5.0);

    // 加载与刷新
    final loadingDelay = useState(120.0);
    final refreshOnFocus = useState(false);
    final refreshOnReconnect = useState(false);

    // 缓存与并发
    final cacheEnabled = useState(true);
    final cacheTime = useState(40.0);
    final staleTime = useState(12.0);
    final fetchKeyByQuery = useState(true);

    // 加载更多与控制
    final loadMoreEnabled = useState(true);
    final externalCancelEnabled = useState(false);
    final callbacksEnabled = useState(true);
    final forceError = useState(false);

    useEffect(
      () {
        onSourceChanged(
          _buildLevel4Source(
            query: query.value,
            sort: sort.value,
            order: order.value,
            perPage: perPage.value.toInt(),
            manual: manual.value,
            ready: ready.value,
            useInitialData: useInitialData.value,
            keepPreviousData: keepPreviousData.value,
            refreshDepsEnabled: refreshDepsEnabled.value,
            customRefreshDepsAction: customRefreshDepsAction.value,
            depsVersion: depsVersion.value,
            pollingEnabled: pollingEnabled.value,
            pollingInterval: pollingInterval.value.toInt(),
            pollingWhenHidden: pollingWhenHidden.value,
            pausePollingOnError: pausePollingOnError.value,
            pollingRetryInterval: pollingRetryInterval.value.toInt(),
            rateMode: rateMode.value,
            rateInterval: rateInterval.value.toInt(),
            debounceLeading: debounceLeading.value,
            debounceTrailing: debounceTrailing.value,
            debounceMaxWaitEnabled: debounceMaxWaitEnabled.value,
            debounceMaxWait: debounceMaxWait.value.toInt(),
            throttleLeading: throttleLeading.value,
            throttleTrailing: throttleTrailing.value,
            retryEnabled: retryEnabled.value,
            retryCount: retryCount.value.toInt(),
            retryInterval: retryInterval.value.toInt(),
            retryExponential: retryExponential.value,
            connectTimeout: connectTimeout.value.toInt(),
            receiveTimeout: receiveTimeout.value.toInt(),
            sendTimeout: sendTimeout.value.toInt(),
            loadingDelay: loadingDelay.value.toInt(),
            refreshOnFocus: refreshOnFocus.value,
            refreshOnReconnect: refreshOnReconnect.value,
            cacheEnabled: cacheEnabled.value,
            cacheTime: cacheTime.value.toInt(),
            staleTime: staleTime.value.toInt(),
            fetchKeyByQuery: fetchKeyByQuery.value,
            loadMoreEnabled: loadMoreEnabled.value,
            externalCancelEnabled: externalCancelEnabled.value,
            callbacksEnabled: callbacksEnabled.value,
            forceError: forceError.value,
          ),
        );
        return null;
      },
      [
        query.value,
        sort.value,
        order.value,
        perPage.value.toInt(),
        manual.value,
        ready.value,
        useInitialData.value,
        keepPreviousData.value,
        refreshDepsEnabled.value,
        customRefreshDepsAction.value,
        depsVersion.value,
        pollingEnabled.value,
        pollingInterval.value.toInt(),
        pollingWhenHidden.value,
        pausePollingOnError.value,
        pollingRetryInterval.value.toInt(),
        rateMode.value,
        rateInterval.value.toInt(),
        debounceLeading.value,
        debounceTrailing.value,
        debounceMaxWaitEnabled.value,
        debounceMaxWait.value.toInt(),
        throttleLeading.value,
        throttleTrailing.value,
        retryEnabled.value,
        retryCount.value.toInt(),
        retryInterval.value.toInt(),
        retryExponential.value,
        connectTimeout.value.toInt(),
        receiveTimeout.value.toInt(),
        sendTimeout.value.toInt(),
        loadingDelay.value.toInt(),
        refreshOnFocus.value,
        refreshOnReconnect.value,
        cacheEnabled.value,
        cacheTime.value.toInt(),
        staleTime.value.toInt(),
        fetchKeyByQuery.value,
        loadMoreEnabled.value,
        externalCancelEnabled.value,
        callbacksEnabled.value,
        forceError.value,
      ],
    );

    final reconnectController = useMemoized(
      () => StreamController<bool>.broadcast(),
    );
    useEffect(() {
      return () {
        unawaited(reconnectController.close());
      };
    }, [reconnectController]);

    final cancelEpoch = useState(0);
    final externalToken = useMemoized(() => CancelToken(), [cancelEpoch.value]);
    final logs = useState<List<String>>(<String>[]);
    final requestRef =
        useRef<UseRequestResult<Map<String, dynamic>, HttpRequestConfig>?>(
          null,
        );

    void pushLog(String text) {
      logs.value = <String>[
        '${_clockNow()}  $text',
        ...logs.value,
      ].take(12).toList();
    }

    useEffect(() {
      void listener() {
        final trimmed = queryController.text.trim();
        query.value = trimmed.isEmpty ? 'flutter' : trimmed;
      }

      queryController.addListener(listener);
      return () => queryController.removeListener(listener);
    }, [queryController]);

    final adapter = useMemoized(
      () => DioHttpAdapter.withBaseUrl(_githubBaseUrl),
    );
    final service =
        useMemoized<Service<Map<String, dynamic>, HttpRequestConfig>>(() {
          return (config) async {
            final response = await adapter.request<Map<String, dynamic>>(
              config,
            );
            final data = response.data;
            final map = data is Map
                ? Map<String, dynamic>.from(data as Map<dynamic, dynamic>)
                : <String, dynamic>{};
            return <String, dynamic>{
              ...map,
              '_fetchedAt': DateTime.now().toIso8601String(),
            };
          };
        }, [adapter]);

    HttpRequestConfig buildSearchParams({required int page}) {
      return HttpRequestConfig.get(
        forceError.value
            ? '/search/repositories-invalid'
            : '/search/repositories',
        headers: _githubHeaders,
        queryParameters: {
          'q': query.value,
          'sort': sort.value,
          'order': order.value,
          'per_page': perPage.value.toInt(),
          'page': page,
        },
      );
    }

    final options = UseRequestOptions<Map<String, dynamic>, HttpRequestConfig>(
      manual: manual.value,
      ready: ready.value,
      defaultParams: useMemoized(() => buildSearchParams(page: 1), [
        query.value,
        sort.value,
        order.value,
        perPage.value.toInt(),
        forceError.value,
      ]),
      initialData: useInitialData.value
          ? <String, dynamic>{
              'total_count': 0,
              'items': const <dynamic>[],
              '_fetchedAt': 'initialData',
            }
          : null,
      keepPreviousData: keepPreviousData.value,
      refreshDeps: refreshDepsEnabled.value
          ? [
              query.value,
              sort.value,
              order.value,
              perPage.value.toInt(),
              depsVersion.value,
            ]
          : null,
      refreshDepsAction: customRefreshDepsAction.value
          ? () {
              pushLog('refreshDepsAction -> run(page=1)');
              requestRef.value?.run(buildSearchParams(page: 1));
            }
          : null,
      pollingInterval: pollingEnabled.value
          ? Duration(seconds: pollingInterval.value.toInt())
          : null,
      pollingWhenHidden: pollingWhenHidden.value,
      pausePollingOnError: pausePollingOnError.value,
      pollingRetryInterval: Duration(
        seconds: pollingRetryInterval.value.toInt(),
      ),
      debounceInterval: rateMode.value == _RateMode.debounce
          ? Duration(milliseconds: rateInterval.value.toInt())
          : null,
      debounceLeading: debounceLeading.value,
      debounceTrailing: debounceTrailing.value,
      debounceMaxWait:
          rateMode.value == _RateMode.debounce && debounceMaxWaitEnabled.value
          ? Duration(milliseconds: debounceMaxWait.value.toInt())
          : null,
      throttleInterval: rateMode.value == _RateMode.throttle
          ? Duration(milliseconds: rateInterval.value.toInt())
          : null,
      throttleLeading: throttleLeading.value,
      throttleTrailing: throttleTrailing.value,
      retryCount: retryEnabled.value ? retryCount.value.toInt() : null,
      retryInterval: retryEnabled.value
          ? Duration(milliseconds: retryInterval.value.toInt())
          : null,
      retryExponential: retryExponential.value,
      onRetryAttempt: retryEnabled.value && callbacksEnabled.value
          ? (attempt, error) => pushLog('onRetryAttempt #$attempt -> $error')
          : null,
      connectTimeout: Duration(seconds: connectTimeout.value.toInt()),
      receiveTimeout: Duration(seconds: receiveTimeout.value.toInt()),
      sendTimeout: Duration(seconds: sendTimeout.value.toInt()),
      loadingDelay: Duration(milliseconds: loadingDelay.value.toInt()),
      refreshOnFocus: refreshOnFocus.value,
      refreshOnReconnect: refreshOnReconnect.value,
      reconnectStream: reconnectController.stream,
      cacheKey: cacheEnabled.value
          ? (params) {
              final qp = params.queryParameters ?? const <String, dynamic>{};
              return 'gh:${params.path}:${qp['q']}:${qp['page']}:${qp['per_page']}';
            }
          : null,
      cacheTime: cacheEnabled.value
          ? Duration(seconds: cacheTime.value.toInt())
          : null,
      staleTime: cacheEnabled.value
          ? Duration(seconds: staleTime.value.toInt())
          : null,
      fetchKey: fetchKeyByQuery.value
          ? (params) => 'q:${params.queryParameters?['q'] ?? ''}'
          : null,
      loadMoreParams: loadMoreEnabled.value
          ? (lastParams, _) {
              final currentPage =
                  (lastParams.queryParameters?['page'] as num?)?.toInt() ?? 1;
              return lastParams.copyWith(
                queryParameters: {
                  ...?lastParams.queryParameters,
                  'page': currentPage + 1,
                },
              );
            }
          : null,
      dataMerger: loadMoreEnabled.value ? _mergeSearchResult : null,
      hasMore: loadMoreEnabled.value ? _hasMoreSearchResult : null,
      cancelToken: externalCancelEnabled.value ? externalToken : null,
      onBefore: callbacksEnabled.value
          ? (params) {
              final page =
                  (params.queryParameters?['page'] as num?)?.toInt() ?? 1;
              pushLog('onBefore page=$page');
            }
          : null,
      onSuccess: callbacksEnabled.value
          ? (data, params) {
              final page =
                  (params.queryParameters?['page'] as num?)?.toInt() ?? 1;
              final count = (data['items'] as List?)?.length ?? 0;
              pushLog('onSuccess page=$page items=$count');
            }
          : null,
      onError: callbacksEnabled.value
          ? (error, _) => pushLog('onError $error')
          : null,
      onFinally: callbacksEnabled.value
          ? (params, _, error) {
              final page =
                  (params.queryParameters?['page'] as num?)?.toInt() ?? 1;
              pushLog('onFinally page=$page error=${error != null}');
            }
          : null,
    );

    final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: options,
    );
    requestRef.value = request;

    final repos = _toRepoItems(request.data);
    final fetchedAt = (request.data?['_fetchedAt'] ?? '-').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OptionGroup(
          title: '基础配置',
          subtitle:
              'manual / ready / defaultParams / initialData / keepPreviousData',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: queryController,
                  decoration: const InputDecoration(
                    labelText: 'q',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(sort.value),
                  initialValue: sort.value,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'sort',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'stars', child: Text('stars')),
                    DropdownMenuItem(value: 'updated', child: Text('updated')),
                    DropdownMenuItem(value: 'forks', child: Text('forks')),
                  ],
                  onChanged: (v) {
                    if (v != null) sort.value = v;
                  },
                ),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(order.value),
                  initialValue: order.value,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'order',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'desc', child: Text('desc')),
                    DropdownMenuItem(value: 'asc', child: Text('asc')),
                  ],
                  onChanged: (v) {
                    if (v != null) order.value = v;
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'per_page',
                  valueLabel: perPage.value.toInt().toString(),
                  value: perPage.value,
                  min: 3,
                  max: 15,
                  divisions: 12,
                  onChanged: (v) => perPage.value = v,
                ),
              ),
              _SwitchOption(
                label: 'manual',
                description: '手动触发 run()',
                value: manual.value,
                onChanged: (v) => manual.value = v,
              ),
              _SwitchOption(
                label: 'ready',
                description: 'false 时禁止自动请求',
                value: ready.value,
                onChanged: (v) => ready.value = v,
              ),
              _SwitchOption(
                label: 'initialData',
                description: '首帧占位数据',
                value: useInitialData.value,
                onChanged: (v) => useInitialData.value = v,
              ),
              _SwitchOption(
                label: 'keepPreviousData',
                description: '切参时保留旧数据',
                value: keepPreviousData.value,
                onChanged: (v) => keepPreviousData.value = v,
              ),
              _SwitchOption(
                label: 'forceError',
                description: '模拟错误路径',
                value: forceError.value,
                onChanged: (v) => forceError.value = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '依赖刷新',
          subtitle: 'refreshDeps / refreshDepsAction',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SwitchOption(
                label: 'refreshDeps',
                description: '依赖变化自动刷新',
                value: refreshDepsEnabled.value,
                onChanged: (v) => refreshDepsEnabled.value = v,
              ),
              _SwitchOption(
                label: 'refreshDepsAction',
                description: '自定义依赖变化动作',
                value: customRefreshDepsAction.value,
                onChanged: (v) => customRefreshDepsAction.value = v,
              ),
              FilledButton.tonalIcon(
                onPressed: () => depsVersion.value += 1,
                icon: const Icon(Icons.track_changes_outlined),
                label: Text('deps +1 (${depsVersion.value})'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '轮询配置',
          subtitle:
              'pollingInterval / pollingWhenHidden / pausePollingOnError / pollingRetryInterval',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SwitchOption(
                label: 'pollingInterval',
                description: '是否开启轮询',
                value: pollingEnabled.value,
                onChanged: (v) => pollingEnabled.value = v,
              ),
              _SwitchOption(
                label: 'pollingWhenHidden',
                description: '后台继续轮询',
                value: pollingWhenHidden.value,
                onChanged: (v) => pollingWhenHidden.value = v,
              ),
              _SwitchOption(
                label: 'pausePollingOnError',
                description: '出错暂停轮询',
                value: pausePollingOnError.value,
                onChanged: (v) => pausePollingOnError.value = v,
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'pollingInterval',
                  valueLabel: '${pollingInterval.value.toInt()}s',
                  value: pollingInterval.value,
                  min: 2,
                  max: 30,
                  divisions: 14,
                  onChanged: (v) => pollingInterval.value = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'pollingRetryInterval',
                  valueLabel: '${pollingRetryInterval.value.toInt()}s',
                  value: pollingRetryInterval.value,
                  min: 1,
                  max: 12,
                  divisions: 11,
                  onChanged: (v) => pollingRetryInterval.value = v,
                ),
              ),
              OutlinedButton.icon(
                onPressed: request.pausePolling,
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('pausePolling'),
              ),
              OutlinedButton.icon(
                onPressed: request.resumePolling,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('resumePolling'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '频率控制（防抖 / 节流）',
          subtitle:
              'debounceInterval / debounceLeading / debounceTrailing / debounceMaxWait / throttleInterval',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 360,
                child: SegmentedButton<_RateMode>(
                  segments: const [
                    ButtonSegment(
                      value: _RateMode.debounce,
                      label: Text('Debounce'),
                    ),
                    ButtonSegment(
                      value: _RateMode.throttle,
                      label: Text('Throttle'),
                    ),
                  ],
                  selected: {rateMode.value},
                  onSelectionChanged: (value) {
                    rateMode.value = value.first;
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: rateMode.value == _RateMode.debounce
                      ? 'debounceInterval'
                      : 'throttleInterval',
                  valueLabel: '${rateInterval.value.toInt()}ms',
                  value: rateInterval.value,
                  min: 100,
                  max: 1500,
                  divisions: 14,
                  onChanged: (v) => rateInterval.value = v,
                ),
              ),
              _SwitchOption(
                label: 'debounceLeading',
                description: '防抖首次触发',
                value: debounceLeading.value,
                onChanged: (v) => debounceLeading.value = v,
              ),
              _SwitchOption(
                label: 'debounceTrailing',
                description: '防抖末尾触发',
                value: debounceTrailing.value,
                onChanged: (v) => debounceTrailing.value = v,
              ),
              _SwitchOption(
                label: 'debounceMaxWait',
                description: '防抖最大等待',
                value: debounceMaxWaitEnabled.value,
                onChanged: (v) => debounceMaxWaitEnabled.value = v,
              ),
              if (debounceMaxWaitEnabled.value)
                SizedBox(
                  width: 240,
                  child: _SliderOption(
                    label: 'maxWait',
                    valueLabel: '${debounceMaxWait.value.toInt()}ms',
                    value: debounceMaxWait.value,
                    min: 400,
                    max: 3000,
                    divisions: 13,
                    onChanged: (v) => debounceMaxWait.value = v,
                  ),
                ),
              _SwitchOption(
                label: 'throttleLeading',
                description: '节流首次触发',
                value: throttleLeading.value,
                onChanged: (v) => throttleLeading.value = v,
              ),
              _SwitchOption(
                label: 'throttleTrailing',
                description: '节流末尾触发',
                value: throttleTrailing.value,
                onChanged: (v) => throttleTrailing.value = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '重试与超时',
          subtitle:
              'retryCount / retryInterval / retryExponential + connect/receive/send timeout',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SwitchOption(
                label: 'retryEnabled',
                description: '是否启用重试',
                value: retryEnabled.value,
                onChanged: (v) => retryEnabled.value = v,
              ),
              _SwitchOption(
                label: 'retryExponential',
                description: '指数退避',
                value: retryExponential.value,
                onChanged: (v) => retryExponential.value = v,
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'retryCount',
                  valueLabel: retryCount.value.toInt().toString(),
                  value: retryCount.value,
                  min: 0,
                  max: 6,
                  divisions: 6,
                  onChanged: (v) => retryCount.value = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'retryInterval',
                  valueLabel: '${retryInterval.value.toInt()}ms',
                  value: retryInterval.value,
                  min: 300,
                  max: 4000,
                  divisions: 12,
                  onChanged: (v) => retryInterval.value = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'connectTimeout',
                  valueLabel: '${connectTimeout.value.toInt()}s',
                  value: connectTimeout.value,
                  min: 1,
                  max: 15,
                  divisions: 14,
                  onChanged: (v) => connectTimeout.value = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'receiveTimeout',
                  valueLabel: '${receiveTimeout.value.toInt()}s',
                  value: receiveTimeout.value,
                  min: 1,
                  max: 15,
                  divisions: 14,
                  onChanged: (v) => receiveTimeout.value = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'sendTimeout',
                  valueLabel: '${sendTimeout.value.toInt()}s',
                  value: sendTimeout.value,
                  min: 1,
                  max: 15,
                  divisions: 14,
                  onChanged: (v) => sendTimeout.value = v,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '加载与刷新',
          subtitle:
              'loadingDelay / refreshOnFocus / refreshOnReconnect / reconnectStream',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'loadingDelay',
                  valueLabel: '${loadingDelay.value.toInt()}ms',
                  value: loadingDelay.value,
                  min: 0,
                  max: 800,
                  divisions: 16,
                  onChanged: (v) => loadingDelay.value = v,
                ),
              ),
              _SwitchOption(
                label: 'refreshOnFocus',
                description: '窗口聚焦自动刷新',
                value: refreshOnFocus.value,
                onChanged: (v) => refreshOnFocus.value = v,
              ),
              _SwitchOption(
                label: 'refreshOnReconnect',
                description: '网络恢复自动刷新',
                value: refreshOnReconnect.value,
                onChanged: (v) => refreshOnReconnect.value = v,
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  reconnectController.add(true);
                  pushLog('reconnectStream -> true');
                },
                icon: const Icon(Icons.wifi_tethering_outlined),
                label: const Text('模拟重连事件'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '缓存与并发隔离',
          subtitle: 'cacheKey / cacheTime / staleTime / fetchKey',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SwitchOption(
                label: 'cacheKey',
                description: '启用缓存键',
                value: cacheEnabled.value,
                onChanged: (v) => cacheEnabled.value = v,
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'cacheTime',
                  valueLabel: '${cacheTime.value.toInt()}s',
                  value: cacheTime.value,
                  min: 10,
                  max: 120,
                  divisions: 11,
                  onChanged: (v) => cacheTime.value = v,
                ),
              ),
              SizedBox(
                width: 240,
                child: _SliderOption(
                  label: 'staleTime',
                  valueLabel: '${staleTime.value.toInt()}s',
                  value: staleTime.value,
                  min: 2,
                  max: 60,
                  divisions: 14,
                  onChanged: (v) => staleTime.value = v,
                ),
              ),
              _SwitchOption(
                label: 'fetchKey',
                description: '按 query 隔离并发',
                value: fetchKeyByQuery.value,
                onChanged: (v) => fetchKeyByQuery.value = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _OptionGroup(
          title: '加载更多、取消与回调',
          subtitle:
              'loadMoreParams / dataMerger / hasMore / cancelToken / onBefore/onSuccess/onError/onFinally',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SwitchOption(
                label: 'loadMoreParams',
                description: '启用分页加载更多',
                value: loadMoreEnabled.value,
                onChanged: (v) => loadMoreEnabled.value = v,
              ),
              _SwitchOption(
                label: 'cancelToken',
                description: '使用外部 cancel token',
                value: externalCancelEnabled.value,
                onChanged: (v) => externalCancelEnabled.value = v,
              ),
              _SwitchOption(
                label: 'callbacks',
                description: '启用生命周期回调日志',
                value: callbacksEnabled.value,
                onChanged: (v) => callbacksEnabled.value = v,
              ),
              FilledButton.tonalIcon(
                onPressed: () => request.run(buildSearchParams(page: 1)),
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('run(page=1)'),
              ),
              OutlinedButton.icon(
                onPressed: request.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('refresh()'),
              ),
              OutlinedButton.icon(
                onPressed: loadMoreEnabled.value ? request.loadMore : null,
                icon: const Icon(Icons.expand_more),
                label: Text(
                  request.loadingMore ? 'loadingMore...' : 'loadMore()',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  request.mutate((old) {
                    if (old == null) return old;
                    final oldItems = old['items'] as List? ?? const [];
                    if (oldItems.isEmpty) return old;
                    final first = oldItems.first;
                    if (first is! Map) return old;
                    final patchedFirst = Map<String, dynamic>.from(first)
                      ..update(
                        'full_name',
                        (value) => '[mutated] $value',
                        ifAbsent: () => '[mutated] unknown',
                      );
                    return <String, dynamic>{
                      ...old,
                      'items': <dynamic>[patchedFirst, ...oldItems.skip(1)],
                    };
                  });
                  pushLog('mutate -> patch first item');
                },
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('mutate()'),
              ),
              OutlinedButton.icon(
                onPressed: request.cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('cancel()'),
              ),
              OutlinedButton.icon(
                onPressed: externalCancelEnabled.value
                    ? () {
                        externalToken.cancel('cancel from external token');
                        cancelEpoch.value += 1;
                        pushLog('external cancelToken.cancel()');
                      }
                    : null,
                icon: const Icon(Icons.block_outlined),
                label: const Text('external cancelToken.cancel()'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusDot(
              label: request.loading ? 'loading' : 'idle',
              active: request.loading,
            ),
            _StatusDot(
              label: request.loadingMore ? 'loadingMore' : 'not loadingMore',
              active: request.loadingMore,
            ),
            _StatusDot(
              label: request.isPolling ? 'polling' : 'not polling',
              active: request.isPolling,
            ),
            _StatusDot(
              label: 'hasMore=${request.hasMore}',
              active: request.hasMore ?? false,
            ),
            _StatusDot(label: 'fetchedAt=$fetchedAt', active: false),
          ],
        ),
        if (request.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _InfoBanner(
              color: const Color(0xFFB91C1C),
              message: '请求失败：${request.error}',
            ),
          ),
        if (request.loading)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(minHeight: 4),
          ),
        const SizedBox(height: 8),
        ...repos.map((repo) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(repo.fullName),
            subtitle: Text(
              '${repo.language} · ${repo.description}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text('★ ${repo.stars}'),
          );
        }),
        const SizedBox(height: 6),
        _EventLog(logs: logs.value),
      ],
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      blur: 6,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DecorativeBackdrop extends StatelessWidget {
  const _DecorativeBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF2FF), Color(0xFFE6FBF7), Color(0xFFF5F7FD)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -90,
            top: -80,
            child: _BlurBlob(color: const Color(0x8855DDE0), size: 300),
          ),
          Positioned(
            right: -70,
            top: 100,
            child: _BlurBlob(color: const Color(0x884CB9F0), size: 240),
          ),
          Positioned(
            right: 120,
            bottom: -80,
            child: _BlurBlob(color: const Color(0x88A5B4FC), size: 220),
          ),
        ],
      ),
    );
  }
}

class _BlurBlob extends StatelessWidget {
  const _BlurBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.blur = 12,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xDDF8FCFF), Color(0xBFF2F8FF)],
            ),
            border: Border.all(color: const Color(0x8FFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A0F172A),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _TopBadge extends StatelessWidget {
  const _TopBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x3322C4B8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x5520B7A9)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF0F766E),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OptionTag extends StatelessWidget {
  const _OptionTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x220EA5A4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0F766E),
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _SwitchOption extends StatelessWidget {
  const _SwitchOption({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x447D8FA8)),
        color: Colors.white.withValues(alpha: 0.45),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SliderOption extends StatelessWidget {
  const _SliderOption({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x447D8FA8)),
        color: Colors.white.withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF0F766E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: active ? const Color(0x3322C4B8) : const Color(0x22A7B2C5),
        border: Border.all(
          color: active ? const Color(0xFF22B8AA) : const Color(0xFF93A5BE),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: active ? const Color(0xFF0F766E) : const Color(0xFF516176),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(message, style: TextStyle(color: color, fontSize: 12.5)),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Text(
        '事件日志：暂无',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
      );
    }

    return _GlassPanel(
      blur: 5,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '事件日志',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          ...logs.map(
            (log) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $log',
                style: const TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 11.5,
                  color: Color(0xFF45556A),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCodePanel extends StatelessWidget {
  const _SourceCodePanel({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: _GlassPanel(
        blur: 5,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          title: const Text(
            '查看源码（Dart）',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 640),
                  child: SelectableText.rich(
                    _buildHighlightedCodeSpan(code),
                    style: const TextStyle(
                      fontFamily: 'Menlo',
                      fontSize: 12,
                      height: 1.45,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextSpan _buildHighlightedCodeSpan(String source) {
  final keywordPattern =
      r'\b(class|const|final|if|else|for|while|switch|case|default|return|void|bool|int|double|String|Future|async|await|var|true|false|null|import|enum|extends|implements|with|this|required|late|try|catch|throw|typedef)\b';
  final pattern = RegExp(
    "(//.*\$|\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|$keywordPattern)",
    multiLine: true,
  );

  final spans = <TextSpan>[];
  var current = 0;

  for (final match in pattern.allMatches(source)) {
    if (match.start > current) {
      spans.add(TextSpan(text: source.substring(current, match.start)));
    }

    final token = match.group(0) ?? '';
    Color color = const Color(0xFFE2E8F0);

    if (token.startsWith('//')) {
      color = const Color(0xFF86EFAC);
    } else if (token.startsWith('"') || token.startsWith('\'')) {
      color = const Color(0xFFFDE68A);
    } else {
      color = const Color(0xFF93C5FD);
    }

    spans.add(
      TextSpan(
        text: token,
        style: TextStyle(color: color),
      ),
    );
    current = match.end;
  }

  if (current < source.length) {
    spans.add(TextSpan(text: source.substring(current)));
  }

  return TextSpan(children: spans);
}

String _clockNow() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
}

enum _RateMode { debounce, throttle }

typedef _ProfileRecord = ({
  String login,
  int stars,
  int forks,
  String avatarUrl,
  String bio,
});

_ProfileRecord _toProfileRecord(Map<String, dynamic>? raw) {
  final first = _firstRepoItem(raw);
  final owner = first?['owner'];
  final ownerMap = owner is Map ? owner.cast<String, dynamic>() : null;

  return (
    login: (ownerMap?['login'] ?? 'unknown').toString(),
    stars: (first?['stargazers_count'] as num?)?.toInt() ?? 0,
    forks: (first?['forks_count'] as num?)?.toInt() ?? 0,
    avatarUrl: (ownerMap?['avatar_url'] ?? '').toString(),
    bio: (first?['description'] ?? 'No description').toString(),
  );
}

typedef _RepoItemRecord = ({
  String fullName,
  String description,
  int stars,
  String language,
});

List<_RepoItemRecord> _toRepoItems(Map<String, dynamic>? raw) {
  final items = raw?['items'];
  if (items is! List) return const [];

  return items.map((item) {
    if (item is! Map) {
      return (fullName: 'unknown', description: '', stars: 0, language: '-');
    }

    final map = item.cast<String, dynamic>();
    return (
      fullName: (map['full_name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      stars: (map['stargazers_count'] as num?)?.toInt() ?? 0,
      language: (map['language'] ?? '-').toString(),
    );
  }).toList();
}

typedef _RepoMetricsRecord = ({
  String fullName,
  int stars,
  int forks,
  int openIssues,
  String pushedAt,
});

_RepoMetricsRecord _toRepoMetricsRecord(Map<String, dynamic>? raw) {
  final first = _firstRepoItem(raw);
  return (
    fullName: (first?['full_name'] ?? '-').toString(),
    stars: (first?['stargazers_count'] as num?)?.toInt() ?? 0,
    forks: (first?['forks_count'] as num?)?.toInt() ?? 0,
    openIssues: (first?['open_issues_count'] as num?)?.toInt() ?? 0,
    pushedAt: (first?['pushed_at'] ?? '-').toString(),
  );
}

HttpRequestConfig _searchConfig({
  required String query,
  required int page,
  required int perPage,
}) {
  return HttpRequestConfig.get(
    '/search/repositories',
    headers: _githubHeaders,
    queryParameters: {
      'q': query,
      'sort': 'stars',
      'order': 'desc',
      'per_page': perPage,
      'page': page,
    },
  );
}

HttpRequestConfig _repoConfig(String fullName, {required bool forceError}) {
  if (forceError) {
    return HttpRequestConfig.get(
      '/search/repositories-invalid',
      headers: _githubHeaders,
    );
  }

  return _searchConfig(query: fullName, page: 1, perPage: 1);
}

Map<String, dynamic>? _firstRepoItem(Map<String, dynamic>? raw) {
  final items = raw?['items'];
  if (items is! List || items.isEmpty || items.first is! Map) {
    return null;
  }
  return (items.first as Map).cast<String, dynamic>();
}

Map<String, dynamic> _mergeSearchResult(
  Map<String, dynamic>? previous,
  Map<String, dynamic> next,
) {
  final previousItems = previous?['items'] as List? ?? const [];
  final nextItems = next['items'] as List? ?? const [];

  return <String, dynamic>{
    ...next,
    'items': <dynamic>[...previousItems, ...nextItems],
  };
}

bool _hasMoreSearchResult(Map<String, dynamic>? data) {
  final totalCount = (data?['total_count'] as num?)?.toInt() ?? 0;
  final currentCount = (data?['items'] as List?)?.length ?? 0;
  return currentCount < totalCount && currentCount < 80;
}

String _boolCode(bool value) => value ? 'true' : 'false';

String _buildLevel1Source({
  required String username,
  required bool ready,
  required int loadingDelayMs,
}) {
  return '''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  profileService,
  options: UseRequestOptions(
    manual: false,
    ready: ${_boolCode(ready)},
    defaultParams: _searchConfig(
      query: 'user:$username',
      page: 1,
      perPage: 1,
    ),
    refreshDeps: ['$username'],
    loadingDelay: Duration(milliseconds: $loadingDelayMs),
    onBefore: (_) => log('onBefore search user:$username'),
    onSuccess: (data, _) => log('onSuccess items=\${(data['items'] as List?)?.length ?? 0}'),
    onError: (error, _) => log('onError: \$error'),
  ),
);
''';
}

String _buildLevel2Source({
  required String query,
  required int perPage,
  required _RateMode mode,
  required int intervalMs,
  required bool leading,
  required bool trailing,
  required bool useMaxWait,
  required int maxWaitMs,
  required bool keepPrevious,
  required int loadingDelay,
}) {
  final debounceLine = mode == _RateMode.debounce
      ? 'Duration(milliseconds: $intervalMs)'
      : 'null';
  final throttleLine = mode == _RateMode.throttle
      ? 'Duration(milliseconds: $intervalMs)'
      : 'null';
  final maxWaitLine = mode == _RateMode.debounce && useMaxWait
      ? 'Duration(milliseconds: $maxWaitMs)'
      : 'null';

  return '''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  searchService,
  options: UseRequestOptions(
    manual: false,
    defaultParams: _searchConfig(
      query: '$query',
      page: 1,
      perPage: $perPage,
    ),
    refreshDeps: ['$query', ${mode == _RateMode.debounce ? "'debounce'" : "'throttle'"}, $intervalMs],
    keepPreviousData: ${_boolCode(keepPrevious)},
    debounceInterval: $debounceLine,
    debounceLeading: ${_boolCode(leading)},
    debounceTrailing: ${_boolCode(trailing)},
    debounceMaxWait: $maxWaitLine,
    throttleInterval: $throttleLine,
    throttleLeading: ${_boolCode(leading)},
    throttleTrailing: ${_boolCode(trailing)},
    loadingDelay: Duration(milliseconds: $loadingDelay),
  ),
);
''';
}

String _buildLevel3Source({
  required String repo,
  required bool pollingEnabled,
  required int pollingInterval,
  required bool pollingWhenHidden,
  required bool pausePollingOnError,
  required int pollingRetryInterval,
  required int retryCount,
  required int retryInterval,
  required bool retryExponential,
  required int timeoutSec,
  required bool forceError,
}) {
  return '''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  repoService,
  options: UseRequestOptions(
    manual: false,
    defaultParams: _repoConfig('$repo', forceError: ${_boolCode(forceError)}),
    refreshDeps: ['$repo', ${_boolCode(forceError)}],
    pollingInterval: ${pollingEnabled ? 'Duration(seconds: $pollingInterval)' : 'null'},
    pollingWhenHidden: ${_boolCode(pollingWhenHidden)},
    pausePollingOnError: ${_boolCode(pausePollingOnError)},
    pollingRetryInterval: Duration(seconds: $pollingRetryInterval),
    retryCount: $retryCount,
    retryInterval: Duration(milliseconds: $retryInterval),
    retryExponential: ${_boolCode(retryExponential)},
    connectTimeout: Duration(seconds: $timeoutSec),
    receiveTimeout: Duration(seconds: $timeoutSec),
    sendTimeout: Duration(seconds: $timeoutSec),
    onRetryAttempt: (attempt, error) => log('retry #\$attempt: \$error'),
  ),
);
''';
}

String _buildLevel4Source({
  required String query,
  required String sort,
  required String order,
  required int perPage,
  required bool manual,
  required bool ready,
  required bool useInitialData,
  required bool keepPreviousData,
  required bool refreshDepsEnabled,
  required bool customRefreshDepsAction,
  required int depsVersion,
  required bool pollingEnabled,
  required int pollingInterval,
  required bool pollingWhenHidden,
  required bool pausePollingOnError,
  required int pollingRetryInterval,
  required _RateMode rateMode,
  required int rateInterval,
  required bool debounceLeading,
  required bool debounceTrailing,
  required bool debounceMaxWaitEnabled,
  required int debounceMaxWait,
  required bool throttleLeading,
  required bool throttleTrailing,
  required bool retryEnabled,
  required int retryCount,
  required int retryInterval,
  required bool retryExponential,
  required int connectTimeout,
  required int receiveTimeout,
  required int sendTimeout,
  required int loadingDelay,
  required bool refreshOnFocus,
  required bool refreshOnReconnect,
  required bool cacheEnabled,
  required int cacheTime,
  required int staleTime,
  required bool fetchKeyByQuery,
  required bool loadMoreEnabled,
  required bool externalCancelEnabled,
  required bool callbacksEnabled,
  required bool forceError,
}) {
  final debounceInterval = rateMode == _RateMode.debounce
      ? 'Duration(milliseconds: $rateInterval)'
      : 'null';
  final throttleInterval = rateMode == _RateMode.throttle
      ? 'Duration(milliseconds: $rateInterval)'
      : 'null';
  final debounceMaxWaitLine = debounceMaxWaitEnabled
      ? 'Duration(milliseconds: $debounceMaxWait)'
      : 'null';

  return '''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  searchService,
  options: UseRequestOptions(
    manual: ${_boolCode(manual)},
    ready: ${_boolCode(ready)},
    defaultParams: buildSearchParams(page: 1), // q=$query sort=$sort order=$order per_page=$perPage
    initialData: ${_boolCode(useInitialData)} ? {'items': []} : null,
    keepPreviousData: ${_boolCode(keepPreviousData)},
    refreshDeps: ${_boolCode(refreshDepsEnabled)} ? ['$query', '$sort', '$order', $perPage, $depsVersion] : null,
    refreshDepsAction: ${_boolCode(customRefreshDepsAction)} ? () => requestRef.value?.run(buildSearchParams(page: 1)) : null,
    pollingInterval: ${pollingEnabled ? 'Duration(seconds: $pollingInterval)' : 'null'},
    pollingWhenHidden: ${_boolCode(pollingWhenHidden)},
    pausePollingOnError: ${_boolCode(pausePollingOnError)},
    pollingRetryInterval: Duration(seconds: $pollingRetryInterval),
    debounceInterval: $debounceInterval,
    debounceLeading: ${_boolCode(debounceLeading)},
    debounceTrailing: ${_boolCode(debounceTrailing)},
    debounceMaxWait: $debounceMaxWaitLine,
    throttleInterval: $throttleInterval,
    throttleLeading: ${_boolCode(throttleLeading)},
    throttleTrailing: ${_boolCode(throttleTrailing)},
    retryCount: ${retryEnabled ? '$retryCount' : 'null'},
    retryInterval: ${retryEnabled ? 'Duration(milliseconds: $retryInterval)' : 'null'},
    retryExponential: ${_boolCode(retryExponential)},
    connectTimeout: Duration(seconds: $connectTimeout),
    receiveTimeout: Duration(seconds: $receiveTimeout),
    sendTimeout: Duration(seconds: $sendTimeout),
    loadingDelay: Duration(milliseconds: $loadingDelay),
    refreshOnFocus: ${_boolCode(refreshOnFocus)},
    refreshOnReconnect: ${_boolCode(refreshOnReconnect)},
    cacheKey: ${_boolCode(cacheEnabled)} ? (params) => 'gh:\${params.queryParameters}' : null,
    cacheTime: ${cacheEnabled ? 'Duration(seconds: $cacheTime)' : 'null'},
    staleTime: ${cacheEnabled ? 'Duration(seconds: $staleTime)' : 'null'},
    fetchKey: ${_boolCode(fetchKeyByQuery)} ? (params) => 'q:\${params.queryParameters?['q']}' : null,
    loadMoreParams: ${_boolCode(loadMoreEnabled)} ? (lastParams, _) => nextPage(lastParams) : null,
    dataMerger: ${_boolCode(loadMoreEnabled)} ? _mergeSearchResult : null,
    hasMore: ${_boolCode(loadMoreEnabled)} ? _hasMoreSearchResult : null,
    cancelToken: ${_boolCode(externalCancelEnabled)} ? externalToken : null,
    onBefore: ${_boolCode(callbacksEnabled)} ? (params) => log('onBefore') : null,
    onSuccess: ${_boolCode(callbacksEnabled)} ? (data, params) => log('onSuccess') : null,
    onError: ${_boolCode(callbacksEnabled)} ? (error, params) => log('onError \$error') : null,
    onFinally: ${_boolCode(callbacksEnabled)} ? (params, data, error) => log('onFinally') : null,
  ),
);
// forceError = ${_boolCode(forceError)}
''';
}

const String _sourceLevel1 = r'''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  profileService,
  options: UseRequestOptions(
    manual: false,
    ready: ready.value,
    defaultParams: _searchConfig(
      query: 'user:${username.value}',
      page: 1,
      perPage: 1,
    ),
    refreshDeps: [username.value],
    loadingDelay: Duration(milliseconds: loadingDelayMs.value.toInt()),
    onBefore: (_) => log('onBefore'),
    onSuccess: (_, __) => log('onSuccess'),
    onError: (error, _) => log('onError: $error'),
  ),
);
''';

const String _sourceLevel2 = r'''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  searchService,
  options: UseRequestOptions(
    manual: false,
    defaultParams: _searchConfig(
      query: query.value,
      page: 1,
      perPage: perPage.value.toInt(),
    ),
    refreshDeps: [query.value, mode.value, intervalMs.value.toInt()],
    keepPreviousData: keepPrevious.value,

    // 互斥：二选一
    debounceInterval: mode.value == _RateMode.debounce
        ? Duration(milliseconds: intervalMs.value.toInt())
        : null,
    debounceLeading: leading.value,
    debounceTrailing: trailing.value,
    debounceMaxWait: useMaxWait.value
        ? Duration(milliseconds: maxWaitMs.value.toInt())
        : null,

    throttleInterval: mode.value == _RateMode.throttle
        ? Duration(milliseconds: intervalMs.value.toInt())
        : null,
    throttleLeading: leading.value,
    throttleTrailing: trailing.value,
  ),
);
''';

const String _sourceLevel3 = r'''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  repoService,
  options: UseRequestOptions(
    defaultParams: _repoConfig(repo.value, forceError: forceError.value),
    refreshDeps: [repo.value, forceError.value],

    pollingInterval: pollingEnabled.value
        ? Duration(seconds: pollingInterval.value.toInt())
        : null,
    pollingWhenHidden: pollingWhenHidden.value,
    pausePollingOnError: pausePollingOnError.value,
    pollingRetryInterval: Duration(seconds: pollingRetryInterval.value.toInt()),

    retryCount: retryCount.value.toInt(),
    retryInterval: Duration(milliseconds: retryInterval.value.toInt()),
    retryExponential: retryExponential.value,
    onRetryAttempt: (attempt, error) => log('retry #$attempt: $error'),

    connectTimeout: Duration(seconds: timeoutSec.value.toInt()),
    receiveTimeout: Duration(seconds: timeoutSec.value.toInt()),
    sendTimeout: Duration(seconds: timeoutSec.value.toInt()),

    onError: (error, _) => log('error: $error'),
  ),
);
''';

const String _sourceLevel4 = r'''
final request = useRequest<Map<String, dynamic>, HttpRequestConfig>(
  searchService,
  options: UseRequestOptions(
    // 基础
    manual: manual.value,
    ready: ready.value,
    defaultParams: buildSearchParams(page: 1),
    initialData: useInitialData.value ? {'items': []} : null,
    keepPreviousData: keepPreviousData.value,

    // 依赖刷新
    refreshDeps: refreshDepsEnabled.value ? [query.value, depsVersion.value] : null,
    refreshDepsAction: customRefreshDepsAction.value
        ? () => requestRef.value?.run(buildSearchParams(page: 1))
        : null,

    // 轮询
    pollingInterval: pollingEnabled.value
        ? Duration(seconds: pollingInterval.value.toInt())
        : null,
    pollingWhenHidden: pollingWhenHidden.value,
    pausePollingOnError: pausePollingOnError.value,
    pollingRetryInterval: Duration(seconds: pollingRetryInterval.value.toInt()),

    // 防抖 / 节流
    debounceInterval: rateMode.value == _RateMode.debounce
        ? Duration(milliseconds: rateInterval.value.toInt())
        : null,
    debounceLeading: debounceLeading.value,
    debounceTrailing: debounceTrailing.value,
    debounceMaxWait: debounceMaxWaitEnabled.value
        ? Duration(milliseconds: debounceMaxWait.value.toInt())
        : null,
    throttleInterval: rateMode.value == _RateMode.throttle
        ? Duration(milliseconds: rateInterval.value.toInt())
        : null,
    throttleLeading: throttleLeading.value,
    throttleTrailing: throttleTrailing.value,

    // 重试 + 超时
    retryCount: retryEnabled.value ? retryCount.value.toInt() : null,
    retryInterval: retryEnabled.value
        ? Duration(milliseconds: retryInterval.value.toInt())
        : null,
    retryExponential: retryExponential.value,
    connectTimeout: Duration(seconds: connectTimeout.value.toInt()),
    receiveTimeout: Duration(seconds: receiveTimeout.value.toInt()),
    sendTimeout: Duration(seconds: sendTimeout.value.toInt()),

    // 加载与刷新
    loadingDelay: Duration(milliseconds: loadingDelay.value.toInt()),
    refreshOnFocus: refreshOnFocus.value,
    refreshOnReconnect: refreshOnReconnect.value,
    reconnectStream: reconnectController.stream,

    // 缓存 + 并发
    cacheKey: cacheEnabled.value ? (params) => 'gh:${params.queryParameters}' : null,
    cacheTime: cacheEnabled.value ? Duration(seconds: cacheTime.value.toInt()) : null,
    staleTime: cacheEnabled.value ? Duration(seconds: staleTime.value.toInt()) : null,
    fetchKey: fetchKeyByQuery.value ? (params) => 'q:${params.queryParameters?['q']}' : null,

    // 加载更多
    loadMoreParams: loadMoreEnabled.value
        ? (lastParams, _) => lastParams.copyWith(
            queryParameters: {
              ...?lastParams.queryParameters,
              'page': ((lastParams.queryParameters?['page'] as num?)?.toInt() ?? 1) + 1,
            },
          )
        : null,
    dataMerger: loadMoreEnabled.value ? _mergeSearchResult : null,
    hasMore: loadMoreEnabled.value ? _hasMoreSearchResult : null,

    // 取消与回调
    cancelToken: externalCancelEnabled.value ? externalToken : null,
    onBefore: callbacksEnabled.value ? (_, ) => log('onBefore') : null,
    onSuccess: callbacksEnabled.value ? (_, __) => log('onSuccess') : null,
    onError: callbacksEnabled.value ? (error, _) => log('onError: $error') : null,
    onFinally: callbacksEnabled.value ? (_, __, ___) => log('onFinally') : null,
  ),
);
''';
