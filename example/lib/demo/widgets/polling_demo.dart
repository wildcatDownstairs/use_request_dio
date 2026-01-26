import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';
import 'package:visibility_detector/visibility_detector.dart';

class PollingDemo extends HookWidget {
  final bool enablePolling;
  const PollingDemo({super.key, this.enablePolling = true});

  Future<Map<String, dynamic>> _fetchRandomUser(int _) async {
    final dio = Dio();
    final randomId = DateTime.now().second % 10 + 1;
    final res = await dio.get(
      'https://jsonplaceholder.typicode.com/users/$randomId',
    );
    return {
      ...res.data as Map<String, dynamic>,
      'fetchTime': DateTime.now().toIso8601String(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final updateCount = useState(0);
    final ready = useState(enablePolling);
    final pollingEnabled = useState(enablePolling);
    final pollingWhenHidden = useState(false);
    final pauseOnError = useState(true);
    final autoRetry = useState(true);
    final isVisible = useState(true);

    final request = useRequest<Map<String, dynamic>, int>(
      _fetchRandomUser,
      options: UseRequestOptions(
        manual: false,
        ready: ready.value,
        defaultParams: 1,
        pollingInterval: pollingEnabled.value
            ? const Duration(seconds: 3)
            : null,
        pollingWhenHidden: pollingWhenHidden.value,
        pausePollingOnError: pauseOnError.value,
        pollingRetryInterval: autoRetry.value
            ? const Duration(seconds: 5)
            : null,
        refreshOnFocus: true,
        onSuccess: (data, params) {
          updateCount.value++;
        },
      ),
    );

    // Demo: 当滚出视口时暂停轮询，回到视口自动恢复（仅演示用）
    useEffect(() {
      if (!isVisible.value) {
        if (request.isPolling) {
          request.pausePolling();
        }
      } else {
        final shouldResume = ready.value && pollingEnabled.value;
        if (shouldResume && !request.isPolling) {
          request.resumePolling();
        }
      }
      return null;
    }, [isVisible.value, ready.value, pollingEnabled.value, request.isPolling]);

    return VisibilityDetector(
      key: const Key('polling-demo-visibility'),
      onVisibilityChanged: (info) {
        isVisible.value = info.visibleFraction > 0.01;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '说明：',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            '• pollingInterval: 3s - 每3秒自动刷新\n'
            '• refreshOnFocus: true - 应用回到前台时刷新\n'
            '• pollingWhenHidden=false 时后台暂停\n'
            '• pausePollingOnError=true 且 pollingRetryInterval=5s 时自动恢复\n'
            '• Demo 额外在滚出视口时暂停轮询',
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _ToggleChip(
                label: 'ready',
                value: ready.value,
                onChanged: (v) => ready.value = v,
              ),
              _ToggleChip(
                label: 'polling',
                value: pollingEnabled.value,
                onChanged: (v) => pollingEnabled.value = v,
              ),
              _ToggleChip(
                label: 'whenHidden',
                value: pollingWhenHidden.value,
                onChanged: (v) => pollingWhenHidden.value = v,
              ),
              _ToggleChip(
                label: 'pauseOnError',
                value: pauseOnError.value,
                onChanged: (v) => pauseOnError.value = v,
              ),
              _ToggleChip(
                label: 'autoRetry',
                value: autoRetry.value,
                onChanged: (v) => autoRetry.value = v,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: request.isPolling
                        ? Colors.green[50]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: request.isPolling
                          ? Colors.green[200]!
                          : Colors.grey[300]!,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: request.isPolling
                              ? Colors.green[400]
                              : Colors.grey[500],
                          shape: BoxShape.circle,
                        ),
                        child: request.isPolling
                            ? const Center(
                                child: SizedBox(
                                  width: 6,
                                  height: 6,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1,
                                    color: Colors.white,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.isPolling
                              ? '轮询中 - 已更新 ${updateCount.value} 次'
                              : ready.value
                              ? '未轮询（可能被暂停/不可见）'
                              : 'ready=false，已暂停',
                          style: TextStyle(
                            color: request.isPolling
                                ? Colors.green[900]
                                : Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (request.data != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.blue[100],
                              child: Text(
                                request.data!['name']
                                    .toString()[0]
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.data!['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    request.data!['email'] ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        _buildInfoRow('Phone', request.data!['phone']),
                        _buildInfoRow('Website', request.data!['website']),
                        _buildInfoRow(
                          'Company',
                          request.data!['company']?['name'],
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '更新时间: ${request.data!['fetchTime']?.toString().substring(11, 19) ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: request.refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('立即刷新'),
                    ),
                    OutlinedButton.icon(
                      onPressed: request.isPolling
                          ? request.pausePolling
                          : request.resumePolling,
                      icon: Icon(
                        request.isPolling ? Icons.stop : Icons.play_arrow,
                        size: 18,
                      ),
                      label: Text(request.isPolling ? '停止轮询' : '恢复轮询'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: request.isPolling
                            ? Colors.orange
                            : Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
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
    );
  }
}
