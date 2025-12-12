import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

/// HTTP 方法语义层演示
///
/// 展示 DioHttpAdapter 的 GET/POST/PUT/DELETE 等语义化方法
class HttpMethodsDemo extends HookWidget {
  const HttpMethodsDemo({super.key});

  @override
  Widget build(BuildContext context) {
    // 创建 DioHttpAdapter 实例
    final http = useMemoized(() => DioHttpAdapter(
          dio: Dio(BaseOptions(
            baseUrl: 'https://jsonplaceholder.typicode.com',
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          )),
        ));

    // 操作日志
    final logs = useState<List<String>>([]);

    // 当前选中的用户
    final selectedUser = useState<Map<String, dynamic>?>(null);

    // 加载状态
    final isLoading = useState(false);

    // 添加日志
    void addLog(String message) {
      final time = DateTime.now().toString().substring(11, 19);
      logs.value = ['[$time] $message', ...logs.value.take(9)];
    }

    int safeUserId(dynamic rawId) {
      final id = rawId is int ? rawId : int.tryParse(rawId.toString()) ?? 1;
      if (id < 1 || id > 10) {
        addLog('JSONPlaceholder 仅支持 /users/1-10 的 PUT/PATCH/DELETE；已回退到 /users/1');
        return 1;
      }
      return id;
    }

    // GET 请求 - 获取用户列表
    Future<void> fetchUsers() async {
      isLoading.value = true;
      addLog('GET /users - 开始请求...');
      try {
        final response = await http.get<List<dynamic>>('/users');
        final users = response.data ?? [];
        addLog('GET /users - 成功，返回 ${users.length} 个用户');
        if (users.isNotEmpty) {
          selectedUser.value = users[0] as Map<String, dynamic>;
        }
      } catch (e) {
        addLog('GET /users - 失败: $e');
      } finally {
        isLoading.value = false;
      }
    }

    // POST 请求 - 创建新用户
    Future<void> createUser() async {
      isLoading.value = true;
      addLog('POST /users - 创建新用户...');
      try {
        final response = await http.post<Map<String, dynamic>>(
          '/users',
          data: {
            'name': 'New User ${DateTime.now().millisecond}',
            'email': 'newuser@example.com',
            'phone': '123-456-7890',
          },
        );
        final newUser = response.data!;
        addLog('POST /users - 成功，新用户ID: ${newUser['id']}');
        if (newUser['id'] is int && (newUser['id'] as int) > 10) {
          addLog('注意：该 ID 在 JSONPlaceholder 上不可被 PUT/PATCH/DELETE 更新');
        }
        selectedUser.value = newUser;
      } catch (e) {
        addLog('POST /users - 失败: $e');
      } finally {
        isLoading.value = false;
      }
    }

    // PUT 请求 - 更新用户
    Future<void> updateUser() async {
      if (selectedUser.value == null) {
        addLog('PUT - 请先选择一个用户');
        return;
      }
      isLoading.value = true;
      final userId = safeUserId(selectedUser.value!['id']);
      addLog('PUT /users/$userId - 更新用户...');
      try {
        final response = await http.put<Map<String, dynamic>>(
          '/users/$userId',
          data: {
            'id': userId,
            'name': '${selectedUser.value!['name']} (已更新)',
            'email': selectedUser.value!['email'] ?? '',
            'phone': selectedUser.value!['phone'] ?? '',
          },
        );
        addLog('PUT /users/$userId - 成功');
        selectedUser.value = response.data!;
      } catch (e) {
        addLog('PUT /users/$userId - 失败: $e');
      } finally {
        isLoading.value = false;
      }
    }

    // PATCH 请求 - 部分更新
    Future<void> patchUser() async {
      if (selectedUser.value == null) {
        addLog('PATCH - 请先选择一个用户');
        return;
      }
      isLoading.value = true;
      final userId = safeUserId(selectedUser.value!['id']);
      addLog('PATCH /users/$userId - 部分更新...');
      try {
        final response = await http.patch<Map<String, dynamic>>(
          '/users/$userId',
          data: {'email': 'patched_${DateTime.now().millisecond}@example.com'},
        );
        addLog('PATCH /users/$userId - 成功');
        selectedUser.value = response.data!;
      } catch (e) {
        addLog('PATCH /users/$userId - 失败: $e');
      } finally {
        isLoading.value = false;
      }
    }

    // DELETE 请求 - 删除用户
    Future<void> deleteUser() async {
      if (selectedUser.value == null) {
        addLog('DELETE - 请先选择一个用户');
        return;
      }
      isLoading.value = true;
      final userId = safeUserId(selectedUser.value!['id']);
      addLog('DELETE /users/$userId - 删除用户...');
      try {
        await http.delete('/users/$userId');
        addLog('DELETE /users/$userId - 成功');
        selectedUser.value = null;
      } catch (e) {
        addLog('DELETE /users/$userId - 失败: $e');
      } finally {
        isLoading.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '说明：',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          '• DioHttpAdapter 提供语义化 HTTP 方法\n'
          '• 支持 GET/POST/PUT/DELETE/PATCH\n'
          '• 可配置超时、请求头、取消令牌等',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 24),

        // 操作按钮区
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
              // 加载指示器
              if (isLoading.value)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),

              // HTTP 方法按钮
              const Text(
                'HTTP 方法操作：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HttpMethodButton(
                    method: 'GET',
                    color: Colors.blue,
                    onPressed: isLoading.value ? null : fetchUsers,
                    tooltip: '获取用户列表',
                  ),
                  _HttpMethodButton(
                    method: 'POST',
                    color: Colors.green,
                    onPressed: isLoading.value ? null : createUser,
                    tooltip: '创建新用户',
                  ),
                  _HttpMethodButton(
                    method: 'PUT',
                    color: Colors.orange,
                    onPressed: isLoading.value ? null : updateUser,
                    tooltip: '完整更新用户',
                  ),
                  _HttpMethodButton(
                    method: 'PATCH',
                    color: Colors.purple,
                    onPressed: isLoading.value ? null : patchUser,
                    tooltip: '部分更新用户',
                  ),
                  _HttpMethodButton(
                    method: 'DELETE',
                    color: Colors.red,
                    onPressed: isLoading.value ? null : deleteUser,
                    tooltip: '删除用户',
                  ),
                ],
              ),

              // 当前用户信息
              if (selectedUser.value != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  '当前用户：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _UserInfoRow(
                        label: 'ID',
                        value: '${selectedUser.value!['id']}',
                      ),
                      _UserInfoRow(
                        label: '姓名',
                        value: selectedUser.value!['name'] ?? '-',
                      ),
                      _UserInfoRow(
                        label: '邮箱',
                        value: selectedUser.value!['email'] ?? '-',
                      ),
                      if (selectedUser.value!['phone'] != null)
                        _UserInfoRow(
                          label: '电话',
                          value: selectedUser.value!['phone'],
                        ),
                    ],
                  ),
                ),
              ],

              // 操作日志
              if (logs.value.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '操作日志：',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => logs.value = [],
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('清空'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: logs.value
                        .map((log) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: log.contains('成功')
                                      ? Colors.greenAccent
                                      : log.contains('失败')
                                          ? Colors.redAccent
                                          : Colors.white70,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),

        // 代码示例
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '代码示例：',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '''final http = DioHttpAdapter(
  dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
);

// GET 请求
final users = await http.get<List>('/users');

// POST 请求
final user = await http.post<Map>('/users', data: {...});

// PUT 请求
await http.put('/users/1', data: {...});

// DELETE 请求
await http.delete('/users/1');''',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.greenAccent,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// HTTP 方法按钮组件
class _HttpMethodButton extends StatelessWidget {
  final String method;
  final Color color;
  final VoidCallback? onPressed;
  final String tooltip;

  const _HttpMethodButton({
    required this.method,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: Text(
          method,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// 用户信息行组件
class _UserInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _UserInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
