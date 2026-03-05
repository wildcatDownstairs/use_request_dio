import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

// ── 共用服务（轻量 mock，避免真实网络依赖影响频率控制测试）─────────────────────

Future<String> _mockSearch(String query) async {
  await Future.delayed(const Duration(milliseconds: 200));
  return '结果：$query（${DateTime.now().millisecondsSinceEpoch}）';
}

// ── 主入口组件 ────────────────────────────────────────────────────────────────

/// 频率控制进阶：防抖高级选项（leading/trailing/maxWait）+ 节流（throttle）
class RateControlDemo extends StatelessWidget {
  const RateControlDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RateControlBody();
  }
}

class _RateControlBody extends HookWidget {
  const _RateControlBody();

  @override
  Widget build(BuildContext context) {
    final tabIndex = useState(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 模式切换
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('防抖进阶'),
              icon: Icon(Icons.hourglass_bottom, size: 16),
            ),
            ButtonSegment(
              value: 1,
              label: Text('节流'),
              icon: Icon(Icons.speed, size: 16),
            ),
          ],
          selected: {tabIndex.value},
          onSelectionChanged: (s) => tabIndex.value = s.first,
        ),
        const SizedBox(height: 20),
        IndexedStack(
          index: tabIndex.value,
          children: const [_DebounceAdvancedSection(), _ThrottleSection()],
        ),
      ],
    );
  }
}

// ── 共用计数 + 日志 UI ────────────────────────────────────────────────────────

class _CounterRow extends StatelessWidget {
  final int hitCount;
  final int execCount;

  const _CounterRow({required this.hitCount, required this.execCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.indigo[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          _CountBadge(label: '触发次数', count: hitCount, color: Colors.indigo),
          const SizedBox(width: 8),
          const Text('→', style: TextStyle(fontSize: 18, color: Colors.grey)),
          const SizedBox(width: 8),
          _CountBadge(label: '实际执行', count: execCount, color: Colors.green),
          if (hitCount > 0 && execCount > 0) ...[
            const SizedBox(width: 12),
            Text(
              '过滤率 ${((1 - execCount / hitCount) * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final MaterialColor color;

  const _CountBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color[700],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: color[400])),
      ],
    );
  }
}

class _ExecLog extends StatelessWidget {
  final List<String> logs;

