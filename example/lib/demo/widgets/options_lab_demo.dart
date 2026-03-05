import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

// ── 共用服务函数 ──────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> _fetchUser(int userId) async {
  final res = await Dio().get(
    'https://jsonplaceholder.typicode.com/users/$userId',
  );
  return res.data as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _fetchUserSlowly(int userId) async {
  await Future.delayed(const Duration(milliseconds: 600));
  final res = await Dio().get(
    'https://jsonplaceholder.typicode.com/users/$userId',
  );
  return res.data as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _fetchUserVerySlow(int userId) async {
  await Future.delayed(const Duration(seconds: 4));
  final res = await Dio().get(
    'https://jsonplaceholder.typicode.com/users/$userId',
  );
  return res.data as Map<String, dynamic>;
}

Future<List<dynamic>> _fetchByTopic(String topic) async {
  final res = await Dio().get(
    'https://jsonplaceholder.typicode.com/$topic?_limit=5',
  );
  return res.data as List<dynamic>;
}

// ── 主入口组件 ────────────────────────────────────────────────────────────────

/// Options 实验室：在一个页面里交互演示 ready / initialData / keepPreviousData /
/// loadingDelay / refreshDeps / mutate / cancel 等配置
class OptionsLabDemo extends StatelessWidget {
  const OptionsLabDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReadySection(),
        SizedBox(height: 24),
        _DataControlSection(),
        SizedBox(height: 24),
        _LoadingDelaySection(),
        SizedBox(height: 24),
        _RefreshDepsSection(),
        SizedBox(height: 24),
        _MutateSection(),
        SizedBox(height: 24),
        _CancelSection(),
      ],
    );
  }
}

// ── 共用小组件 ────────────────────────────────────────────────────────────────

