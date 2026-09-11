import 'package:flutter/foundation.dart';

import '../core/app_settings.dart';
import '../models/aprs_station.dart';
import 'aprs_bus.dart';

/// 接收统计（列表页顶部展示，方便现场判断链路是否正常）。
class AprsStats {
  const AprsStats({
    this.lines = 0,
    this.accepted = 0,
    this.checksumFailed = 0,
    this.malformed = 0,
    this.flagged = 0,
  });

  /// 收到的语句行总数。
  final int lines;

  /// 成功解析并入库的数量。
  final int accepted;

  /// 校验和错误的数量。
  final int checksumFailed;

  /// 其它格式错误（字段不足 / 坐标非法等）。
  final int malformed;

  /// 入库但「有问题」的数量（字段数异常 / 呼号可疑 / 校验不符但宽松接收）。
  final int flagged;

  AprsStats copyWith({
    int? lines,
    int? accepted,
    int? checksumFailed,
    int? malformed,
    int? flagged,
  }) =>
      AprsStats(
        lines: lines ?? this.lines,
        accepted: accepted ?? this.accepted,
        checksumFailed: checksumFailed ?? this.checksumFailed,
        malformed: malformed ?? this.malformed,
        flagged: flagged ?? this.flagged,
      );
}

/// 台站台账：以**呼号为 Key** 的 Map，新数据覆盖旧数据并置顶。
///
/// 用 `LinkedHashMap`（Dart 里普通 Map 就是插入有序）实现「置顶」：
/// 每次写入前先 `remove` 再 `put`，该呼号就跑到 Map 末尾；
/// 对外暴露时再反转一次，得到「最新的在最上面」。
class StationStore extends ChangeNotifier {
  StationStore({this.maxStations = 500});

  /// 最多保留多少个台站（超出丢弃最旧的），避免长时间运行内存无上限增长。
  final int maxStations;

  final Map<String, AprsStation> _byCallsign = <String, AprsStation>{};
  AprsStats _stats = const AprsStats();

  /// 最近一次解析失败的原因（列表页/连接页可展示）。
  AprsParseError? _lastError;

  /// 接收序号计数器：每条**成功解析**的语句 +1（列表页第一列显示它）。
  int _sequence = 0;

  int get sequence => _sequence;

  /// 最新的在最前（第一项 = 最近收到）。
  List<AprsStation> get stations =>
      _byCallsign.values.toList(growable: false).reversed.toList(growable: false);

  /// 按筛选条件取列表。
  List<AprsStation> filteredStations(StationFilter filter) {
    switch (filter) {
      case StationFilter.all:
        return stations;
      case StationFilter.valid:
        return stations
            .where((AprsStation s) => s.statusValid == true && !s.hasWarnings)
            .toList(growable: false);
      case StationFilter.flagged:
        return stations.where((AprsStation s) => s.hasWarnings).toList(growable: false);
    }
  }

  AprsStats get stats => _stats;

  AprsParseError? get lastError => _lastError;

  int get count => _byCallsign.length;

  bool get isEmpty => _byCallsign.isEmpty;

  AprsStation? byCallsign(String callsign) => _byCallsign[callsign.toUpperCase()];

  /// 最近一条数据（列表页 AppBar 的「最后更新」用）。
  AprsStation? get latest => _byCallsign.isEmpty ? null : _byCallsign.values.last;

  /// 写入 / 覆盖一条台站数据。
  void upsert(AprsStation station) {
    final String key = station.callsign.toUpperCase();
    _byCallsign.remove(key); // 先删后插 → 置顶
    _byCallsign[key] = station;

    if (_byCallsign.length > maxStations) {
      _byCallsign.remove(_byCallsign.keys.first);
    }

    AprsBus.emitStation(station);
    notifyListeners();
  }

  /// 解析并写入一行原始 NMEA 语句。
  ///
  /// [strictChecksum] 为 true（默认，符合需求 3）时，校验和错误 → 丢弃 + 控制台告警；
  /// 为 false 时仍然入库，但该条会带 [AprsStation.softError]，界面上标注出来。
  ///
  /// 返回是否成功入库。
  bool addRawLine(String line, {bool strictChecksum = true}) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return false;

    AprsBus.emitRawLine(trimmed);

    final AprsParseResult result = AprsStationParser.tryParse(
      trimmed,
      strictChecksum: strictChecksum,
      receiveSeq: _sequence + 1,
    );

    if (result.isSuccess) {
      final AprsStation station = result.station!;
      _sequence++;
      _stats = _stats.copyWith(
        lines: _stats.lines + 1,
        accepted: _stats.accepted + 1,
        flagged: _stats.flagged + (station.hasWarnings ? 1 : 0),
      );
      _lastError = station.softError; // 宽松模式下也提示出来
      upsert(station);
      return true;
    }

    final AprsParseError error = result.error!;
    _lastError = error;
    _stats = _stats.copyWith(
      lines: _stats.lines + 1,
      checksumFailed: _stats.checksumFailed +
          (error.code == AprsParseErrorCode.checksumMismatch ? 1 : 0),
      malformed: _stats.malformed +
          (error.code == AprsParseErrorCode.checksumMismatch ? 0 : 1),
    );

    // 需求 3：控制台打印警告。
    debugPrint(
      '[PKWDWPL] ⚠ 丢弃语句 (${error.code.name}'
      '${error.detail == null ? '' : ', ${error.detail}'}): ${error.raw}',
    );
    notifyListeners();
    return false;
  }

  /// 删除某个呼号。
  void remove(String callsign) {
    if (_byCallsign.remove(callsign.toUpperCase()) != null) {
      notifyListeners();
    }
  }

  /// 清空台账与统计（接收序号也归零）。
  void clear() {
    _byCallsign.clear();
    _stats = const AprsStats();
    _lastError = null;
    _sequence = 0;
    notifyListeners();
  }
}
