import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'bluetooth_service.dart';

/// Android 平台实现：经典蓝牙 SPP（RFCOMM）。
///
/// 生命周期：
/// ```
///   refreshPeers() → connect(peer) → bytes 流出 → disconnect()
/// ```
/// 插件用的是 EventChannel，**必须在有 FlutterEngine 的主 Isolate 里使用**。
///
/// 关于保活：本类不做重连/心跳，只把每次状态变化和错误原样暴露出来
/// （[stage] / [lastError]），你可以把「断线自动重连」接到自己的保活服务里：
/// ```dart
/// service.bytes.listen(null, onDone: () => _scheduleReconnect(peer));
/// ```
class PlatformBluetoothService extends BluetoothService {
  PlatformBluetoothService({FlutterBluetoothSerial? bluetooth})
      : _bluetooth = bluetooth ?? FlutterBluetoothSerial.instance;

  final FlutterBluetoothSerial _bluetooth;

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<BluetoothState>? _stateSubscription;

  BluetoothStage _stage = BluetoothStage.ready;
  List<BluetoothPeer> _peers = const <BluetoothPeer>[];
  BluetoothPeer? _active;
  String? _lastError;

  @override
  BluetoothStage get stage => _stage;

  @override
  List<BluetoothPeer> get peers => _peers;

  @override
  BluetoothPeer? get activePeer => _active;

  @override
  String? get lastError => _lastError;

  /// 订阅系统蓝牙开关变化（在 App 启动时调用一次即可）。
  void watchAdapterState() {
    _stateSubscription ??= _bluetooth.onStateChanged().listen((BluetoothState state) {
      if (!state.isEnabled && _stage != BluetoothStage.connected) {
        _stage = BluetoothStage.off;
      } else if (state.isEnabled && _stage == BluetoothStage.off) {
        _stage = BluetoothStage.ready;
      }
      notifySafely();
    });
  }

  @override
  Future<void> refreshPeers() async {
    try {
      final List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      _peers = devices
          .map(
            (BluetoothDevice device) => BluetoothPeer(
              address: device.address,
              name: device.name,
              bonded: device.isBonded,
              connected: device.isConnected,
            ),
          )
          .toList()
        ..sort(
          (BluetoothPeer a, BluetoothPeer b) =>
              a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
      _lastError = null;
      await _syncStage(adapterOnly: true);
    } catch (error) {
      _handleError(error, '刷新已配对设备失败');
    }
    notifySafely();
  }

  @override
  Future<bool> requestEnable() async {
    try {
      if (await _bluetooth.isEnabled ?? false) return true;
      final bool? granted = await _bluetooth.requestEnable();
      await _syncStage();
      return granted ?? false;
    } catch (error) {
      _handleError(error, '请求打开蓝牙失败');
      notifySafely();
      return false;
    }
  }

  @override
  Future<bool> ensurePermissions() async {
    try {
      final Map<Permission, PermissionStatus> statuses = await <Permission>[
        // Android 12+：附近的设备
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        // Android 11 及以下：扫描/连接需要定位权限（插件侧同样声明）
        Permission.locationWhenInUse,
      ].request();

      final bool granted = (statuses[Permission.bluetoothScan]?.isGranted ?? false) ||
          (statuses[Permission.bluetoothConnect]?.isGranted ?? false) ||
          (statuses[Permission.locationWhenInUse]?.isGranted ?? false);

      if (!granted) {
        _stage = BluetoothStage.unauthorized;
        _lastError = 'BLUETOOTH_SCAN / BLUETOOTH_CONNECT / LOCATION denied';
      }
      notifySafely();
      return granted;
    } catch (error) {
      _handleError(error, '申请蓝牙权限失败');
      _stage = BluetoothStage.unauthorized;
      notifySafely();
      return false;
    }
  }

  @override
  Future<void> connect(BluetoothPeer peer) async {
    await disconnect();

    _stage = BluetoothStage.connecting;
    _lastError = null;
    notifySafely();

    try {
      final BluetoothConnection connection =
          await BluetoothConnection.toAddress(peer.address);
      _connection = connection;
      _active = peer;

      _inputSubscription = connection.input.listen(
        (Uint8List data) => emitBytes(data),
        onDone: () => _handleClosed('远端已关闭连接'),
        onError: (Object error) {
          _handleError(error, '蓝牙读取错误');
          _handleClosed('蓝牙读取错误');
        },
        cancelOnError: true,
      );

      _stage = BluetoothStage.connected;
    } catch (error) {
      _handleError(error, '连接 ${peer.label} 失败');
      _stage = BluetoothStage.ready;
      _active = null;
    }
    notifySafely();
  }

  @override
  Future<void> disconnect() async {
    final StreamSubscription<Uint8List>? subscription = _inputSubscription;
    final BluetoothConnection? connection = _connection;
    _inputSubscription = null;
    _connection = null;
    _active = null;

    try {
      await subscription?.cancel();
    } catch (_) {
      // 忽略取消订阅时的异常。
    }

    try {
      // 先 finish() 让待发送的数据发完，再关闭；失败时退化为直接 close()。
      await connection?.finish();
    } catch (_) {
      try {
        await connection?.close();
      } catch (_) {
        // 已经断开，忽略。
      }
    }

    if (_stage == BluetoothStage.connected || _stage == BluetoothStage.connecting) {
      _stage = BluetoothStage.ready;
    }
    notifySafely();
  }

  @override
  Future<void> send(String ascii) async {
    final BluetoothConnection? connection = _connection;
    if (connection == null || !connection.isConnected) {
      throw StateError('Bluetooth not connected');
    }
    connection.output.add(Uint8List.fromList(utf8.encode(ascii)));
    await connection.output.allSent;
  }

  Future<void> _syncStage({bool adapterOnly = false}) async {
    try {
      final BluetoothState state = await _bluetooth.state;
      if (!state.isEnabled) {
        _stage = BluetoothStage.off;
        return;
      }
      if (adapterOnly && _stage != BluetoothStage.connected) {
        _stage = BluetoothStage.ready;
        return;
      }
      if (_stage != BluetoothStage.connecting) {
        _stage = _connection?.isConnected ?? false
            ? BluetoothStage.connected
            : BluetoothStage.ready;
      }
    } on PlatformException catch (error) {
      _handleError(error, '读取蓝牙状态失败');
      _stage = BluetoothStage.unavailable;
    } on MissingPluginException catch (error) {
      // 在没有实现的平台（Windows/Linux 桌面）上跑 UI 时会走到这里。
      _handleError(error, '当前平台不支持经典蓝牙插件');
      _stage = BluetoothStage.unavailable;
    }
  }

  void _handleClosed(String reason) {
    _connection = null;
    _active = null;
    _inputSubscription = null;
    _lastError = reason;
    _stage = BluetoothStage.ready;
    notifySafely();
  }

  void _handleError(Object error, String what) {
    _lastError = '$what: $error';
    debugPrint('[PKWDWPL][BT] $_lastError');
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _inputSubscription?.cancel();
    _connection?.close();
    _stateSubscription = null;
    _inputSubscription = null;
    _connection = null;
    super.dispose();
  }
}
