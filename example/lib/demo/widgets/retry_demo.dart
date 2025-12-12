import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

class RetryDemo extends HookWidget {
  const RetryDemo({super.key});

  Future<Map<String, dynamic>> _fetchWithError(bool shouldFail) async {
    final dio = Dio();
    if (shouldFail) {
      // 模拟请求失败
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
    final retryCount = useState(0);

    final request = useRequest<Map<String, dynamic>, bool>(
      _fetchWithError,
      options: UseRequestOptions(
        manual: true,
        retryCount: 3,
        retryInterval: const Duration(seconds: 1),
        onBefore: (_) {
          retryCount.value = 0;
        },
        onRetryAttempt: (attempt, error) {
          retryCount.value = attempt;
          debugPrint('重试第 ${retryCount.value} 次');
        },
        onError: (error, _) {
          debugPrint('最终失败，已重试 ${retryCount.value} 次');
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
          '• retryCount: 3 - 失败后最多重试3次\n'
          '• retryInterval: 1s - 每次重试间隔1秒\n'
          '• 适用于网络不稳定的场景',
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
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          '模拟设置',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('模拟请求失败'),
                      subtitle: Text(
                        shouldFail.value ? '请求将会失败并重试' : '请求将会成功',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: shouldFail.value,
                      onChanged: (value) {
                        shouldFail.value = value;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (request.loading) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '请求中...',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (retryCount.value > 0)
                              Text(
                                '正在重试: ${retryCount.value}/3',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (request.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              '请求失败',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '错误信息: ${request.error}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已重试 ${retryCount.value} 次',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (request.data != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700]),
                          const SizedBox(width: 12),
                          Text(
                            '请求成功',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: request.loading
                    ? null
                    : () => request.run(shouldFail.value),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('发起请求'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
