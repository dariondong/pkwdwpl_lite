import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/models/geo_math.dart';
import 'package:pkwdwpl_lite/models/map_bounds.dart';

void main() {
  group('MapBounds', () {
    test('project：左上角是 maxLat/minLon，右下角是 minLat/maxLon', () {
      const MapBounds bounds = MapBounds(
        minLatitude: 39.0,
        maxLatitude: 41.0,
        minLongitude: 116.0,
        maxLongitude: 118.0,
      );
      const Size size = Size(200, 100);

      final Offset topLeft = bounds.project(41.0, 116.0, size);
      expect(topLeft.dx, closeTo(0, 1e-9));
      expect(topLeft.dy, closeTo(0, 1e-9));

      final Offset bottomRight = bounds.project(39.0, 118.0, size);
      expect(bottomRight.dx, closeTo(200, 1e-6));
      expect(bottomRight.dy, closeTo(100, 1e-6));

      // 正中心
      final Offset center = bounds.project(40.0, 117.0, size);
      expect(center.dx, closeTo(100, 1e-6));
      expect(center.dy, closeTo(50, 1e-6));
    });

    test('fromPoints：自动范围 + 边距 + 单点最小跨度', () {
      final MapBounds? bounds = MapBounds.fromPoints(
        <({double latitude, double longitude})>[
          (latitude: 39.0, longitude: 116.0),
          (latitude: 41.0, longitude: 118.0),
        ],
        padRatio: 0.1,
      );
      expect(bounds, isNotNull);
      expect(bounds!.minLatitude, lessThan(39.0));
      expect(bounds.maxLatitude, greaterThan(41.0));
      expect(bounds.contains(40.0, 117.0), isTrue);

      // 单点：给出最小跨度，避免画布退化
      final MapBounds? single = MapBounds.fromPoints(
        <({double latitude, double longitude})>[
          (latitude: 39.9, longitude: 116.4),
        ],
      );
      expect(single, isNotNull);
      expect(single!.latitudeSpan, greaterThan(0.01));
      expect(single.longitudeSpan, greaterThan(0.01));

      expect(MapBounds.fromPoints(const <({double latitude, double longitude})>[]), isNull);
    });

    test('aspectRatio：经度方向按纬度做 cos 校正', () {
      const MapBounds bounds = MapBounds(
        minLatitude: 39,
        maxLatitude: 41,
        minLongitude: 116,
        maxLongitude: 118,
      );
      // 40°N 处 cos≈0.766 → 宽高比 ≈ 2*0.766/2 ≈ 0.766
      expect(bounds.aspectRatio, closeTo(0.766, 0.01));
    });

    test('JSON 往返', () {
      const MapBounds bounds = MapBounds(
        minLatitude: 38.5,
        maxLatitude: 41.5,
        minLongitude: 115.5,
        maxLongitude: 118.5,
      );
      final MapBounds? restored = MapBounds.fromJson(bounds.toJson());
      expect(restored, bounds);
      expect(MapBounds.fromJson(<String, double>{'minLat': 1}), isNull);
    });
  });

  group('距离 / 速度格式化', () {
    test('公制：m 与 km 自动切换', () {
      expect(GeoMath.formatMeters(850, DistanceUnit.metric), '850 m');
      expect(GeoMath.formatMeters(5200, DistanceUnit.metric), '5.20 km');
      expect(GeoMath.formatMeters(52300, DistanceUnit.metric), '52.3 km');
    });

    test('英制：ft 与 mi 自动切换', () {
      expect(GeoMath.formatMeters(100, DistanceUnit.imperial), '328 ft');
      expect(GeoMath.formatMeters(1609.344, DistanceUnit.imperial), '1.00 mi');
      expect(
        GeoMath.formatMeters(16093.44, DistanceUnit.imperial),
        '10.0 mi',
      );
    });

    test('速度：km/h ↔ mph', () {
      expect(GeoMath.formatSpeedKph(50, DistanceUnit.metric), '50 km/h');
      expect(GeoMath.formatSpeedKph(50, DistanceUnit.imperial), '31 mph');
    });

    test('异常值不抛异常', () {
      expect(GeoMath.formatMeters(double.nan, DistanceUnit.metric), '--');
      expect(GeoMath.formatMeters(double.infinity, DistanceUnit.imperial), '--');
    });

    test('十进制度 → 度分：分的整数部分必须补两位（真实数据回归）', () {
      // 真实报文里这些写法都是四位整数部分
      expect(GeoMath.decimalToDm(39.13), '3907.80'); // 曾错成 397.80
      expect(GeoMath.decimalToDm(40.005), '4000.30');
      expect(GeoMath.decimalToDm(39.975833), '3958.55');
      expect(GeoMath.decimalToDm(39.974333), '3958.46');
      expect(GeoMath.decimalToDm(40.007667), '4000.46');
      // 经度 5 位
      expect(GeoMath.decimalToDm(116.428333), '11625.70');
      expect(GeoMath.decimalToDm(117.203333), '11712.20');
      // 回环：度分 → 十进制
      expect(GeoMath.dmToDecimal('3907.80'), closeTo(39.13, 1e-9));
    });

    test('真实台站之间的距离量级合理（北京西部 → 京东）', () {
      // BI4PGN-11 (39.975833,116.428333) → BH3BBJ-1 (39.130000,117.203333)
      final double meters =
          GeoMath.haversineMeters(39.975833, 116.428333, 39.13, 117.203333);
      expect(meters, greaterThan(90000));
      expect(meters, lessThan(130000));
      expect(GeoMath.formatMeters(meters, DistanceUnit.metric), endsWith('km'));
    });
  });
}
