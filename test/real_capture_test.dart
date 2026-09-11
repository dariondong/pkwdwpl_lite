import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';

/// BI7NOR 于 2025-08 采集的 **10 条真实 `$PKWDWPL` 报文**回归测试。
///
/// 这组用例的价值在于：它是「真实电台/真实链路」的数据，
/// 而不是我们自己编造的理想数据。开发过程中就是用这组数据定位出：
///
///   1. 校验算法本身没问题（7/10 通过；权威 NMEA 示例 `*47` 也能算对）；
///   2. 3 条不通过的都是**采集时的手误**，其中 2 条已能证明：
///      * `BG1UB9` 应为 `BG1UBU-9`（改成它后校验和正好等于报文里的 0C）；
///      * 102940 那条漏了一个逗号（补成 `E,,,290625` 后校验和正好等于 4E）；
///   3. **字段数最少可以是 10**（`E,290625,,call,icon` 这种写法里第 8/9 字段为空），
///      所以「严格按 12 字段解析」会把真实数据判成格式错误 —— 必须容错解析。
const List<String> realCaptures = <String>[
  r'$PKWDWPL,102339,V,3958.55,N,11625.70,E,,,290625,,BI4PGN-11,/i*22',
  r'$PKWDWPL,102353,V,3955.09,N,11616.91,E,4,103,290625,000050,BG1UB9,/j*0C',
  r'$PKWDWPL,102439,V,4000.30,N,11610.16,E,,,290625,,BY1BJ-1,/r*4D',
  r'$PKWDWPL,102537,V,3958.46,N,11618.95,E,290625,,BI1AR-1,/&*1C',
  r'$PKWDWPL,102627,V,3907.80,N,11712.20,E,,,290625,,BH3BBJ-1,/r*15',
  r'$PKWDWPL,102629,V,3907.80,N,11712.20,E,,,290625,,BH3BBJ-1,/r*1B',
  r'$PKWDWPL,102843,V,3948.57,N,11645.32,E,,,290625,,BI4PGN1-1,/i*24',
  r'$PKWDWPL,102921,V,4000.46,N,11632.53,E,,,290625,,BG1QGD-10,/r*3D',
  r'$PKWDWPL,102939,V,4000.30,N,11610.16,E,,,290625,,BY1BJ-1,/r*40',
  r'$PKWDWPL,102940,V,4000.30,N,11610.16,E,,290625,,BY1BJ-1,/r*4E',
];

