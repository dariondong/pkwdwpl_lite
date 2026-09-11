import 'dart:math' as math;
// 只用 dart:ui 的 Offset/Size：不引入 flutter/material，保持 models 层干净，
// 也让这里避开 intl 与 dart:ui 的 TextDirection 同名问题。
import 'dart:ui' show Offset, Size;

/// 离线地图的经纬度范围。
///
/// 「离线」的意思是不请求任何在线瓦片：底图要么是随 App 打包的图片
/// （`assets/map/offline_map.png`），要么是用户在设置里指定的本地图片，
/// 都没有时退回程序绘制的经纬网格。
class MapBounds {
  const MapBounds({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;

  double get latitudeSpan => (maxLatitude - minLatitude).abs();
  double get longitudeSpan => (maxLongitude - minLongitude).abs();

  /// 宽高比（用于给画布定比例，避免地图被拉伸变形）。
  ///
  /// 用等距圆柱投影时，经度方向在纬度 φ 处要乘 cos(φ) 才是真实比例。
  double get aspectRatio {
    final double midLat = (minLatitude + maxLatitude) / 2;
    final double lonScale = math.max(0.05, math.cos(midLat * math.pi / 180));
    final double w = longitudeSpan * lonScale;
    final double h = latitudeSpan;
    if (w <= 0 || h <= 0) return 1;
    return w / h;
  }

  bool contains(double latitude, double longitude) =>
      latitude >= minLatitude &&
      latitude <= maxLatitude &&
      longitude >= minLongitude &&
      longitude <= maxLongitude;

  /// 向四周扩张一点边距，避免台站正好贴在画布边缘。
  MapBounds padded([double ratio = 0.15]) {
    final double latPad = math.max(latitudeSpan * ratio, 0.01);
    final double lonPad = math.max(longitudeSpan * ratio, 0.01);
    return MapBounds(
      minLatitude: minLatitude - latPad,
      maxLatitude: maxLatitude + latPad,
      minLongitude: minLongitude - lonPad,
      maxLongitude: maxLongitude + lonPad,
    );
  }

  /// 经纬度 → 画布像素（等距圆柱投影，屏幕 y 轴向下）。
  Offset project(double latitude, double longitude, Size size) {
    final double lonSpan = longitudeSpan == 0 ? 1 : longitudeSpan;
    final double latSpan = latitudeSpan == 0 ? 1 : latitudeSpan;
    final double x = (longitude - minLongitude) / lonSpan * size.width;
    final double y = (maxLatitude - latitude) / latSpan * size.height;
    return Offset(x, y);
  }

  /// 根据一组坐标自动生成范围（外加边距）。
  static MapBounds? fromPoints(
    Iterable<({double latitude, double longitude})> points, {
    double padRatio = 0.15,
    double minSpan = 0.02,
  }) {
    double? minLat, maxLat, minLon, maxLon;
    for (final ({double latitude, double longitude}) p in points) {
      minLat = minLat == null ? p.latitude : math.min(minLat, p.latitude);
      maxLat = maxLat == null ? p.latitude : math.max(maxLat, p.latitude);
      minLon = minLon == null ? p.longitude : math.min(minLon, p.longitude);
      maxLon = maxLon == null ? p.longitude : math.max(maxLon, p.longitude);
    }
    if (minLat == null || maxLat == null || minLon == null || maxLon == null) {
      return null;
    }
    // 单点或极窄范围时给一个最小跨度，否则画布会退化成一个像素。
    if ((maxLat - minLat).abs() < minSpan) {
      final double center = (maxLat + minLat) / 2;
      minLat = center - minSpan / 2;
      maxLat = center + minSpan / 2;
    }
    if ((maxLon - minLon).abs() < minSpan) {
      final double center = (maxLon + minLon) / 2;
      minLon = center - minSpan / 2;
      maxLon = center + minSpan / 2;
    }
    return MapBounds(
      minLatitude: minLat,
      maxLatitude: maxLat,
      minLongitude: minLon,
      maxLongitude: maxLon,
    ).padded(padRatio);
  }

  Map<String, double> toJson() => <String, double>{
        'minLat': minLatitude,
        'maxLat': maxLatitude,
        'minLon': minLongitude,
        'maxLon': maxLongitude,
      };

  static MapBounds? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double? read(String key) => (raw[key] as num?)?.toDouble();
    final double? minLat = read('minLat');
    final double? maxLat = read('maxLat');
    final double? minLon = read('minLon');
    final double? maxLon = read('maxLon');
    if (minLat == null || maxLat == null || minLon == null || maxLon == null) {
      return null;
    }
    return MapBounds(
      minLatitude: minLat,
      maxLatitude: maxLat,
      minLongitude: minLon,
      maxLongitude: maxLon,
    );
  }

  String get label => '${minLatitude.toStringAsFixed(2)},'
      '${minLongitude.toStringAsFixed(2)} → '
      '${maxLatitude.toStringAsFixed(2)},${maxLongitude.toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      other is MapBounds &&
      other.minLatitude == minLatitude &&
      other.maxLatitude == maxLatitude &&
      other.minLongitude == minLongitude &&
      other.maxLongitude == maxLongitude;

  @override
  int get hashCode =>
      Object.hash(minLatitude, maxLatitude, minLongitude, maxLongitude);
}

/// 一个待绘制的台站点位。
///
/// 只存可序列化的原始数据（图标存的是 `$PKWDWPL` 第 13 字段原文，
/// 例如 `/j`），具体的 PNG / Material 图标由绘制方决定，
/// 这样 models 层不用依赖 material。
class MapPoint {
  const MapPoint({
    required this.callsign,
    required this.latitude,
    required this.longitude,
    required this.iconRaw,
    this.courseDegrees,
    this.distanceMeters,
  });

  final String callsign;
  final double latitude;
  final double longitude;

  /// `$PKWDWPL` 第 13 字段原文，如 `/j`（地图上优先用官方图标包渲染）。
  final String iconRaw;

  final int? courseDegrees;
  final double? distanceMeters;
}
