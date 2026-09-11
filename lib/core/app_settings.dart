import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/geo_math.dart';
import '../models/map_bounds.dart';

/// 字段 11（`000050`）的含义。
///
/// 不同 Kenwood 机型/固件在这一位上输出的是**距离**或**速度**（详见 docs/PROTOCOL.md），
/// 所以让用户按自己的电台实测结果选，而不是写死。
enum Field11Meaning {
  /// 距离，单位千米（实测 `000050` 对应几十公里，最可能是 km）
  distanceKm,

  /// 距离，单位米
  distanceMeters,

  /// 速度，单位 km/h
  speedKph;

  String get i18nKey => switch (this) {
        Field11Meaning.distanceKm => 'settings.field11_distance_km',
        Field11Meaning.distanceMeters => 'settings.field11_distance_m',
        Field11Meaning.speedKph => 'settings.field11_speed_kph',
      };
}

/// 列表筛选。
enum StationFilter {
  /// 全部
  all,

  /// 只看 A（有效）
  valid,

  /// 只看有问题的（字段数异常 / 呼号可疑 / 校验不符）
  flagged;

  String get i18nKey => switch (this) {
        StationFilter.all => 'stations.filter_all',
        StationFilter.valid => 'stations.filter_valid',
        StationFilter.flagged => 'stations.filter_flagged',
      };
}

/// 全局设置（持久化到 SharedPreferences）。
///
/// * [strictChecksum]：严格 NMEA 校验（需求 3 的默认行为）。
/// * [demoMode]：无硬件时的模拟数据源，方便在 CI 产物/真机上验证 UI。
/// * [distanceUnit]：列表页距离单位（KM / MI 可切换）。
/// * [field11Meaning]：字段 11 的语义（距离 km/m 或速度 km/h）。
/// * [referenceLatitude] / [referenceLongitude]：本机参考坐标。
///   **本 App 不申请定位权限、不打开 GPS**（省电）：这两个值要么用户手填，
///   要么由你现有的定位模块调用 [setReferencePosition] 写入。
/// * [mapImagePath] / [mapBounds]：离线地图底图。不配置也能用（程序绘制经纬网格）。
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static const String _kStrictChecksum = 'strict_checksum';
  static const String _kDemoMode = 'demo_mode';
  static const String _kRefLat = 'reference_latitude';
  static const String _kRefLon = 'reference_longitude';
  static const String _kDistanceUnit = 'distance_unit';
  static const String _kField11 = 'field11_meaning';
  static const String _kMapImagePath = 'map_image_path';
  static const String _kMapMinLat = 'map_min_lat';
  static const String _kMapMaxLat = 'map_max_lat';
  static const String _kMapMinLon = 'map_min_lon';
  static const String _kMapMaxLon = 'map_max_lon';

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  /// 校验和错误时是否丢弃语句（默认丢弃）。
  bool get strictChecksum => _prefs.getBool(_kStrictChecksum) ?? true;

  /// 演示模式（模拟数据源）。
  bool get demoMode => _prefs.getBool(_kDemoMode) ?? false;

  /// 距离单位（默认公制 KM）。
  DistanceUnit get distanceUnit =>
      _prefs.getString(_kDistanceUnit) == DistanceUnit.imperial.name
          ? DistanceUnit.imperial
          : DistanceUnit.metric;

  /// 字段 11 的含义（默认按千米距离）。
  Field11Meaning get field11Meaning {
    final String? raw = _prefs.getString(_kField11);
    for (final Field11Meaning value in Field11Meaning.values) {
      if (value.name == raw) return value;
    }
    return Field11Meaning.distanceKm;
  }

  double? get referenceLatitude => _prefs.getDouble(_kRefLat);

  double? get referenceLongitude => _prefs.getDouble(_kRefLon);

  bool get hasReferencePosition =>
      referenceLatitude != null && referenceLongitude != null;

  /// 离线地图底图的本地绝对路径（可选）。
  String? get mapImagePath {
    final String? path = _prefs.getString(_kMapImagePath);
    return (path == null || path.isEmpty) ? null : path;
  }

  /// 离线地图的经纬范围（可选；不设置就按台站范围自动生成）。
  MapBounds? get mapBounds {
    final double? minLat = _prefs.getDouble(_kMapMinLat);
    final double? maxLat = _prefs.getDouble(_kMapMaxLat);
    final double? minLon = _prefs.getDouble(_kMapMinLon);
    final double? maxLon = _prefs.getDouble(_kMapMaxLon);
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

  Future<void> setStrictChecksum(bool value) async {
    await _prefs.setBool(_kStrictChecksum, value);
    notifyListeners();
  }

  Future<void> setDemoMode(bool value) async {
    await _prefs.setBool(_kDemoMode, value);
    notifyListeners();
  }

  Future<void> setDistanceUnit(DistanceUnit value) async {
    await _prefs.setString(_kDistanceUnit, value.name);
    notifyListeners();
  }

  /// 在 KM / MI 之间切换（列表页右上角按钮用）。
  Future<void> toggleDistanceUnit() => setDistanceUnit(
        distanceUnit == DistanceUnit.metric
            ? DistanceUnit.imperial
            : DistanceUnit.metric,
      );

  Future<void> setField11Meaning(Field11Meaning value) async {
    await _prefs.setString(_kField11, value.name);
    notifyListeners();
  }

  /// 写入本机参考坐标（可在你的定位逻辑里调用；传 null 清除）。
  ///
  /// 本 App 自己**不会**去开 GPS —— 省电，且避免和你的定位方案冲突。
  Future<void> setReferencePosition(double? latitude, double? longitude) async {
    if (latitude == null || longitude == null) {
      await _prefs.remove(_kRefLat);
      await _prefs.remove(_kRefLon);
    } else {
      await _prefs.setDouble(_kRefLat, latitude);
      await _prefs.setDouble(_kRefLon, longitude);
    }
    notifyListeners();
  }

  Future<void> setMapImagePath(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_kMapImagePath);
    } else {
      await _prefs.setString(_kMapImagePath, path.trim());
    }
    notifyListeners();
  }

  Future<void> setMapBounds(MapBounds? bounds) async {
    if (bounds == null) {
      await _prefs.remove(_kMapMinLat);
      await _prefs.remove(_kMapMaxLat);
      await _prefs.remove(_kMapMinLon);
      await _prefs.remove(_kMapMaxLon);
    } else {
      await _prefs.setDouble(_kMapMinLat, bounds.minLatitude);
      await _prefs.setDouble(_kMapMaxLat, bounds.maxLatitude);
      await _prefs.setDouble(_kMapMinLon, bounds.minLongitude);
      await _prefs.setDouble(_kMapMaxLon, bounds.maxLongitude);
    }
    notifyListeners();
  }
}
