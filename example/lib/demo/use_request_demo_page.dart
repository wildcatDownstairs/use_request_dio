import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/basic_usage_demo.dart';
import 'widgets/manual_request_demo.dart';
import 'widgets/debounce_demo.dart';
import 'widgets/polling_demo.dart';
import 'widgets/retry_demo.dart';
import 'widgets/cache_demo.dart';
import 'widgets/pagination_demo.dart';
import 'widgets/http_methods_demo.dart';

/// useRequest 功能演示主页面
class UseRequestDemoPage extends ConsumerStatefulWidget {
  final bool enableAutoNetwork;
  const UseRequestDemoPage({super.key, this.enableAutoNetwork = true});

  @override
  ConsumerState<UseRequestDemoPage> createState() => _UseRequestDemoPageState();
}

class _UseRequestDemoPageState extends ConsumerState<UseRequestDemoPage> {
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;
  final List<String> _logs = [];

  late final List<DemoSection> _sections = [
    DemoSection(
      title: '基础用法',
      icon: Icons.play_circle_outline,
      description: '自动请求、回调处理、状态管理',
      widget: BasicUsageDemo(autoRequest: widget.enableAutoNetwork),
      key: GlobalKey(),
    ),
    DemoSection(
      title: '手动请求',
      icon: Icons.touch_app,
      description: '手动触发请求、参数传递',
      widget: const ManualRequestDemo(),
      key: GlobalKey(),
    ),
    DemoSection(
      title: '防抖搜索',
      icon: Icons.search,
      description: '延迟执行请求，避免频繁调用',
      widget: const DebounceDemo(),
      key: GlobalKey(),
    ),
    DemoSection(
      title: '轮询刷新',
      icon: Icons.refresh,
      description: '定时自动刷新数据',
      widget: PollingDemo(enablePolling: widget.enableAutoNetwork),
      key: GlobalKey(),
    ),
    DemoSection(
      title: '错误重试',
      icon: Icons.replay,
      description: '请求失败自动重试',
      widget: const RetryDemo(),
      key: GlobalKey(),
    ),
    DemoSection(
      title: '缓存策略',
      icon: Icons.storage,
      description: 'SWR缓存、请求去重',
      widget: const CacheDemo(),
      key: GlobalKey(),
    ),
    DemoSection(
      title: '分页加载',
      icon: Icons.view_list,
      description: '加载更多、数据合并',
      widget: PaginationDemo(enableAutoLoad: widget.enableAutoNetwork),
      key: GlobalKey(),
    ),
    DemoSection(
      title: 'HTTP方法',
      icon: Icons.http,
      description: 'GET/POST/PUT/DELETE/PATCH',
      widget: const HttpMethodsDemo(),
      key: GlobalKey(),
    ),
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(int index) {
    setState(() {
      _selectedIndex = index;
    });
    final key = _sections[index].key;
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
      _logs.add('已跳转到: ${_sections[index].title}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'useRequest',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '功能演示',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      drawer: isMobile ? _buildDrawer() : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(child: _buildNavigationList());
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey[200]!)),
      ),
      child: _buildNavigationList(),
    );
  }

  Widget _buildNavigationList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '功能列表',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ..._sections.asMap().entries.map((entry) {
          final index = entry.key;
          final section = entry.value;
          final isSelected = _selectedIndex == index;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue[50] : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              selected: isSelected,
              selectedColor: Colors.blue[700],
              leading: Icon(
                section.icon,
                size: 20,
                color: isSelected ? Colors.blue[700] : Colors.grey[600],
              ),
              title: Text(
                section.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              onTap: () => _scrollToSection(index),
            ),
          );
        }),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '操作日志',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _logs
                .take(5)
                .map((e) => Text('• $e', style: const TextStyle(fontSize: 12)))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      children: _sections.asMap().entries.map((entry) {
        final index = entry.key;
        final section = entry.value;
        return Padding(
          key: section.key,
          padding: const EdgeInsets.only(bottom: 32),
          child: _DemoSectionCard(section: section, index: index),
        );
      }).toList(),
    );
  }
}

class DemoSection {
  final String title;
  final IconData icon;
  final String description;
  final Widget widget;
  final GlobalKey key;

  const DemoSection({
    required this.title,
    required this.icon,
    required this.description,
    required this.widget,
    required this.key,
  });
}

class _DemoSectionCard extends StatelessWidget {
  final DemoSection section;
  final int index;

  const _DemoSectionCard({required this.section, required this.index});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(section.icon, color: Colors.blue[700], size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        section.description,
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(padding: const EdgeInsets.all(24), child: section.widget),
        ],
      ),
    );
  }
}
