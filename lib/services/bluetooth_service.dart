import 'dart:async';

import 'package:flutter/foundation.dart';

/// 蓝牙链路的整体状态。`name` 与多语言 key `connect.state.*` 一一对应。
enum BluetoothStage {
  /// 设备不支持蓝牙 / 插件不可用。
  unavailable,

  /// 蓝牙已关闭。
  off,

  /// 缺少权限。
  unauthorized,

  /// 正常但未连接。
  ready,

  /// 正在连接。
  connecting,

  /// 已连接，正在收数据。
  connected,
}

/// 一个已配对（或模拟）的蓝牙设备。
@immutable
class BluetoothPeer {
  const BluetoothPeer({
    required this.address,
    this.name,
    this.bonded = true,
    this.connected = false,
  });

  /// MAC 地址（模拟设备用 `DEMO:` 前缀）。
  final String address;

  /// 友好名称。
  final String? name;

  /// 是否已配对。
  final bool bonded;

  /// 系统层面是否已连接。
  final bool connected;

  /// 界面显示名：有名用名，无名用地址。
  String get label => (name == null || name!.isEmpty) ? address : name!;

  @override
  bool operator ==(Object other) =>
      other is BluetoothPeer && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'BluetoothPeer($label)';
}

/// 蓝牙服务抽象层。
///
/// 只暴露「状态 + 设备列表 + 字节流」，把 NMEA 解析完全交给数据层，
/// 这样：
///   * 真正的心跳/重连/保活策略可以放在你的平台侧架构里；
///   * CI 里没有蓝牙硬件时可以用 [MockBluetoothService] 跑通整条链路；
///   * 未来要换成 BLE 或 USB 串口，只需要再实现一个子类。
///
/// **线程/Isolate 说明**：经典蓝牙插件是 MethodChannel/EventChannel 实现，
/// 必须跑在主 Isolate（有 FlutterEngine 的那个）。所以本类只在主 Isolate 使用；
/// 如果你要把解析结果送去后台 Isolate，请监听 [AprsBus.stations]，
/// 用 `IsolateNameServer`/`SendPort` 或你现有的通信通道转发。
abstract class BluetoothService extends ChangeNotifier {
  final StreamController<List<int>> _bytesController =
      StreamController<List<int>>.broadcast();

  bool _disposed = false;

  /// 收到的原始字节流（UI/数据层订阅它，自己做分帧）。
  Stream<List<int>> get bytes => _bytesController.stream;

  /// 当前状态。
  BluetoothStage get stage;

  /// 已配对设备列表。
  List<BluetoothPeer> get peers;

  /// 当前连接的设备。
  BluetoothPeer? get activePeer;

  /// 最近一次错误信息（原始字符串，界面直接展示）。
  String? get lastError;

  bool get isConnected => stage == BluetoothStage.connected;

  /// 刷新已配对设备列表。
  Future<void> refreshPeers();

  /// 请求打开蓝牙，返回是否已开启。
  Future<bool> requestEnable();

  /// 申请运行所需的权限（Android 12+ 的 BLUETOOTH_SCAN / BLUETOOTH_CONNECT）。
  Future<bool> ensurePermissions();

  /// 连接设备：连接成功后数据会从 [bytes] 流出。
  Future<void> connect(BluetoothPeer peer);

  /// 断开连接。
  Future<void> disconnect();

  /// 向设备写数据（本 App 的接收场景用得少，留给「主动请求信标」等扩展）。
  Future<void> send(String ascii);

  @protected
  void emitBytes(List<int> data) {
    if (!_bytesController.isClosed) _bytesController.add(data);
  }

  @protected
  void emitError(Object error) {
    if (!_bytesController.isClosed) _bytesController.addError(error);
  }

  @protected
  bool get isDisposed => _disposed;

  /// 安全地通知监听者（避免 dispose 之后调用抛异常）。
  @protected
  void notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _bytesController.close();
    super.dispose();
  }
}
