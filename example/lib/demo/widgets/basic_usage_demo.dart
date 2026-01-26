import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

class BasicUsageDemo extends HookWidget {
  final bool autoRequest;
  const BasicUsageDemo({super.key, this.autoRequest = true});

  Future<Map<String, dynamic>> _fetchUser(int userId) async {
    final dio = Dio();
    final res = await dio.get(
      'https://jsonplaceholder.typicode.com/users/$userId',
    );
    return res.data as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = useState<bool>(false);

    final request = useRequest<Map<String, dynamic>, int>(
      _fetchUser,
      options: UseRequestOptions(
        manual: !autoRequest,
        defaultParams: autoRequest ? 1 : null,
        onSuccess: (data, params) {
          debugPrint('成功获取用户: ${data['name']}');
          cancelled.value = false;
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '说明：',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          '• manual: false - 组件加载时自动执行请求\n'
          '• defaultParams - 设置默认参数\n'
          '• onSuccess - 请求成功回调',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 24),
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
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip('Loading', request.loading, Colors.orange),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      'Has Data',
                      request.data != null,
                      Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _buildStatusChip(
                      'Has Error',
                      request.error != null,
                      Colors.red,
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              if (request.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (cancelled.value)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cancel, color: Colors.orange),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('已取消本次请求')),
                    ],
                  ),
                )
              else if (request.error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '错误: ${request.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                )
              else if (request.data != null)
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
                          const Icon(Icons.person, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              request.data!['name'] ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildInfoRow('Email', request.data!['email']),
                      _buildInfoRow('Phone', request.data!['phone']),
                      _buildInfoRow('Website', request.data!['website']),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => request.run(1),
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text('加载用户1'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => request.run(2),
                    icon: const Icon(Icons.person, size: 18),
                    label: const Text('加载用户2'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      cancelled.value = false;
                      request.refresh();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('刷新'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      request.cancel();
                      cancelled.value = true;
                    },
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('取消'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, bool isActive, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.1) : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color : Colors.grey[400]!,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? color : Colors.grey[400],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? color : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
