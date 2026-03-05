import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

class RetryDemo extends HookWidget {
  const RetryDemo({super.key});

  Future<Map<String, dynamic>> _fetchWithError(bool shouldFail) async {
    final dio = Dio();
    if (shouldFail) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        error: '模拟网络错误',
        type: DioExceptionType.connectionTimeout,
      );
    }
    final res = await dio.get('https://jsonplaceholder.typicode.com/users/1');
    return res.data as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final shouldFail = useState(true);

    // 可配置参数
    final retryCountOpt = useState(3);
    final retryIntervalOpt = useState(1000); // ms
    final retryExponential = useState(true);

    // 可视化状态
    final currentAttempt = useState(0);
    final retryLog = useState<List<String>>([]);
    final lastStartMs = useState<int>(0);

    final retryCountOptions = [1, 2, 3, 5];
    final retryIntervalOptions = [500, 1000, 2000];

    final request = useRequest<Map<String, dynamic>, bool>(
      _fetchWithError,
      options: UseRequestOptions(
        manual: true,
        retryCount: retryCountOpt.value,
        retryInterval: Duration(milliseconds: retryIntervalOpt.value),
        retryExponential: retryExponential.value,
        onBefore: (_) {
          currentAttempt.value = 0;
          retryLog.value = [];
          lastStartMs.value = DateTime.now().millisecondsSinceEpoch;
        },
        onRetryAttempt: (attempt, error) {
          currentAttempt.value = attempt;
          final elapsed =
              DateTime.now().millisecondsSinceEpoch - lastStartMs.value;

          // 计算本次预计间隔（用于日志展示）
          int expectedInterval;
          if (retryExponential.value) {
            // 指数退避: interval * 2^(attempt-1)
            expectedInterval =
                retryIntervalOpt.value * (1 << (attempt - 1)).clamp(1, 32);
          } else {
            expectedInterval = retryIntervalOpt.value;
          }

          final now = DateTime.now();
          final ts =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

          retryLog.value = [
            ...retryLog.value,
            '$ts  第$attempt次重试  已用${elapsed}ms  下次间隔≈${expectedInterval}ms',
          ];
        },
        onSuccess: (_, _) {
          final now = DateTime.now();
          final ts =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
          retryLog.value = [...retryLog.value, '$ts  ✅ 请求成功'];
        },
        onError: (error, _) {
          final now = DateTime.now();
          final ts =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
          retryLog.value = [
            ...retryLog.value,
            '$ts  ❌ 最终失败，已重试${currentAttempt.value}次',
          ];
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 说明 ──
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '失败重试：可配置重试次数、间隔、是否指数退避。实时日志展示每次重试时间点。',
            style: TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 20),

        // ── 配置区 ──
        const Text(
          '配置参数',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 12),

        // retryCount
        const Text('retryCount（最大重试次数）:', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: retryCountOptions.map((n) {
            return ChoiceChip(
              label: Text('$n 次'),
              selected: retryCountOpt.value == n,
              onSelected: (_) => retryCountOpt.value = n,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // retryInterval
        const Text('retryInterval（基础间隔）:', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: retryIntervalOptions.map((ms) {
            return ChoiceChip(
              label: Text('${ms}ms'),
              selected: retryIntervalOpt.value == ms,
              onSelected: (_) => retryIntervalOpt.value = ms,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // retryExponential
        Row(
          children: [
            FilterChip(
              label: const Text('retryExponential（指数退避）'),
              selected: retryExponential.value,
              onSelected: (v) => retryExponential.value = v,
              selectedColor: Colors.purple[100],
              checkmarkColor: Colors.purple[700],
            ),
          ],
        ),
        if (retryExponential.value)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '间隔依次为: ${_buildBackoffPreview(retryIntervalOpt.value, retryCountOpt.value)}',
              style: TextStyle(fontSize: 12, color: Colors.purple[700]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '固定间隔: 每次 ${retryIntervalOpt.value}ms',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        const SizedBox(height: 20),

        // ── 模拟开关 ──
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('模拟请求失败'),
            subtitle: Text(
              shouldFail.value ? '请求将失败并重试' : '请求将成功',
              style: const TextStyle(fontSize: 12),
            ),
            value: shouldFail.value,
            onChanged: (v) => shouldFail.value = v,
          ),
        ),
        const SizedBox(height: 16),

        // ── 状态显示 ──
        if (request.loading) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '请求中...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (currentAttempt.value > 0)
                      Text(
                        '正在重试: ${currentAttempt.value}/${retryCountOpt.value}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (request.error != null && !request.loading) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '最终失败',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        '已重试 ${currentAttempt.value} 次',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (request.data != null && !request.loading) ...[
          Container(
            padding: const EdgeInsets.all(14),
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
                    Icon(
                      Icons.check_circle,
                      color: Colors.green[700],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '请求成功',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '用户名: ${request.data!['name']}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Email: ${request.data!['email']}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── 触发按钮 ──
        ElevatedButton.icon(
          onPressed: request.loading
              ? null
              : () => request.run(shouldFail.value),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('发起请求'),
        ),
        const SizedBox(height: 20),

        // ── 重试日志 ──
        if (retryLog.value.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.list_alt, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              const Text(
                '重试日志',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => retryLog.value = [],
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: retryLog.value
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.greenAccent,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// 生成指数退避间隔预览字符串
  String _buildBackoffPreview(int baseMs, int count) {
    final parts = <String>[];
    for (var i = 0; i < count; i++) {
      final interval = baseMs * (1 << i).clamp(1, 32);
      parts.add('${interval}ms');
    }
    return parts.join(' → ');
  }
}
