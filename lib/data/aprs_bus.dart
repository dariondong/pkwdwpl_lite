import 'dart:async';

import '../models/aprs_station.dart';

/// 全局数据总线：把「解析好的台站」以广播 Stream 的形式抛出去。
///
/// 为什么要它？——需求 2 里提到 App 要后台保活，主 Isolate 里维持蓝牙连接，
/// UI（以及你可能新增的后台 Service Isolate、日志页、悬浮窗）只订阅这个流即可：
///
/// ```dart
/// AprsBus.stations.listen((station) => ...);
/// AprsBus.rawLines.listen((line) => ...);   // 原始 NMEA，调试/落盘用
/// ```
///
/// 这样你的保活架构只需要「把收到的字节喂给 [NmeaLineSplitter] /
/// [StationStore.addRawLine]」，不必关心 UI 如何渲染。
class AprsBus {
  const AprsBus._();

  static final StreamController<AprsStation> _stations =
      StreamController<AprsStation>.broadcast();
  static final StreamController<String> _rawLines =
      StreamController<String>.broadcast();

  /// 每成功解析出一条第 12 字段（呼号）有效的语句，就推送一个 [AprsStation]。
  static Stream<AprsStation> get stations => _stations.stream;

  /// 每一行通过分帧的原始语句（含解析失败的），适合调试或写日志文件。
  static Stream<String> get rawLines => _rawLines.stream;

  static void emitStation(AprsStation station) {
    if (!_stations.isClosed) _stations.add(station);
  }

  static void emitRawLine(String line) {
    if (!_rawLines.isClosed) _rawLines.add(line);
  }
}
