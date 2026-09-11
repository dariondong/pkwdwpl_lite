// DateFormat 由 easy_localization 间接导出（pubspec 里仍显式依赖 intl）。
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/aprs_station.dart';
import '../models/geo_math.dart';
import 'app_settings.dart';

/// 距离数值的来源（列表/详情页会标注，避免误导）。
enum DistanceSource {
  /// 用本机参考坐标算的大圆距离（最可信）
  estimated,

  /// 报文第 11 字段（单位按设置解释为距离）
  reportedDistance,

  /// 报文第 11 字段被解释为速度
  reportedSpeed,

  /// 没有任何可用的距离信息
  none,
}

/// 距离展示结果。
class DistanceView {
  const DistanceView(this.text, this.source);

  final String? text;
  final DistanceSource source;

  bool get hasValue => text != null;
}

/// 界面用的格式化工具（纯展示逻辑，解析逻辑全在 models/ 里）。
class Formats {
  const Formats._();

  /// 十进制经纬度：`39.97583°N`、`116.42833°E`。
  static String latLon(double value, {required bool isLatitude}) {
    final String hemi = isLatitude
        ? (value >= 0 ? 'N' : 'S')
        : (value >= 0 ? 'E' : 'W');
    return '${value.abs().toStringAsFixed(5)}°$hemi';
  }

  /// 纬度 + 经度一行展示。
  static String coordinates(AprsStation station) =>
      '${latLon(station.latitude, isLatitude: true)}  '
      '${latLon(station.longitude, isLatitude: false)}';

  /// 距离文案。
  ///
  /// 优先级：
  ///   1. 有本机参考坐标 → Haversine 真实距离（[DistanceSource.estimated]）；
  ///   2. 否则看报文第 11 字段，按 [Field11Meaning] 解释
  ///      （距离 km / 距离 m / 速度 km/h）。
  ///
  /// **不需要 GPS**：没有参考坐标时照样能用（显示报文里的值）。
  static DistanceView distance(
    AprsStation station, {
    required DistanceUnit unit,
    required Field11Meaning field11,
    double? referenceLatitude,
    double? referenceLongitude,
  }) {
    if (referenceLatitude != null && referenceLongitude != null) {
      final double meters = GeoMath.haversineMeters(
        referenceLatitude,
        referenceLongitude,
        station.latitude,
        station.longitude,
      );
      return DistanceView(
        GeoMath.formatMeters(meters, unit),
        DistanceSource.estimated,
      );
    }

    final int? raw = station.distanceMeters;
    if (raw == null) return const DistanceView(null, DistanceSource.none);

    switch (field11) {
      case Field11Meaning.distanceKm:
        return DistanceView(
          GeoMath.formatMeters(raw * 1000.0, unit),
          DistanceSource.reportedDistance,
        );
      case Field11Meaning.distanceMeters:
        return DistanceView(
          GeoMath.formatMeters(raw.toDouble(), unit),
          DistanceSource.reportedDistance,
        );
      case Field11Meaning.speedKph:
        return DistanceView(
          GeoMath.formatSpeedKph(raw.toDouble(), unit),
          DistanceSource.reportedSpeed,
        );
    }
  }

  /// 第 11 字段的原始文本（详情页展示，保留前导零）。
  static String rawField11(AprsStation station) =>
      station.distanceRaw.isEmpty ? '--' : station.distanceRaw;

  /// 航向（度）。
  static String course(int? degrees) => degrees == null ? '--' : '$degrees°';

  /// 航向的弧度值（用于旋转方向箭头）；无航向返回 null。
  static double? courseRadians(int? degrees) =>
      degrees == null ? null : degrees * 3.1415926535897932 / 180.0;

  /// 「3 秒前 / 5 分钟前」这类相对时间。
  static String relativeTime(BuildContext context, DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inSeconds < 3) return context.tr('stations.already');
    if (diff.inSeconds < 60) {
      return context.tr('stations.seconds_ago', args: <String>['${diff.inSeconds}']);
    }
    if (diff.inMinutes < 60) {
      return context.tr('stations.minutes_ago', args: <String>['${diff.inMinutes}']);
    }
    if (diff.inHours < 24) {
      return context.tr('stations.hours_ago', args: <String>['${diff.inHours}']);
    }
    return DateFormat('MM-dd HH:mm').format(time);
  }

  /// 接收时刻（本地时区，精确到秒）。
  static String localDateTime(DateTime time) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(time);

  /// 接收时刻只保留时分秒（列表页空间紧张）。
  static String localTimeOnly(DateTime time) =>
      DateFormat('HH:mm:ss').format(time);

  /// UTC 时间 → 本地时间（精确到秒）。
  static String localDateTimeOfUtc(DateTime utc) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(utc.toLocal());

  /// `290625` + `102339` → `290625 102339`。
  static String rawUtcStamp(AprsStation station) =>
      '${station.utcDate} ${station.utcTime}';

  /// 海拔。
  static String altitude(int? meters) => meters == null ? '--' : '$meters m';

  /// 状态文本：A / V / 其它。
  static String statusLabel(BuildContext context, AprsStation station) {
    if (station.statusValid == null) {
      return station.statusRaw.isEmpty
          ? context.tr('common.unknown')
          : '${context.tr('common.unknown')} (${station.statusRaw})';
    }
    return station.statusValid!
        ? context.tr('detail.status_valid')
        : context.tr('detail.status_invalid');
  }
}
