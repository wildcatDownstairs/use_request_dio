/// 全局请求观察者接口
///
/// 用于日志记录、调试、监控等场景。通过 [UseRequestObserver.instance] 设置全局观察者。
///
/// ## 使用方式
///
/// ```dart
/// // 自定义观察者
/// class MyObserver extends UseRequestObserver {
///   @override
///   void onRequest(String key, Object? params) {
///     print('[REQ] key=$key params=$params');
///   }
///
///   @override
///   void onSuccess(String key, Object? data, Object? params) {
///     print('[OK] key=$key');
///   }
///
///   @override
///   void onError(String key, Object error, Object? params) {
///     print('[ERR] key=$key error=$error');
///   }
///
///   @override
///   void onFinally(String key, Object? params) {
///     print('[DONE] key=$key');
///   }
/// }
///
/// // 在 main() 中设置
/// void main() {
///   UseRequestObserver.instance = MyObserver();
///   runApp(MyApp());
/// }
/// ```
class UseRequestObserver {
  /// 全局单例观察者。设为 null 可禁用。
  static UseRequestObserver? instance;

  /// 请求开始时触发
  void onRequest(String key, Object? params) {}

  /// 请求成功时触发
  void onSuccess(String key, Object? data, Object? params) {}

  /// 请求失败时触发
  void onError(String key, Object error, Object? params) {}

  /// 请求完成时触发（成功或失败）
  void onFinally(String key, Object? params) {}

  /// 缓存命中时触发
  void onCacheHit(String cacheKey, bool isStale) {}

  /// mutate 时触发
  void onMutate(String key, Object? oldData, Object? newData) {}

  /// 请求被取消时触发
  void onCancel(String key) {}
}