  const _ExecLog({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Text(
        '（尚无执行记录）',
        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: logs
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '▸ $e',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── ① 防抖进阶 ────────────────────────────────────────────────────────────────

class _DebounceAdvancedSection extends HookWidget {
  const _DebounceAdvancedSection();

  @override
  Widget build(BuildContext context) {
    final intervalMs = useState(500);
    final leading = useState(false);
    final trailing = useState(true);
    final maxWaitMs = useState<int?>(null); // null = 关闭

    final hitCount = useState(0);
    final execCount = useState(0);
    final execLog = useState<List<String>>([]);

    final intervalOptions = [200, 500, 1000];
    final maxWaitOptions = <int?>[null, 2000, 5000];

    final request = useRequest<String, String>(
      _mockSearch,
      options: UseRequestOptions(
        manual: true,
        debounceInterval: Duration(milliseconds: intervalMs.value),
        debounceLeading: leading.value,
        debounceTrailing: trailing.value,
        debounceMaxWait: maxWaitMs.value != null
            ? Duration(milliseconds: maxWaitMs.value!)
            : null,
        onSuccess: (data, _) {
          execCount.value++;
          final now = TimeOfDay.fromDateTime(DateTime.now());
          final ts =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}';
          execLog.value = ['$ts → $data', ...execLog.value.take(4)];
        },
      ),
    );

    Future<void> burstTrigger() async {
      for (var i = 0; i < 10; i++) {
        hitCount.value++;
        request.run('连击#${hitCount.value}');
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // debounceInterval
        const Text('debounceInterval:', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: intervalOptions.map((ms) {
            return ChoiceChip(
              label: Text('${ms}ms'),
              selected: intervalMs.value == ms,
              onSelected: (_) => intervalMs.value = ms,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // leading / trailing toggles
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('debounceLeading'),
              selected: leading.value,
              onSelected: (v) => leading.value = v,
              selectedColor: Colors.blue[100],
            ),
            FilterChip(
              label: const Text('debounceTrailing'),
              selected: trailing.value,
              onSelected: (v) => trailing.value = v,
              selectedColor: Colors.blue[100],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // maxWait
        const Text('debounceMaxWait:', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: maxWaitOptions.map((ms) {
            final label = ms == null ? '关闭' : '${ms ~/ 1000}s';
            return ChoiceChip(
              label: Text(label),
              selected: maxWaitMs.value == ms,
              onSelected: (_) => maxWaitMs.value = ms,
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // 计数器
        _CounterRow(hitCount: hitCount.value, execCount: execCount.value),
        const SizedBox(height: 12),
        // 操作按钮
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                hitCount.value++;
                request.run('单次#${hitCount.value}');
              },
              icon: const Icon(Icons.touch_app, size: 16),
              label: const Text('触发一次'),
            ),
            OutlinedButton.icon(
              onPressed: () => burstTrigger(),
              icon: const Icon(Icons.fast_forward, size: 16),
              label: const Text('连击 ×10'),
            ),
            TextButton(
              onPressed: () {
                hitCount.value = 0;
                execCount.value = 0;
                execLog.value = [];
              },
              child: const Text('重置'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 执行日志
        const Text(
          '执行记录（最近5条）：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        _ExecLog(logs: execLog.value),
      ],
    );
  }
}

// ── ② 节流 ────────────────────────────────────────────────────────────────────

class _ThrottleSection extends HookWidget {
  const _ThrottleSection();

  @override
  Widget build(BuildContext context) {
    final intervalMs = useState(500);
    final leading = useState(true);
    final trailing = useState(true);

    final hitCount = useState(0);
    final execCount = useState(0);
    final execLog = useState<List<String>>([]);

    final intervalOptions = [200, 500, 1000];

    final request = useRequest<String, String>(
      _mockSearch,
      options: UseRequestOptions(
        manual: true,
        throttleInterval: Duration(milliseconds: intervalMs.value),
        throttleLeading: leading.value,
        throttleTrailing: trailing.value,
        onSuccess: (data, _) {
          execCount.value++;
          final now = TimeOfDay.fromDateTime(DateTime.now());
          final ts =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}';
          execLog.value = ['$ts → $data', ...execLog.value.take(4)];
        },
      ),
    );

    Future<void> burstTrigger() async {
      for (var i = 0; i < 10; i++) {
        hitCount.value++;
        request.run('连击#${hitCount.value}');
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // throttleInterval
        const Text('throttleInterval:', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: intervalOptions.map((ms) {
            return ChoiceChip(
              label: Text('${ms}ms'),
              selected: intervalMs.value == ms,
              onSelected: (_) => intervalMs.value = ms,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // leading / trailing
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('throttleLeading'),
              selected: leading.value,
              onSelected: (v) => leading.value = v,
              selectedColor: Colors.teal[100],
            ),
            FilterChip(
              label: const Text('throttleTrailing'),
              selected: trailing.value,
              onSelected: (v) => trailing.value = v,
              selectedColor: Colors.teal[100],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.teal[50],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'leading=true: 首次触发立即执行\n'
            'trailing=true: 间隔结束后执行最后一次\n'
            '两者都关闭则节流期间完全忽略调用',
            style: TextStyle(fontSize: 12, color: Colors.teal[800]),
          ),
        ),
        const SizedBox(height: 16),
        // 计数器
        _CounterRow(hitCount: hitCount.value, execCount: execCount.value),
        const SizedBox(height: 12),
        // 操作按钮
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                hitCount.value++;
                request.run('单次#${hitCount.value}');
              },
              icon: const Icon(Icons.touch_app, size: 16),
              label: const Text('触发一次'),
            ),
            OutlinedButton.icon(
              onPressed: () => burstTrigger(),
              icon: const Icon(Icons.fast_forward, size: 16),
              label: const Text('连击 ×10'),
            ),
            TextButton(
              onPressed: () {
                hitCount.value = 0;
                execCount.value = 0;
                execLog.value = [];
              },
              child: const Text('重置'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 执行日志
        const Text(
          '执行记录（最近5条）：',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        _ExecLog(logs: execLog.value),
      ],
    );
  }
}