void main() {
  group('真实报文：校验和复算', () {
    test('逐条复算校验和（7/10 通过）', () {
      // key = 报文序号 1..10，value = (计算值, 是否与报文一致)
      const Map<int, (String, bool)> expected = <int, (String, bool)>{
        1: ('22', true),
        2: ('74', false), // BG1UB9 是手误（应为 BG1UBU-9）
        3: ('4D', true),
        4: ('1C', true),
        5: ('15', true),
        6: ('1B', true),
        7: ('27', false), // BI4PGN1-1 字符换位/替换（XOR 查不出换位，见下）
        8: ('3D', true),
        9: ('40', true),
        10: ('62', false), // 漏了一个逗号
      };

      int passed = 0;
      for (int i = 0; i < realCaptures.length; i++) {
        final NmeaChecksumCheck check = NmeaChecksum.check(realCaptures[i]);
        final (String hex, bool ok) = expected[i + 1]!;
        expect(check.computedHex, hex, reason: '第 ${i + 1} 条计算值不符');
        expect(check.valid, ok, reason: '第 ${i + 1} 条有效性判断不符');
        if (ok) passed++;
      }
      expect(passed, 7);
    });

    test('手误定性 ①：BG1UB9 → BG1UBU-9 后校验和正好等于报文里的 0C', () {
      const String fixed =
          r'$PKWDWPL,102353,V,3955.09,N,11616.91,E,4,103,290625,000050,BG1UBU-9,/j*0C';
      final NmeaChecksumCheck check = NmeaChecksum.check(fixed);
      expect(check.computedHex, '0C');
      expect(check.valid, isTrue);
    });

    test('手误定性 ②：102940 那条补一个逗号后校验和正好等于报文里的 4E', () {
      const String fixed =
          r'$PKWDWPL,102940,V,4000.30,N,11610.16,E,,,290625,,BY1BJ-1,/r*4E';
      final NmeaChecksumCheck check = NmeaChecksum.check(fixed);
      expect(check.computedHex, '4E');
      expect(check.valid, isTrue);
    });

    test('XOR 的固有局限：字符换位改变不了校验和', () {
      // BI4PGN1-1 与 BI4PGN-11 是同一批字符的换位，XOR 完全相同
      final int a = NmeaChecksum.computeFrom('BI4PGN1-1');
      final int b = NmeaChecksum.computeFrom('BI4PGN-11');
      expect(a, b);
    });
  });

  group('真实报文：严格模式解析', () {
    test('7 条通过校验的能被严格模式接收', () {
      final List<int> accepted = <int>[];
      final List<int> rejected = <int>[];
      for (int i = 0; i < realCaptures.length; i++) {
        final AprsParseResult result = AprsStationParser.tryParse(realCaptures[i]);
        (result.isSuccess ? accepted : rejected).add(i + 1);
      }
      expect(accepted, <int>[1, 3, 4, 5, 6, 8, 9]);
      expect(rejected, <int>[2, 7, 10]);
    });

    test('第 1 条：空的海拔/航向/距离 → null，但坐标与日期正常', () {
      final AprsStation station = AprsStationParser.parse(realCaptures[0]);
      expect(station.callsign, 'BI4PGN-11');
      expect(station.statusRaw, 'V');
      expect(station.statusValid, isFalse);
      expect(station.latitude, closeTo(39.975833, 1e-6));
      expect(station.longitude, closeTo(116.428333, 1e-6));
      expect(station.altitudeMeters, isNull);
      expect(station.courseDegrees, isNull);
      expect(station.distanceMeters, isNull);
      expect(station.utcDate, '290625');
      expect(station.iconRaw, '/i');
      expect(station.parsedFieldCount, 12);
      expect(station.fieldCountAnomaly, isFalse);
      expect(station.callsignSuspicious, isFalse);
      expect(station.utcDateTime, DateTime.utc(2025, 6, 29, 10, 23, 39));
    });

    test('第 4 条：只有 10 个逗号字段，容错解析仍能拿到呼号/坐标/日期', () {
      final AprsStation station = AprsStationParser.parse(realCaptures[3]);
      expect(station.parsedFieldCount, 10);
      expect(station.fieldCountAnomaly, isTrue);
      expect(station.callsign, 'BI1AR-1');
      expect(station.iconRaw, '/&');
      expect(station.utcDate, '290625');
      expect(station.latitude, closeTo(39.974333, 1e-6));
      expect(station.longitude, closeTo(116.315833, 1e-6));
      expect(station.altitudeMeters, isNull);
      expect(station.courseDegrees, isNull);
      expect(station.distanceMeters, isNull);
      expect(station.hasWarnings, isTrue);
    });

    test('第 3 条：字段 11 为空 → distanceMeters 为 null（不是 0）', () {
      final AprsStation station = AprsStationParser.parse(realCaptures[2]);
      expect(station.callsign, 'BY1BJ-1');
      expect(station.distanceMeters, isNull);
      expect(station.distanceRaw, '');
      expect(station.parsedFieldCount, 12);
    });

    test('第 2 条：呼号 BG1UB9 会被标记为「格式可疑」', () {
      final AprsStation station =
          AprsStationParser.parse(realCaptures[1], strictChecksum: false);
      expect(station.callsign, 'BG1UB9');
      expect(station.callsignSuspicious, isTrue);
      expect(station.checksumValid, isFalse);
      // 海拔/航向/距离都有值
      expect(station.altitudeMeters, 4);
      expect(station.courseDegrees, 103);
      expect(station.distanceMeters, 50);
      expect(station.distanceRaw, '000050');
    });

    test('第 7 条：BI4PGN1-1 呼号格式可疑（疑似 BI4PGN-11 手误）', () {
      final AprsStation station =
          AprsStationParser.parse(realCaptures[6], strictChecksum: false);
      expect(station.callsignSuspicious, isTrue);
      expect(station.checksumValid, isFalse);
    });

    test('第 10 条：11 个字段的降级解析（日期仍能定位）', () {
      final AprsStation station =
          AprsStationParser.parse(realCaptures[9], strictChecksum: false);
      expect(station.parsedFieldCount, 11);
      expect(station.fieldCountAnomaly, isTrue);
      expect(station.callsign, 'BY1BJ-1');
      expect(station.iconRaw, '/r');
      expect(station.utcDate, '290625');
      expect(station.latitude, closeTo(40.005, 1e-6));
      expect(station.checksumValid, isFalse);
    });

    test('所有真实台站的呼号格式检查：正常呼号不被误报', () {
      const List<String> okCallsigns = <String>[
        'BI4PGN-11',
        'BY1BJ-1',
        'BI1AR-1',
        'BH3BBJ-1',
        'BG1QGD-10',
        'BG1UBU-9',
      ];
      for (final String callsign in okCallsigns) {
        expect(
          AprsStationParser.callsignPattern.hasMatch(callsign),
          isTrue,
          reason: '$callsign 不应该被误判',
        );
      }
      for (final String callsign in <String>['BG1UB9', 'BI4PGN1-1', 'ABC']) {
        expect(
          AprsStationParser.callsignPattern.hasMatch(callsign),
          isFalse,
          reason: '$callsign 应该被判为可疑',
        );
      }
    });
  });
}
