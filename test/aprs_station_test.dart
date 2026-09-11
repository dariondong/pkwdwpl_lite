import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/models/aprs_icon.dart';
import 'package:pkwdwpl_lite/models/geo_math.dart';

void main() {
  group('NMEA XOR 校验', () {
    test(r'业界标准示例 $GPGGA...*47 校验通过', () {
      const String sentence =
          r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47';
      final NmeaChecksumCheck check = NmeaChecksum.check(sentence);
      expect(check.hasChecksum, isTrue);
      expect(check.claimedHex, '47');
      expect(check.computedHex, '47');
      expect(check.valid, isTrue);
    });

    test('需求文档中的示例语句，实际校验和是 2E 而不是 35', () {
      const String sentence =
          r'$PKWDWPL,102202,M,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j*35';
      final NmeaChecksumCheck check = NmeaChecksum.check(sentence);
      expect(check.computedHex, '2E');
      expect(check.claimedHex, '35');
      expect(check.valid, isFalse);
    });

    test('缺失校验和时 hasChecksum 为 false', () {
      const String sentence =
          r'$PKWDWPL,102202,M,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j';
      final NmeaChecksumCheck check = NmeaChecksum.check(sentence);
      expect(check.hasChecksum, isFalse);
      expect(check.valid, isFalse);
      expect(check.computedHex, '2E');
    });
  });

  group('度分 → 十进制', () {
    test('纬度 3954.98 → 39.91633', () {
      expect(GeoMath.dmToDecimal('3954.98'), closeTo(39.916333, 1e-6));
    });

    test('经度 11616.63 → 116.27717', () {
      expect(GeoMath.dmToDecimal('11616.63'), closeTo(116.277167, 1e-6));
    });

    test('南纬 / 西经为负', () {
      expect(GeoMath.dmToDecimal('3352.00', hemisphere: 'S'), closeTo(-33.866667, 1e-6));
      expect(GeoMath.dmToDecimal('11814.00', hemisphere: 'W'), closeTo(-118.233333, 1e-6));
    });

    test('非法输入返回 null（分 ≥ 60 也算非法）', () {
      expect(GeoMath.dmToDecimal(''), isNull);
      expect(GeoMath.dmToDecimal('99'), isNull);
      expect(GeoMath.dmToDecimal('3960.00'), isNull);
      expect(GeoMath.dmToDecimal(null), isNull);
    });

    test('十进制度 → 度分（回环）', () {
      expect(GeoMath.decimalToDm(39.916333), '3954.98');
      expect(GeoMath.decimalToDm(116.277167), '11616.63');
    });

    test('haversine：北京 → 天津约 110km 量级', () {
      final double meters =
          GeoMath.haversineMeters(39.91633, 116.27717, 39.08510, 117.19930);
      expect(meters, greaterThan(100000));
      expect(meters, lessThan(140000));
    });
  });

  group('APRS 图标映射', () {
    test('/j 与 /> → 汽车', () {
      expect(AprsIconMapper.iconFor('/j'), Icons.directions_car);
      expect(AprsIconMapper.iconFor('/>'), Icons.directions_car);
    });

    test('/- → 房屋', () {
      expect(AprsIconMapper.iconFor('/-'), Icons.home);
    });

    test('未知符号 → 电台兜底', () {
      expect(AprsIconMapper.iconFor('/z'), AprsIconMapper.fallbackIcon);
      expect(AprsIconMapper.iconFor(''), AprsIconMapper.fallbackIcon);
      expect(AprsIconMapper.iconFor(null), AprsIconMapper.fallbackIcon);
    });
  });

  group('AprsStationParser', () {
    // 用真实校验和修正后的示例（*2E）。
    const String valid =
        r'$PKWDWPL,102202,M,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j*2E';

    test('完整解析 14 个字段', () {
      final AprsStation station = AprsStationParser.parse(valid);

      expect(station.raw, valid);
      expect(station.callsign, 'BG1UBU-9');
      expect(station.utcTime, '102202');
      expect(station.utcDate, '290625');
      expect(station.statusRaw, 'M');
      expect(station.statusValid, isNull); // M 既不是 A 也不是 V
      expect(station.latitude, closeTo(39.916333, 1e-5));
      expect(station.longitude, closeTo(116.277167, 1e-5));
      expect(station.altitudeMeters, 7);
      expect(station.courseDegrees, 83);
      expect(station.distanceMeters, 52);
      expect(station.iconRaw, '/j');
      expect(station.icon, Icons.directions_car);
      expect(station.claimedChecksum, '2E');
      expect(station.computedChecksum, '2E');
      expect(station.checksumValid, isTrue);

      expect(station.rawFields.length, 14);
      expect(station.fieldRows.length, 14);
      expect(station.fieldRows.first.value, r'$PKWDWPL');
      expect(station.fieldRows.last.value, '*2E');

      expect(
        station.utcDateTime,
        DateTime.utc(2025, 6, 29, 10, 22, 2),
      );
    });

    test('状态 A/V 解析为有效/无效（校验和分别为 *76 / *61）', () {
      final AprsStation a = AprsStationParser.parse(
        r'$PKWDWPL,102202,A,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/>*76',
      );
      expect(a.statusValid, isTrue);
      expect(a.checksumValid, isTrue);
      expect(a.icon, Icons.directions_car);

      final AprsStation v = AprsStationParser.parse(
        r'$PKWDWPL,102202,V,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/>*61',
      );
      expect(v.statusValid, isFalse);
      expect(v.checksumValid, isTrue);
    });

    test('严格模式：校验和错误 → 丢弃', () {
      const String bad =
          r'$PKWDWPL,102202,M,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j*35';
      final AprsParseResult result = AprsStationParser.tryParse(bad);
      expect(result.isSuccess, isFalse);
      expect(result.error!.code, AprsParseErrorCode.checksumMismatch);
      expect(result.error!.detail, '35 != 2E');

      expect(
        () => AprsStationParser.parse(bad),
        throwsA(isA<AprsParseException>()),
      );
    });

    test('宽松模式：校验和错误仍然解析，但带 softError', () {
      const String bad =
          r'$PKWDWPL,102202,M,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j*35';
      final AprsStation station =
          AprsStationParser.parse(bad, strictChecksum: false);
      expect(station.callsign, 'BG1UBU-9');
      expect(station.checksumValid, isFalse);
      expect(station.softError, isNotNull);
      expect(station.softError!.code, AprsParseErrorCode.checksumMismatch);
    });

    test('兼容 CRLF 结尾与前后空白', () {
      final AprsStation station = AprsStationParser.parse('  $valid  \r\n');
      expect(station.callsign, 'BG1UBU-9');
    });

    test('非 PKWDWPL 语句被拒绝', () {
      expect(
        AprsStationParser.tryParse(r'$GPGGA,123519,4807.038,N*47').error!.code,
        AprsParseErrorCode.notPkwdwpl,
      );
      expect(
        AprsStationParser.tryParse('hello world').error!.code,
        AprsParseErrorCode.noStart,
      );
      expect(
        AprsStationParser.tryParse('').error!.code,
        AprsParseErrorCode.emptyLine,
      );
    });

    test('字段不足被拒绝', () {
      final AprsParseResult result =
          AprsStationParser.tryParse(r'$PKWDWPL,102202,M,3954.98,N', strictChecksum: false);
      expect(result.error!.code, AprsParseErrorCode.tooFewFields);
    });

    test('非法纬度被拒绝', () {
      final AprsParseResult result = AprsStationParser.tryParse(
        r'$PKWDWPL,102202,M,9960.00,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j*22',
      );
      expect(result.error!.code, AprsParseErrorCode.badLatitude);
    });

    test('JSON 往返', () {
      final AprsStation station = AprsStationParser.parse(valid);
      final AprsStation restored = AprsStation.fromJson(station.toJson());
      expect(restored.callsign, station.callsign);
      expect(restored.latitude, closeTo(station.latitude, 1e-9));
      expect(restored.receivedAt, station.receivedAt);
      expect(restored.icon, station.icon);
    });
  });
}
