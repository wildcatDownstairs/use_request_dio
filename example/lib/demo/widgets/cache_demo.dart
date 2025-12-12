import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

class CacheDemo extends HookWidget {
  const CacheDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedUserId = useState(1);
    final requestCount = useState(0);

    // 在 service 函数内部计数，只有真正发起网络请求时才会调用
    Future<Map<String, dynamic>> fetchUser(int userId) async {
      // 只有真正发起网络请求时才增加计数
      requestCount.value++;
      // 模拟网络延迟
      await Future.delayed(const Duration(milliseconds: 500));
      final dio = Dio();
      final res = await dio.get('https://jsonplaceholder.typicode.com/users/$userId');
      return {
        ...res.data as Map<String, dynamic>,
        'fetchTime': DateTime.now().toIso8601String(),
      };
    }

    final request = useRequest<Map<String, dynamic>, int>(
      fetchUser,
      options: UseRequestOptions(
        manual: true,
        cacheKey: (userId) => 'user-$userId',
        cacheTime: const Duration(minutes: 5),
        staleTime: const Duration(seconds: 10),
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
          '• cacheKey - 缓存键，相同的键会复用缓存\n'
          '• staleTime: 10s - 数据10秒内保持新鲜，直接使用缓存\n'
          '• cacheTime: 5m - 缓存最多保留5分钟\n'
          '• SWR策略：过期后先返回缓存，同时后台刷新',
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purple[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.purple[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '实际发送了 ${requestCount.value} 次网络请求',
                        style: TextStyle(
                          color: Colors.purple[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 2, 3, 4, 5].map((userId) {
                  final isSelected = selectedUserId.value == userId;
                  return ChoiceChip(
                    label: Text('用户$userId'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        selectedUserId.value = userId;
                        request.run(userId);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (request.loading) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('加载中...'),
                    ],
                  ),
                ),
              ],
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
                              request.data!['name'].toString()[0].toUpperCase(),
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
                                    fontSize: 16,
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
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '获取时间: ${request.data!['fetchTime']?.toString().substring(11, 19) ?? ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '提示: 10秒内重复点击同一用户会使用缓存（计数器不增加）',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontStyle: FontStyle.italic,
                        ),
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
                    onPressed: () => request.run(selectedUserId.value),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重新加载'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      clearAllCache();
                      requestCount.value = 0;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('缓存已清空')),
                      );
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空缓存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
