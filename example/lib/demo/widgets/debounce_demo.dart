import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

class DebounceDemo extends HookWidget {
  const DebounceDemo({super.key});

  Future<List<dynamic>> _searchPosts(String keyword) async {
    if (keyword.isEmpty) return [];
    final dio = Dio();
    final res = await dio.get('https://jsonplaceholder.typicode.com/posts');
    final posts = res.data as List;
    return posts.where((post) {
      final title = (post['title'] ?? '').toString().toLowerCase();
      return title.contains(keyword.toLowerCase());
    }).take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    final requestCount = useState(0);

    final request = useRequest<List<dynamic>, String>(
      _searchPosts,
      options: UseRequestOptions(
        manual: true,
        debounceInterval: const Duration(milliseconds: 500),
        onBefore: (_) {
          requestCount.value++;
        },
      ),
    );

    useEffect(() {
      void listener() {
        request.run(controller.text);
      }
      controller.addListener(listener);
      return () => controller.removeListener(listener);
    }, [controller]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '说明：',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          '• debounceInterval: 500ms - 延迟500ms执行\n'
          '• 连续输入时，只有停止输入500ms后才会执行请求\n'
          '• 避免频繁调用接口，节省资源',
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
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '已发送 ${requestCount.value} 次请求',
                        style: TextStyle(
                          color: Colors.amber[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '搜索文章',
                  hintText: '输入关键字（自动防抖）',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: request.loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => controller.clear(),
                            )
                          : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (request.data != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '找到 ${request.data!.length} 篇文章:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                if (request.data!.isEmpty && controller.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.article_outlined, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          '未找到匹配的文章',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: request.data!.length,
                      itemBuilder: (context, index) {
                        final post = request.data![index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post['title'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID: ${post['id']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
