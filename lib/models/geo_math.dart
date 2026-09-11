import 'dart:math' as math;

/// 距离单位（列表页可实时切换）。
enum DistanceUnit {
  /// 公制：m / km
  metric,

  /// 英制：ft / mi
  imperial;

  String get label => this == DistanceUnit.metric ? 'km' : 'mi';
}

/// 坐标换算、距离计算与单位格式化。
class GeoMath {
  const GeoMath._();

  /// WGS-84 平均地球半径（米）。
  static const double earthRadiusMeters = 6371008.8;

  static const double metersPerMile = 1609.344;
  static const double metersPerFoot = 0.3048;

  // ---------------------------------------------------------------------------
  // 度分 ↔ 十进制
  // ---------------------------------------------------------------------------

  /// NMEA 度分格式 → 十进制度。
  ///
  /// 例：`3954.98` → `39 + 54.98 / 60 = 39.91633`；
  ///     `11616.63` → `116 + 16.63 / 60 = 116.27717`。
  ///
  /// 取整数部分**最后两位**当「分」，其余当「度」，因此兼容 4 位（纬度 ddmm.mm）
  /// 与 5 位（经度 dddmm.mm），也兼容个别固件省略前导零的写法。
  /// 返回 `null` 表示格式非法。
  static double? dmToDecimal(String? dm, {String hemisphere = 'N'}) {
    if (dm == null) return null;
    final String cleaned = dm.trim().replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;

    final int dot = cleaned.indexOf('.');
    final String intPart = dot == -1 ? cleaned : cleaned.substring(0, dot);
    final String fracPart = dot == -1 ? '' : cleaned.substring(dot + 1);

    // 至少要有「度 + 两位分」，即 3 位数字。
    if (intPart.length < 3) return null;

    final String degStr = intPart.substring(0, intPart.length - 2);
    final String minStr = intPart.substring(intPart.length - 2);
    final int? degrees = int.tryParse(degStr);
    final double? minutes =
        double.tryParse(fracPart.isEmpty ? minStr : '$minStr.$fracPart');
    if (degrees == null || minutes == null) return null;
    if (minutes >= 60) return null; // 分不会 ≥ 60，说明语句有问题

    final double value = degrees + minutes / 60.0;
    final String hemi = hemisphere.toUpperCase();
    return (hemi == 'S' || hemi == 'W') ? -value : value;
  }

  /// 十进制度 → NMEA 度分字符串（模拟数据源 / 回写用）。
  ///
  /// 注意「分」的整数部分必须补足两位：`39.13°` → `3907.80`（不是 `397.80`）。
  /// 这个坑是端到端测试用真实数据揪出来的。
  static String decimalToDm(double value, {int minuteDecimals = 2}) {
    final double abs = value.abs();
    final int degrees = abs.floor();
    final double minutes = (abs - degrees) * 60.0;

    final String raw = minutes.toStringAsFixed(minuteDecimals);
    final int dot = raw.indexOf('.');
    final String minutePart = dot == -1
        ? raw.padLeft(2, '0')
        : '${raw.substring(0, dot).padLeft(2, '0')}${raw.substring(dot)}';

    final int width = abs >= 100 ? 3 : 2;
    return '${degrees.toString().padLeft(width, '0')}$minutePart';
  }

  // ---------------------------------------------------------------------------
  // 距离
  // ---------------------------------------------------------------------------

  /// 两点间大圆距离（米，Haversine）。
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final double dLat = _rad(lat2 - lat1);
    final double dLon = _rad(lon2 - lon1);
    final double rLat1 = _rad(lat1);
    final double rLat2 = _rad(lat2);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) * math.cos(rLat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
  }

  /// 米 → 人类可读文本（公制 m/km，英制 ft/mi）。
  static String formatMeters(double meters, DistanceUnit unit) {
    if (meters.isNaN || meters.isInfinite) return '--';
    if (unit == DistanceUnit.imperial) {
      final double feet = meters / metersPerFoot;
      if (feet < 1000) return '${feet.round()} ft';
      final double miles = meters / metersPerMile;
      return '${miles.toStringAsFixed(miles < 10 ? 2 : 1)} mi';
    }
    if (meters < 1000) return '${meters.round()} m';
    final double km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 2 : 1)} km';
  }

  /// 速度格式化（内部统一 km/h）。
  static String formatSpeedKph(double kph, DistanceUnit unit) {
    if (kph.isNaN || kph.isInfinite) return '--';
    if (unit == DistanceUnit.imperial) {
      return '${(kph / 1.609344).round()} mph';
    }
    return '${kph.round()} km/h';
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
