import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/aprs_station.dart';
import '../models/geo_math.dart';
import 'bluetooth_service.dart';

/// 模拟蓝牙服务：没有电台 / 电脑上跑 UI 时使用。
///
/// 它按 `$PKWDWPL` 格式**真实拼装**语句（校验和用 [NmeaChecksum] 真算），
/// 台站数据全部取自 BI7NOR 采集的真实报文，因此整条链路
/// （分帧 → 校验 → 解析 → 入库 → UI）都能被验证。
///
/// 每 [interval] 一拍，会依次注入：
///   * 每个台站一条语句（含「海拔/航向/距离为空」的 12 字段写法）；
///   * 每 9 拍故意发一条**校验和错误**的语句（验证严格模式丢弃 + 统计）；
///   * 每 13 拍发一条**丢了逗号**的 10 字段语句（验证容错解析 + 存疑标记）；
///   * 每 5 拍重复上报同一个台站（验证「同呼号覆盖并置顶」）。
class MockBluetoothService extends BluetoothService {
  MockBluetoothService({this.interval = const Duration(seconds: 3)});

  final Duration interval;

  static const BluetoothPeer demoPeer = BluetoothPeer(
    address: 'DEMO:00:11:22:33:44',
    name: '演示电台 DEMO-D710',
  );

  BluetoothStage _stage = BluetoothStage.ready;
  BluetoothPeer? _active;
  String? _lastError;
  Timer? _timer;
  int _tick = 0;

  @override
  BluetoothStage get stage => _stage;

  @override
  List<BluetoothPeer> get peers => const <BluetoothPeer>[demoPeer];

  @override
  BluetoothPeer? get activePeer => _active;

  @override
  String? get lastError => _lastError;

  @override
  Future<void> refreshPeers() async {
    // 模拟设备是常量，无需刷新。
  }

  @override
  Future<bool> requestEnable() async => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<void> connect(BluetoothPeer peer) async {
    await disconnect();
    _stage = BluetoothStage.connecting;
    notifySafely();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _active = demoPeer;
    _stage = BluetoothStage.connected;
    _timer = Timer.periodic(interval, (_) => _emitNext());
    notifySafely();
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _active = null;
    if (_stage != BluetoothStage.unavailable) {
      _stage = BluetoothStage.ready;
    }
    notifySafely();
  }

  @override
  Future<void> send(String ascii) async {
    debugPrint('[PKWDWPL][DEMO] 模拟发送: $ascii');
  }

  /// 直接注入一条语句（测试 / 「粘贴语句」调试用）。
  @visibleForTesting
  void emitTestSentence(String sentence) => emitBytes(utf8.encode(sentence));

  void _emitNext() {
    _tick++;
    final DateTime now = DateTime.now().toUtc();

    // ① 正常上报（时间错开 1 秒，更接近真实电台输出）
    for (int i = 0; i < _targets.length; i++) {
      // 移动台站每拍走一小步，方便观察列表置顶与地图上的位置变化。
      final _DemoTarget target = _targets[i].ticked();
      _targets[i] = target;
      final DateTime stamp = now.subtract(Duration(seconds: i));
      final bool corrupt = _tick % 9 == 0 && i == 0; // ② 坏校验和
      emitBytes(utf8.encode(target.buildSentence(stampUtc: stamp, corruptChecksum: corrupt)));
    }

    // ③ 丢了逗号的语句（10 字段，校验和按实际内容计算 → 能通过校验）
    if (_tick % 13 == 0) {
      emitBytes(utf8.encode(_targets.first.buildSentence(stampUtc: now, dropMiddleFields: true)));
    }

    // ④ 重复上报（同呼号 + 同内容）→ 验证覆盖并置顶
    if (_tick % 5 == 0) {
      emitBytes(utf8.encode(_targets[1].buildSentence(stampUtc: now)));
    }
  }

