import 'dart:js_interop';

import 'package:web/web.dart' as web;

typedef VisibilityChangeCallback = void Function(bool visible);
typedef VisibilityChangeDisposer = void Function();

/// Web implementation using document.visibilitychange.
///
/// 基于 package:web + dart:js_interop 实现，兼容 JS 与 WASM 编译目标
/// （旧的 dart:html 已弃用，且 dart.library.html 条件在 WASM 下为 false）。
VisibilityChangeDisposer registerVisibilityChange(
  VisibilityChangeCallback callback,
) {
  void handler(web.Event _) {
    callback(web.document.visibilityState == 'visible');
  }

  final jsHandler = handler.toJS;
  web.document.addEventListener('visibilitychange', jsHandler);
  // Emit current state once.
  callback(web.document.visibilityState == 'visible');

  return () {
    web.document.removeEventListener('visibilitychange', jsHandler);
  };
}
