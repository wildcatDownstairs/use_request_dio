import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'focus_manager_visibility_stub.dart'
    if (dart.library.html) 'focus_manager_visibility_web.dart';

/// 聚焦事件管理器（应用生命周期）
/// 使用 WidgetsBindingObserver 监听应用进入前台与后台
class AppFocusManager with WidgetsBindingObserver {
  final VoidCallback onFocus;
  final VoidCallback? onBlur;
  bool _isRegistered = false;
  bool _wasInBackground = false;
  VisibilityChangeDisposer? _visibilityDisposer;

  AppFocusManager({required this.onFocus, this.onBlur});

  /// 开始监听应用生命周期变化
  void start() {
    if (_isRegistered) return;

    WidgetsBinding.instance.addObserver(this);
    _isRegistered = true;

    // Web 端额外监听 Tab 可见性变化，保证 pollingWhenHidden 生效
    if (kIsWeb) {
      _visibilityDisposer = registerVisibilityChange(_handleVisible);
    }
  }

  /// 停止监听应用生命周期变化
  void stop() {
    if (!_isRegistered) return;

    _visibilityDisposer?.call();
    _visibilityDisposer = null;

    WidgetsBinding.instance.removeObserver(this);
    _isRegistered = false;
  }

  void _handleVisible(bool visible) {
    if (visible) {
      if (_wasInBackground) {
        _wasInBackground = false;
        onFocus();
      }
    } else {
      _wasInBackground = true;
      onBlur?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleVisible(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _handleVisible(false);
        break;
    }
  }

  /// 释放资源
  void dispose() {
    stop();
  }

  /// 管理器是否处于激活状态
  bool get isActive => _isRegistered;
}

/// 创建聚焦管理器的函数式辅助
AppFocusManager createFocusManager({
  required VoidCallback onFocus,
  VoidCallback? onBlur,
}) {
  return AppFocusManager(onFocus: onFocus, onBlur: onBlur);
}
