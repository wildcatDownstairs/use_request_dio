// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

typedef VisibilityChangeCallback = void Function(bool visible);
typedef VisibilityChangeDisposer = void Function();

/// Web implementation using document.visibilitychange.
VisibilityChangeDisposer registerVisibilityChange(
  VisibilityChangeCallback callback,
) {
  void handler(html.Event _) {
    callback(html.document.visibilityState == 'visible');
  }

  html.document.addEventListener('visibilitychange', handler);
  // Emit current state once.
  callback(html.document.visibilityState == 'visible');

  return () {
    html.document.removeEventListener('visibilitychange', handler);
  };
}