  /// 台站数据取自真实采集（BI7NOR 2025-08），坐标由度分换算而来。
  final List<_DemoTarget> _targets = <_DemoTarget>[
    const _DemoTarget(
      callsign: 'BG1UBU-9',
      status: 'A',
      icon: '/j',
      latitude: 39.91633,
      longitude: 116.27717,
      altitude: 7,
      course: 83,
      distance: 52,
      driftLat: 0.00030,
      driftLon: 0.00055,
    ),
    const _DemoTarget(
      callsign: 'BI4PGN-11',
      status: 'V',
      icon: '/i',
      latitude: 39.97583,
      longitude: 116.42833,
      // 真实报文里这三项为空 → 演示「空字段」也能正常显示
    ),
    const _DemoTarget(
      callsign: 'BY1BJ-1',
      status: 'V',
      icon: '/r',
      latitude: 40.00500,
      longitude: 116.16933,
      distance: 50,
    ),
    const _DemoTarget(
      callsign: 'BH3BBJ-1',
      status: 'V',
      icon: '/r',
      latitude: 39.13000,
      longitude: 117.20333,
    ),
    const _DemoTarget(
      callsign: 'BI1AR-1',
      status: 'V',
      icon: '/&',
      latitude: 39.97433,
      longitude: 116.31583,
    ),
    const _DemoTarget(
      callsign: 'BG1QGD-10',
      status: 'V',
      icon: '/r',
      latitude: 40.00767,
      longitude: 116.54217,
      driftLat: -0.00020,
      driftLon: 0.00040,
    ),
  ];
}

/// 模拟目标。
class _DemoTarget {
  const _DemoTarget({
    required this.callsign,
    required this.status,
    required this.icon,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.course,
    this.distance,
    this.driftLat = 0,
    this.driftLon = 0,
  });

  final String callsign;
  final String status;
  final String icon;
  final double latitude;
  final double longitude;
  final int? altitude;
  final int? course;
  final int? distance;
  final double driftLat;
  final double driftLon;

  /// 有漂移的（移动台站）每拍走一小步，方便观察「置顶」与地图上的位置变化。
  _DemoTarget ticked() => _DemoTarget(
        callsign: callsign,
        status: status,
        icon: icon,
        latitude: latitude + driftLat,
        longitude: longitude + driftLon,
        altitude: altitude,
        course: course == null ? null : (course! + 3) % 360,
        distance: distance,
        driftLat: driftLat,
        driftLon: driftLon,
      );

  /// 拼一条 `$PKWDWPL` 语句（含真实计算的校验和与 CRLF 结尾）。
  ///
  /// [dropMiddleFields] 为 true 时故意省略「海拔、航向」两个逗号字段，
  /// 得到 10 个逗号字段的语句（模拟采集/转发丢逗号），校验和按实际内容计算。
  String buildSentence({
    required DateTime stampUtc,
    bool corruptChecksum = false,
    bool dropMiddleFields = false,
  }) {
    String two(int v) => v.toString().padLeft(2, '0');

    final String time =
        '${two(stampUtc.hour)}${two(stampUtc.minute)}${two(stampUtc.second)}';
    final String date =
        '${two(stampUtc.day)}${two(stampUtc.month)}${two(stampUtc.year % 100)}';

    final double lat = latitude.clamp(-90.0, 90.0);
    final double lon = longitude.clamp(-180.0, 180.0);

    final List<String> fields = <String>[
      'PKWDWPL',
      time,
      status,
      GeoMath.decimalToDm(lat),
      lat >= 0 ? 'N' : 'S',
      GeoMath.decimalToDm(lon),
      lon >= 0 ? 'E' : 'W',
      altitude?.toString() ?? '',
      course?.toString() ?? '',
      date,
      distance?.toString().padLeft(6, '0') ?? '',
      callsign,
      icon,
    ];

    if (dropMiddleFields) {
      // 去掉「海拔、航向」两个字段（连带逗号）→ 剩 10 个逗号字段，
      // 模拟采集/转发时丢逗号的情形。
      fields.removeRange(6, 8);
    }

    final String body = fields.join(',');
    final String checksum = corruptChecksum
        ? '00'
        : NmeaChecksum.format(NmeaChecksum.computeFrom(body));

    return r'$' '$body*$checksum\r\n';
  }
}
