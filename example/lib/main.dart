import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:use_request/use_request.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

const Map<String, dynamic> _githubHeaders = {
  'Accept': 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'use-request-example',
};

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.enableAutoNetwork = true});

  final bool enableAutoNetwork;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'use_request Progressive Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: ProgressiveExamplePage(enableAutoNetwork: enableAutoNetwork),
    );
  }
}

/// 示例首页（由易到难）
///
/// 设计目标：
/// 1. 用真实公共 API（GitHub REST）演示网络请求。
/// 2. 展示 hooks + useRequest 的数据流转。
/// 3. 展示 Dart Record 解构如何用于渲染层。
class ProgressiveExamplePage extends StatelessWidget {
  const ProgressiveExamplePage({super.key, this.enableAutoNetwork = true});

  final bool enableAutoNetwork;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('useRequest 渐进式示例（GitHub API）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            level: 'Level 1',
            title: '基础自动请求 + Record 解构',
            description: '自动请求 GitHub 用户信息，演示 loading/error/data 三态。',
            child: BasicProfileDemo(enableAutoNetwork: enableAutoNetwork),
          ),
          SizedBox(height: 16),
          _SectionCard(
            level: 'Level 2',
            title: '手动请求 + 防抖 + 保留旧数据',
            description: '输入仓库关键字后查询，演示 debounce 与 keepPreviousData。',
            child: RepoSearchDemo(enableAutoNetwork: enableAutoNetwork),
          ),
          SizedBox(height: 16),
          _SectionCard(
            level: 'Level 3',
            title: '组合数据流（自动前置请求 + 手动触发）',
            description: '模拟业务流程：先拿上下文，再执行提交动作。',
            child: InquiryStyleFlowDemo(enableAutoNetwork: enableAutoNetwork),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.level,
    required this.title,
    required this.description,
    required this.child,
  });

  final String level;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(level, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

/// Level 1: 自动请求 GitHub 用户，展示最基础网络状态流。
class BasicProfileDemo extends HookWidget {
  const BasicProfileDemo({super.key, this.enableAutoNetwork = true});

  final bool enableAutoNetwork;

  @override
  Widget build(BuildContext context) {
    final http = useMemoized(
      () => DioHttpAdapter.withBaseUrl('https://api.github.com'),
    );
    final service = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        http,
        transformer: (res) => (res.data as Map).cast<String, dynamic>(),
      ),
      [http],
    );

    final req = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: UseRequestOptions(
        manual: !enableAutoNetwork,
        defaultParams: HttpRequestConfig.get(
          '/users/octocat',
          headers: _githubHeaders,
        ),
      ),
    );

    if (req.loading) {
      return const _HintBox(message: '请求中：正在获取 octocat 资料...');
    }
    if (req.error != null) {
      return _HintBox(message: '请求失败：${req.error}');
    }

    final profile = _toProfileRecord(req.data);
    final (:login, :followers, :avatarUrl, :bio) = profile;

    final avatar = avatarUrl.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
          child: avatar.isEmpty ? const Icon(Icons.person_outline) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('@$login', style: Theme.of(context).textTheme.titleMedium),
              Text('Followers: $followers'),
              const SizedBox(height: 4),
              Text(
                bio,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Level 2: 输入查询 + 手动触发请求。
///
/// 关键点：
/// - `manual: true`：由业务主动触发。
/// - `debounceInterval`：输入快速变化时自动防抖。
/// - `keepPreviousData`：新请求中保留旧列表，减少 UI 闪烁。
class RepoSearchDemo extends HookWidget {
  const RepoSearchDemo({super.key, this.enableAutoNetwork = true});

  final bool enableAutoNetwork;

  @override
  Widget build(BuildContext context) {
    final query = useState('flutter hooks');
    final http = useMemoized(
      () => DioHttpAdapter.withBaseUrl('https://api.github.com'),
    );
    final service = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        http,
        transformer: (res) => (res.data as Map).cast<String, dynamic>(),
      ),
      [http],
    );

    final req = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      service,
      options: const UseRequestOptions(
        manual: true,
        debounceInterval: Duration(milliseconds: 350),
        keepPreviousData: true,
      ),
    );

    useEffect(() {
      if (!enableAutoNetwork) {
        return null;
      }
      req.run(
        HttpRequestConfig.get(
          '/search/repositories',
          headers: _githubHeaders,
          queryParameters: {
            'q': query.value,
            'sort': 'stars',
            'order': 'desc',
            'per_page': 5,
          },
        ),
      );
      return null;
    }, [query.value]);

    final items = _toRepoItems(req.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: '仓库关键字',
            hintText: '例如: flutter hooks',
            border: OutlineInputBorder(),
          ),
          controller: useTextEditingController(text: query.value),
          onSubmitted: (value) {
            query.value = value.trim().isEmpty ? 'flutter hooks' : value.trim();
          },
        ),
        const SizedBox(height: 12),
        if (req.loading) const LinearProgressIndicator(),
        if (req.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('查询失败：${req.error}'),
          ),
        const SizedBox(height: 8),
        ...items.map(
          (repo) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(repo.fullName),
            subtitle: Text(repo.description),
            trailing: Text('★ ${repo.stars}'),
          ),
        ),
      ],
    );
  }
}

