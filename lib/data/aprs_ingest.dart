import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_settings.dart';
import '../services/bluetooth_service.dart';
import '../services/bluetooth_service_factory.dart';
import '../services/bluetooth_service_io.dart';
import '../services/bluetooth_service_mock.dart';
import 'nmea_line_splitter.dart';
import 'station_store.dart';

/// 数据入口：把「蓝牙字节流」变成「入库的台站记录」。
///
/// ```text
///  BluetoothService.bytes ──► NmeaLineSplitter ──► StationStore.addRawLine
///        (原始字节)               (分帧成整句)          (XOR 校验+解析+入库)
/// ```
///
/// UI 只需要 `context.watch<AprsIngest>()`：
///   * `ingest.stage` / `ingest.activePeer` / `ingest.peers` —— 连接状态；
///   * `ingest.setDemoMode(true)` —— 无硬件演示；
///   * 台站数据请从 `StationStore` 读（避免解析逻辑和 UI 耦合）。
///
/// 想接入你自己的保活架构？两条路：
///   1. 保住 `AprsIngest` 存活（它就是主 Isolate 里的蓝牙持有者）；
///   2. 或者完全不用它：在后台服务里直接 `StationStore.addRawLine(line)`，
///      UI 通过 `AprsBus.stations` 流接收。
class AprsIngest extends ChangeNotifier {
  AprsIngest({
    required AppSettings settings,
    required StationStore store,
    BluetoothService? service,
  })  : _settings = settings,
        _store = store {
    _service = service ?? createBluetoothService(forceMock: settings.demoMode);
    _attach(_service);
  }

  final AppSettings _settings;
  final StationStore _store;
  final NmeaLineSplitter _splitter = NmeaLineSplitter();

  late BluetoothService _service;
  StreamSubscription<List<int>>? _subscription;

  /// 当前使用的蓝牙服务（平台实现或模拟实现）。
  BluetoothService get service => _service;

  /// 是否处于演示模式。
  bool get isDemo => _service is MockBluetoothService;

  BluetoothStage get stage => _service.stage;

  List<BluetoothPeer> get peers => _service.peers;

  BluetoothPeer? get activePeer => _service.activePeer;

  String? get lastError => _service.lastError;

  bool get isConnected => _service.isConnected;

  /// 未成句的残留数据（调试用）。
  String get pendingBuffer => _splitter.pending;

  // ---------------------------------------------------------------------------
  // 蓝牙操作：直接转发给当前服务，UI 只依赖 AprsIngest。
  // ---------------------------------------------------------------------------

  Future<void> refreshPeers() => _service.refreshPeers();

  Future<bool> requestEnable() => _service.requestEnable();

  Future<bool> ensurePermissions() => _service.ensurePermissions();

  Future<void> connect(BluetoothPeer peer) => _service.connect(peer);

  Future<void> disconnect() => _service.disconnect();

  Future<void> send(String ascii) => _service.send(ascii);

  /// App 启动时调用：如果是真实平台实现，订阅蓝牙开关状态。
  Future<void> bootstrap() async {
    final BluetoothService current = _service;
    if (current is PlatformBluetoothService) {
      current.watchAdapterState();
    }
    if (!isDemo) {
      await ensurePermissions();
      await refreshPeers();
    }
  }

  /// 切换演示模式（会热替换底层服务）。
  Future<void> setDemoMode(bool value) async {
    await _settings.setDemoMode(value);
    syncWithSettings();
  }

  /// 设置变化后同步（目前只关心演示模式开关）。
  void syncWithSettings() {
    final bool wantDemo = _settings.demoMode;
    if (wantDemo == isDemo) {
      notifySafely();
      return;
    }

    final BluetoothService previous = _service;
    _detach(previous);
    _splitter.reset();

    _service = createBluetoothService(forceMock: wantDemo);
    _attach(_service);

    previous.dispose();
    notifySafely();
  }

  // ---------------------------------------------------------------------------
  // 内部：订阅 / 退订
  // ---------------------------------------------------------------------------

  void _attach(BluetoothService service) {
    _subscription = service.bytes.listen(
      _onBytes,
      onError: (Object error) =>
          debugPrint('[PKWDWPL] 蓝牙数据流错误: $error'),
    );
    service.addListener(_onServiceChanged);
  }

  void _detach(BluetoothService service) {
    _subscription?.cancel();
    _subscription = null;
    service.removeListener(_onServiceChanged);
  }

  void _onServiceChanged() => notifySafely();

  void _onBytes(List<int> data) {
    final List<String> lines = _splitter.addBytes(data);
    if (lines.isEmpty) return;
    for (final String line in lines) {
      _store.addRawLine(line, strictChecksum: _settings.strictChecksum);
    }
  }

  /// 手动喂一条语句（自动化测试 / 「粘贴语句」调试用）。
  void feedLine(String line) =>
      _store.addRawLine(line, strictChecksum: _settings.strictChecksum);

  bool _disposed = false;

  void notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _detach(_service);
    _service.dispose();
    super.dispose();
  }
}