class _SubSectionTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SubSectionTitle({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = Colors.indigo[700]!;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: c),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool faded;

  const _UserCard({this.data, this.faded = false});

  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox.shrink();
    return Opacity(
      opacity: faded ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.green[700]),
                const SizedBox(width: 6),
                Text(
                  data!['name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (faded) ...[
                  const SizedBox(width: 8),
                  Text(
                    '（旧数据）',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Email: ${data!['email'] ?? ''}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'ID: ${data!['id']} | ${data!['username'] ?? ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      selectedColor: Colors.blue[100],
      checkmarkColor: Colors.blue[700],
    );
  }
}

// ── ① ready ───────────────────────────────────────────────────────────────────

class _ReadySection extends HookWidget {
  const _ReadySection();

  @override
  Widget build(BuildContext context) {
    final ready = useState(false);

    final request = useRequest<Map<String, dynamic>, int>(
      _fetchUser,
      options: UseRequestOptions(
        manual: false,
        defaultParams: 1,
        ready: ready.value,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubSectionTitle(icon: Icons.lock_clock, label: 'ready — 就绪门控'),
          const SizedBox(height: 8),
          Text(
            'ready=false 时阻止自动请求；切换为 true 后立即触发。',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ToggleChip(
                label: 'ready = ${ready.value}',
                value: ready.value,
                onChanged: (v) => ready.value = v,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!ready.value)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: const Text('⏳ ready=false，请求被阻止，等待就绪...'),
            ),
          if (ready.value && request.loading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('请求中...'),
              ],
            ),
          if (request.data != null) _UserCard(data: request.data),
          if (request.error != null)
            Text(
              '错误: ${request.error}',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

// ── ② initialData + keepPreviousData ─────────────────────────────────────────

class _DataControlSection extends HookWidget {
  const _DataControlSection();

  @override
  Widget build(BuildContext context) {
    final userId = useState(1);
    final useInitialData = useState(false);
    final keepPrev = useState(false);

    final initialData = useInitialData.value
        ? <String, dynamic>{
            'id': 0,
            'name': '📦 占位数据（initialData）',
            'email': 'placeholder@example.com',
            'username': 'placeholder',
          }
        : null;

    final request = useRequest<Map<String, dynamic>, int>(
      _fetchUser,
      options: UseRequestOptions(
        manual: false,
        defaultParams: userId.value,
        initialData: initialData,
        keepPreviousData: keepPrev.value,
        refreshDeps: [userId.value],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubSectionTitle(
            icon: Icons.inventory_2_outlined,
            label: 'initialData + keepPreviousData',
          ),
          const SizedBox(height: 8),
          Text(
            'initialData 提供首屏占位；keepPreviousData 切换参数时保留旧数据。',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          // 用户选择
          const Text('选择用户:', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List.generate(5, (i) {
              final id = i + 1;
              return ChoiceChip(
                label: Text('用户 $id'),
                selected: userId.value == id,
                onSelected: (_) => userId.value = id,
              );
            }),
          ),
          const SizedBox(height: 12),
          // 配置开关
          Wrap(
            spacing: 8,
            children: [
              _ToggleChip(
                label: 'initialData',
                value: useInitialData.value,
                onChanged: (v) => useInitialData.value = v,
              ),
              _ToggleChip(
                label: 'keepPreviousData',
                value: keepPrev.value,
                onChanged: (v) => keepPrev.value = v,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (request.loading)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  keepPrev.value ? '加载中（保留旧数据）...' : '加载中...',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          if (request.data != null)
            _UserCard(
              data: request.data,
              faded: request.loading && keepPrev.value,
            ),
          if (request.error != null)
            Text(
              '错误: ${request.error}',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

// ── ③ loadingDelay ────────────────────────────────────────────────────────────

class _LoadingDelaySection extends HookWidget {
  const _LoadingDelaySection();

  @override
  Widget build(BuildContext context) {
    // 服务耗时 600ms，loadingDelay 设为不同值观察 loading 是否出现
    final delayMs = useState(0);
    final delayOptions = [0, 400, 800];

    final request = useRequest<Map<String, dynamic>, int>(
      _fetchUserSlowly,
      options: UseRequestOptions(
        manual: true,
        loadingDelay: Duration(milliseconds: delayMs.value),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubSectionTitle(
            icon: Icons.timer_outlined,
            label: 'loadingDelay — 防闪烁',
          ),
          const SizedBox(height: 8),
          Text(
            '服务耗时约 600ms。loadingDelay > 600ms 时 loading 永远不会出现。',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          const Text('loadingDelay:', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: delayOptions.map((ms) {
              return ChoiceChip(
                label: Text('${ms}ms'),
                selected: delayMs.value == ms,
                onSelected: (_) => delayMs.value = ms,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: request.loading ? null : () => request.run(1),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('发起请求'),
              ),
              const SizedBox(width: 12),
              if (request.loading)
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Loading 可见 ✓'),
                  ],
                )
              else if (!request.loading &&
                  request.data == null &&
                  !request.loading)
                Text(
                  delayMs.value > 0 ? '（loading 被延迟 ${delayMs.value}ms）' : '',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
            ],
          ),
          if (request.data != null) ...[
            const SizedBox(height: 8),
            _UserCard(data: request.data),
          ],
          if (request.error != null)
            Text(
              '错误: ${request.error}',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

// ── ④ refreshDeps ─────────────────────────────────────────────────────────────

class _RefreshDepsSection extends HookWidget {
  const _RefreshDepsSection();

  @override
  Widget build(BuildContext context) {
    final topic = useState('posts');
    final topics = ['posts', 'comments', 'todos', 'albums'];

    final request = useRequest<List<dynamic>, String>(
      _fetchByTopic,
      options: UseRequestOptions(
        manual: false,
        defaultParams: topic.value,
        refreshDeps: [topic.value],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubSectionTitle(
            icon: Icons.sync_alt,
            label: 'refreshDeps — 依赖变化自动刷新',
          ),
          const SizedBox(height: 8),
          Text(
            '切换主题时 refreshDeps 触发，自动重新请求对应数据。',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: topics.map((t) {
              return ChoiceChip(
                label: Text(t),
                selected: topic.value == t,
                onSelected: (_) => topic.value = t,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (request.loading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('加载中...'),
              ],
            ),
          if (request.data != null && !request.loading) ...[
            Text(
              '${topic.value} 数据（前5条）：',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ...request.data!.take(3).map((item) {
              final map = item as Map<String, dynamic>;
              final title = map['title'] ?? map['name'] ?? map['body'] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: Colors.blue[700])),
                    Expanded(
                      child: Text(
                        title.toString().length > 60
                            ? '${title.toString().substring(0, 60)}...'
                            : title.toString(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (request.data!.length > 3)
              Text(
                '... 共 ${request.data!.length} 条',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
          ],
          if (request.error != null)
            Text(
              '错误: ${request.error}',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

// ── ⑤ mutate ─────────────────────────────────────────────────────────────────

class _MutateSection extends HookWidget {
  const _MutateSection();

  @override
  Widget build(BuildContext context) {
    final request = useRequest<Map<String, dynamic>, int>(
      _fetchUser,
      options: const UseRequestOptions(manual: false, defaultParams: 1),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubSectionTitle(
            icon: Icons.edit_note,
            label: 'mutate — 本地数据变更',
          ),
          const SizedBox(height: 8),
          Text(
            'mutate() 直接修改本地数据，不发送网络请求；refresh() 恢复真实数据。',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          if (request.loading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('加载中...'),
              ],
            ),
          if (request.data != null) _UserCard(data: request.data),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: request.data == null
                    ? null
                    : () => request.mutate(
                        (old) =>
                            old == null ? old : {...old, 'name': '✏️ 已本地修改姓名'},
                      ),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('修改名字'),
              ),
              OutlinedButton.icon(
                onPressed: request.data == null
                    ? null
                    : () => request.mutate(
                        (old) => old == null
                            ? old
                            : {...old, 'email': '📧 local@mutate.dev'},
                      ),
                icon: const Icon(Icons.email, size: 16),
                label: const Text('改邮箱'),
              ),
              ElevatedButton.icon(
                onPressed: request.loading ? null : () => request.refresh(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('恢复真实数据'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '※ 修改操作不发送网络请求',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          if (request.error != null)
            Text(
              '错误: ${request.error}',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

// ── ⑥ cancel ─────────────────────────────────────────────────────────────────

class _CancelSection extends HookWidget {
  const _CancelSection();

  @override
  Widget build(BuildContext context) {
    final elapsedMs = useState(0);
    final status = useState<String>(
      'idle',
    ); // idle | loading | cancelled | done
    final timerRef = useRef<Timer?>(null);

    // 清理 timer
    useEffect(() {
      return () => timerRef.value?.cancel();
    }, const []);

    void startTimer() {
      elapsedMs.value = 0;
      timerRef.value?.cancel();
      timerRef.value = Timer.periodic(const Duration(milliseconds: 100), (_) {
        elapsedMs.value += 100;
      });
    }

    void stopTimer() {
      timerRef.value?.cancel();
      timerRef.value = null;
    }

    final request = useRequest<Map<String, dynamic>, int>(
      _fetchUserVerySlow,
      options: UseRequestOptions(
        manual: true,
        onBefore: (_) {
          status.value = 'loading';
          startTimer();
        },
        onSuccess: (_, _) {
          status.value = 'done';
          stopTimer();
        },
        onError: (err, _) {
          final dioErr = err;
          if (dioErr is DioException &&
              dioErr.type == DioExceptionType.cancel) {
            status.value = 'cancelled';
          } else {
            status.value = 'idle';
          }
          stopTimer();
        },
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SubSectionTitle(
            icon: Icons.cancel_outlined,
            label: 'cancel — 取消请求',
          ),
          const SizedBox(height: 8),
          Text(
            '服务耗时约 4s，可在进行中点击取消。',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          // 状态指示
          _CancelStatusBadge(status: status.value, elapsedMs: elapsedMs.value),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: request.loading
                    ? null
                    : () {
                        status.value = 'idle';
                        request.run(1);
                      },
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('发起请求（4s）'),
              ),
              OutlinedButton.icon(
                onPressed: !request.loading ? null : () => request.cancel(),
                icon: const Icon(Icons.stop, size: 16),
                label: const Text('取消'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
          ),
          if (request.data != null && status.value == 'done') ...[
            const SizedBox(height: 8),
            _UserCard(data: request.data),
          ],
        ],
      ),
    );
  }
}

class _CancelStatusBadge extends StatelessWidget {
  final String status;
  final int elapsedMs;

  const _CancelStatusBadge({required this.status, required this.elapsedMs});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'loading':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.orange[200]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '请求中... ${(elapsedMs / 1000).toStringAsFixed(1)}s',
                style: TextStyle(color: Colors.orange[800]),
              ),
            ],
          ),
        );
      case 'cancelled':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.red[200]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel, size: 16, color: Colors.red[700]),
              const SizedBox(width: 8),
              Text(
                '已取消（用时 ${(elapsedMs / 1000).toStringAsFixed(1)}s）',
                style: TextStyle(color: Colors.red[700]),
              ),
            ],
          ),
        );
      case 'done':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
              const SizedBox(width: 8),
              Text(
                '请求成功（用时 ${(elapsedMs / 1000).toStringAsFixed(1)}s）',
                style: TextStyle(color: Colors.green[700]),
              ),
            ],
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('空闲', style: TextStyle(color: Colors.grey[600])),
        );
    }
  }
}
