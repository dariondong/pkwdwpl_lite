import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/data/station_store.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';

/// 用真实 XOR 校验和拼一条合法语句（测试里绝不手写校验和，避免自欺欺人）。
String sentence({
  String callsign = 'BG1UBU-9',
  String time = '102202',
  String status = 'M',
  String latDm = '3954.98',
  String latHemi = 'N',
  String lonDm = '11616.63',
  String lonHemi = 'E',
  String altitude = '7',
  String course = '83',
  String date = '290625',
  String distance = '000052',
  String icon = '/j',
  String? checksumOverride,
}) {
  final String body = <String>[
    'PKWDWPL',
    time,
    status,
    latDm,
    latHemi,
    lonDm,
    lonHemi,
    altitude,
    course,
    date,
    distance,
    callsign,
    icon,
  ].join(',');
  final String checksum =
      checksumOverride ?? NmeaChecksum.format(NmeaChecksum.computeFrom(body));
  return r'$' '$body*$checksum';
}

void main() {
  final String bg1 = sentence(callsign: 'BG1UBU-9');
  final String bg1Moved = sentence(callsign: 'BG1UBU-9', altitude: '50', course: '120');
  final String bg7 = sentence(callsign: 'BG7LZQ-7', status: 'A', icon: '/-');
  // 需求文档里的原始示例：*35 是错的（正确应为 *2E）。
  final String badChecksum = sentence(callsign: 'BG1UBU-9', checksumOverride: '35');
  const String malformed = r'$PKWDWPL,102202,M,3954.98,N';
  const String notPkwdwpl = r'$GPGGA,123519,4807.038,N*47';

  group('StationStore', () {
    test('以呼号为 Key：同呼号覆盖并置顶', () {
      final StationStore store = StationStore();

      // BG7 先入库，随后 BG1 入库 → 列表顺序为 [BG1, BG7]（最新在前）。
      expect(store.addRawLine(bg7), isTrue);
      expect(store.addRawLine(bg1), isTrue);
      expect(store.count, 2);
      expect(store.stations.first.callsign, 'BG1UBU-9');

      // BG7 收到新数据 → 置顶，且数量不变。
      expect(store.addRawLine(bg7), isTrue);
      expect(store.count, 2);
      expect(store.stations.first.callsign, 'BG7LZQ-7');
    });

    test('同呼号新数据覆盖旧数据', () {
      final StationStore store = StationStore();
      store.addRawLine(bg1);
      store.addRawLine(bg1Moved);
      expect(store.count, 1);
      expect(store.byCallsign('BG1UBU-9')!.altitudeMeters, 50);
      expect(store.byCallsign('bg1ubu-9')!.courseDegrees, 120); // 呼号大小写不敏感
    });

    test('严格模式下校验和错误不入库，并计入统计', () {
      final StationStore store = StationStore();
      expect(store.addRawLine(badChecksum), isFalse);
      expect(store.count, 0);
      expect(store.stats.lines, 1);
      expect(store.stats.checksumFailed, 1);
      expect(store.stats.malformed, 0);
      expect(store.lastError!.code, AprsParseErrorCode.checksumMismatch);
    });

    test('宽松模式下校验和错误仍入库', () {
      final StationStore store = StationStore();
      expect(store.addRawLine(badChecksum, strictChecksum: false), isTrue);
      expect(store.count, 1);
      expect(store.stations.first.checksumValid, isFalse);
      expect(store.stations.first.softError, isNotNull);
    });

    test('格式错误计入 malformed', () {
      final StationStore store = StationStore();
      store.addRawLine(malformed, strictChecksum: false);
      store.addRawLine(notPkwdwpl, strictChecksum: false);
      expect(store.count, 0);
      expect(store.stats.malformed, 2);
      expect(store.stats.checksumFailed, 0);
    });

    test('超过 maxStations 时丢弃最旧的', () {
      final StationStore store = StationStore(maxStations: 2);
      store.addRawLine(sentence(callsign: 'A1AAA'));
      store.addRawLine(sentence(callsign: 'A2AAA'));
      store.addRawLine(sentence(callsign: 'A3AAA'));
      expect(store.count, 2);
      expect(store.byCallsign('A1AAA'), isNull);
      expect(store.byCallsign('A3AAA'), isNotNull);
    });

    test('clear 清空数据与统计', () {
      final StationStore store = StationStore();
      store.addRawLine(bg1);
      store.clear();
      expect(store.count, 0);
      expect(store.stats.lines, 0);
      expect(store.isEmpty, isTrue);
      expect(store.sequence, 0);
    });

    test('接收序号（列表第一个字段）递增，且与成功入库数一致', () {
      final StationStore store = StationStore();
      store.addRawLine(bg1);
      store.addRawLine(bg7);
      store.addRawLine(badChecksum); // 严格模式拒绝
      store.addRawLine(bg1Moved);

      expect(store.stats.accepted, 3);
      expect(store.sequence, 3);
      // bg1 → #1，bg7 → #2，bg1Moved → #3（同呼号覆盖，序号取最新一条）
      expect(store.byCallsign('BG1UBU-9')!.receiveSeq, 3);
      expect(store.byCallsign('BG7LZQ-7')!.receiveSeq, 2);
    });

    test('筛选：仅有效 / 仅存疑', () {
      final StationStore store = StationStore();
      store.addRawLine(bg1); // status M → 未知
      store.addRawLine(bg7); // status A → 有效
      store.addRawLine(badChecksum, strictChecksum: false); // 校验不符 → 存疑

      expect(store.filteredStations(StationFilter.all).length, 2);
      expect(store.filteredStations(StationFilter.valid).length, 1);
      expect(
        store.filteredStations(StationFilter.valid).first.callsign,
        'BG7LZQ-7',
      );
      expect(store.filteredStations(StationFilter.flagged).length, 1);
    });
  });
}