/// Level 3: 参考业务项目里的“前置请求 + 提交请求”思路。
///
/// 对应真实场景：
/// - 前置请求（自动）：获取上下文信息（示例里用 GitHub API 的 `zen`）。
/// - 提交请求（手动）：用户点击按钮后触发一次搜索请求，拼装并渲染结果。
class InquiryStyleFlowDemo extends HookWidget {
  const InquiryStyleFlowDemo({super.key, this.enableAutoNetwork = true});

  final bool enableAutoNetwork;

  @override
  Widget build(BuildContext context) {
    final keyword = useState('bug report');
    final http = useMemoized(
      () => DioHttpAdapter.withBaseUrl('https://api.github.com'),
    );

    final prefetchService = useMemoized(
      () => createDioService<String>(
        http,
        transformer: (res) => (res.data ?? '').toString(),
      ),
      [http],
    );
    final submitService = useMemoized(
      () => createDioService<Map<String, dynamic>>(
        http,
        transformer: (res) => (res.data as Map).cast<String, dynamic>(),
      ),
      [http],
    );

    final prefetch = useRequest<String, HttpRequestConfig>(
      prefetchService,
      options: UseRequestOptions(
        manual: !enableAutoNetwork,
        defaultParams: HttpRequestConfig.get('/zen', headers: _githubHeaders),
      ),
    );

    final submit = useRequest<Map<String, dynamic>, HttpRequestConfig>(
      submitService,
      options: const UseRequestOptions(manual: true),
    );

    Future<void> handleSubmit() {
      return submit.runAsync(
        HttpRequestConfig.get(
          '/search/issues',
          headers: _githubHeaders,
          queryParameters: {
            'q': '${keyword.value} repo:flutter/flutter is:issue',
            'per_page': 3,
          },
        ),
      );
    }

    final topIssue = _toTopIssueRecord(submit.data);
    final (:title, :url, :totalCount) = topIssue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('前置上下文（自动请求）: ${prefetch.data ?? '加载中...'}'),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: '模拟提交关键字',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => keyword.value = value,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: submit.loading ? null : handleSubmit,
          icon: const Icon(Icons.send),
          label: Text(submit.loading ? '提交中...' : '触发手动请求'),
        ),
        const SizedBox(height: 12),
        if (submit.error != null) Text('提交失败：${submit.error}'),
        if (submit.data != null)
          _HintBox(
            message:
                '总结果: $totalCount\nTop1: $title\n链接: $url\n\n这里演示了“自动前置 + 手动触发”的数据流转。',
          ),
      ],
    );
  }
}

class _HintBox extends StatelessWidget {
  const _HintBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message),
    );
  }
}

typedef GitHubProfileRecord = ({
  String login,
  int followers,
  String avatarUrl,
  String bio,
});

GitHubProfileRecord _toProfileRecord(Map<String, dynamic>? raw) {
  return (
    login: (raw?['login'] ?? 'unknown').toString(),
    followers: (raw?['followers'] as num?)?.toInt() ?? 0,
    avatarUrl: (raw?['avatar_url'] ?? '').toString(),
    bio: (raw?['bio'] ?? 'No bio').toString(),
  );
}

typedef RepoListItem = ({String fullName, String description, int stars});

List<RepoListItem> _toRepoItems(Map<String, dynamic>? raw) {
  final items = raw?['items'];
  if (items is! List) return const [];
  return items.map((item) {
    final map = item is Map
        ? item.cast<String, dynamic>()
        : <String, dynamic>{};
    return (
      fullName: (map['full_name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      stars: (map['stargazers_count'] as num?)?.toInt() ?? 0,
    );
  }).toList();
}

typedef TopIssueRecord = ({String title, String url, int totalCount});

TopIssueRecord _toTopIssueRecord(Map<String, dynamic>? raw) {
  final totalCount = (raw?['total_count'] as num?)?.toInt() ?? 0;
  final items = raw?['items'];
  if (items is! List || items.isEmpty || items.first is! Map) {
    return (title: '暂无结果', url: '-', totalCount: totalCount);
  }
  final first = (items.first as Map).cast<String, dynamic>();
  return (
    title: (first['title'] ?? '').toString(),
    url: (first['html_url'] ?? '').toString(),
    totalCount: totalCount,
  );
}
