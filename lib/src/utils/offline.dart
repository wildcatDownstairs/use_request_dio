/// 占位的离线检测接口，可由外部接入 Connectivity 等实现。
@Deprecated('请直接向 UseRequestOptions.reconnectStream 提供 Stream<bool>')
abstract class OfflineDetector {
  /// 是否离线
  bool get isOffline;

  /// 状态变化流
  Stream<bool> get onStatusChange; // true 表示在线
}
