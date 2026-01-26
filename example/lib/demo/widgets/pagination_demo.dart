import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:use_request/use_request.dart';

class PaginationDemo extends HookWidget {
  final bool enableAutoLoad;
  const PaginationDemo({super.key, this.enableAutoLoad = true});

  Future<List<Map<String, dynamic>>> _fetchPosts(
    Map<String, int> params,
  ) async {
    final page = params['page'] ?? 1;
    final pageSize = params['pageSize'] ?? 10;

    final dio = Dio();
    final res = await dio.get(
      'https://jsonplaceholder.typicode.com/posts',
      queryParameters: {'_page': page, '_limit': pageSize},
    );

    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    const pageSize = 10;

    final request = useRequest<List<Map<String, dynamic>>, Map<String, int>>(
      _fetchPosts,
      options: UseRequestOptions(
        manual: !enableAutoLoad,
        defaultParams: enableAutoLoad
            ? const {'page': 1, 'pageSize': pageSize}
            : null,
        loadMoreParams: (lastParams, data) {
          final nextPage = (lastParams['page'] ?? 1) + 1;
          return {'page': nextPage, 'pageSize': pageSize};
        },
        dataMerger: (prev, next) => [...(prev ?? []), ...next],
        hasMore: (data) => (data?.length ?? 0) >= pageSize,
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
          '• loadMoreParams - 生成下一页参数\n'
          '• dataMerger - 合并新旧数据\n'
          '• hasMore - 判断是否还有更多数据\n'
          '• loadingMore - 加载更多的loading状态',
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
                child: Row(
                  children: [
                    Icon(Icons.list_alt, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '已加载 ${request.data?.length ?? 0} 条数据',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (request.hasMore == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '还有更多',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '已全部加载',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (request.loading && request.data == null) ...[
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('加载中...'),
                    ],
                  ),
                ),
              ] else if (request.data != null) ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: request.data!.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final post = request.data![index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          radius: 16,
                          child: Text(
                            '${post['id']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          post['title'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          post['body'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (request.loadingMore)
                  Container(
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '加载更多中...',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: request.hasMore == true
                          ? request.loadMore
                          : null,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(request.hasMore == true ? '加载更多' : '已全部加载'),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: request.refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重置列表'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
