import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/formats.dart';
import '../models/aprs_icon.dart';
import '../models/aprs_station.dart';
import '../models/geo_math.dart';
import '../data/station_store.dart';
import '../models/map_bounds.dart';
import '../widgets/common.dart';

/// 页面 5：离线地图。
///
/// 从列表页**双击**任意一条进入，会把该台站**居中显示**。
///
/// 「离线」= 不请求任何在线瓦片：
///   1. 若在设置里指定了本地底图图片路径 → 用 `Image.file` 画底图；
///   2. 否则若 App 内置了 `assets/map/offline_map.png` → 用它；
///   3. 都没有 → 程序绘制经纬网格 + 台站点位（照样能看相对位置与方向）。
///
/// 经纬范围：优先用设置里配置的 [MapBounds]，否则按「全部台站 + 本机参考点」
/// 自动生成，所以**开箱即用、不需要 GPS、不联网**。
class OfflineMapPage extends StatefulWidget {
  const OfflineMapPage({super.key, this.focusCallsign});

  /// 进入后要居中的呼号。
  final String? focusCallsign;

  @override
  State<OfflineMapPage> createState() => _OfflineMapPageState();
}

class _OfflineMapPageState extends State<OfflineMapPage> {
  static const double _canvasWidth = 2400;
  static const double _focusScale = 3.0;

  final TransformationController _controller = TransformationController();

  MapBounds? _bounds;
  Size _canvasSize = const Size(_canvasWidth, _canvasWidth);
  Size _viewport = Size.zero;
  String? _focused;
  bool _didCenterOnce = false;
  bool _bundledAssetAvailable = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusCallsign;
    _checkBundledAsset();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 检测 App 是否内置了离线底图（没有就退化成经纬网格）。
  Future<void> _checkBundledAsset() async {
    try {
      await rootBundle.load('assets/map/offline_map.png');
      if (!mounted) return;
      setState(() => _bundledAssetAvailable = true);
    } catch (_) {
      // 没有内置底图：保持 false，画布会退化成经纬网格。
    }
  }

  @override
  Widget build(BuildContext context) {
    final StationStore store = context.watch<StationStore>();
    final AppSettings settings = context.watch<AppSettings>();
    final MapData snapshot = MapData.from(store, settings);

    // 计算经纬范围：设置里的优先，否则按台站自动生成。
    final MapBounds bounds = snapshot.mapBounds ??
        MapBounds.fromPoints(<({double latitude, double longitude})>[
          for (final AprsStation station in snapshot.stations)
            (latitude: station.latitude, longitude: station.longitude),
          if (snapshot.referenceLatitude != null &&
              snapshot.referenceLongitude != null)
            (
              latitude: snapshot.referenceLatitude!,
              longitude: snapshot.referenceLongitude!,
            ),
        ]) ??
        // 完全没有数据时给一个中国范围的兜底视图（纯网格）。
        const MapBounds(
          minLatitude: 18,
          maxLatitude: 54,
          minLongitude: 73,
          maxLongitude: 135,
        );

    _bounds = bounds;
    _canvasSize = _resolveCanvasSize(bounds);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('map.title')),
        actions: <Widget>[
          IconButton(
            tooltip: context.tr('map.reset_view'),
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              _didCenterOnce = false;
              setState(() => _focused = widget.focusCallsign);
            },
          ),
          const LanguageButton(),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);

          // 预热官方符号图标（PNG 解码是异步的，先发起请求）。
          AprsSymbolImageCache.instance
              .preload(snapshot.points.map((MapPoint p) => p.iconRaw));

          // 首次布局后把目标台站居中（需求：双击跳转并居中）。
          if (!_didCenterOnce && _focused != null && !_viewport.isEmpty) {
            _didCenterOnce = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _centerOnCallsign(_focused!);
            });
          }

          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  minScale: 0.2,
                  maxScale: 20,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: SizedBox(
                    width: _canvasSize.width,
                    height: _canvasSize.height,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) =>
                          _handleTap(details.localPosition, snapshot),
                      child: _MapCanvas(
                        bounds: bounds,
                        points: snapshot.points,
                        focused: _focused,
                        referenceLatitude: snapshot.referenceLatitude,
                        referenceLongitude: snapshot.referenceLongitude,
                        baseImage: _baseImage(),
                        showGrid: !_hasBaseImage(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _InfoBar(
                  station: _focused == null ? null : store.byCallsign(_focused!),
                  bounds: bounds,
                  unit: snapshot.unit,
                  field11: snapshot.field11,
                  referenceLatitude: snapshot.referenceLatitude,
                  referenceLongitude: snapshot.referenceLongitude,
                  hasBaseImage: _hasBaseImage(),
                  stationCount: snapshot.points.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _hasBaseImage() => _resolveImagePath() != null || _bundledAssetAvailable;

  String? _resolveImagePath() {
    final String? path = context.read<AppSettings>().mapImagePath;
    if (path == null) return null;
    if (kIsWeb) return null;
    try {
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null; // 路径非法 / 无权限
    }
  }

  Widget? _baseImage() {
    final String? path = _resolveImagePath();
    if (path != null) {
      return Image.file(
        File(path),
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    if (_bundledAssetAvailable) {
      return Image.asset('assets/map/offline_map.png', fit: BoxFit.fill);
    }
    return null;
  }

  /// 画布尺寸保持与经纬范围一致的比例，避免地图被拉伸变形。
  Size _resolveCanvasSize(MapBounds bounds) {
    final double ratio = bounds.aspectRatio;
    final double width = _canvasWidth;
    double height = width / (ratio <= 0 ? 1 : ratio);
    height = height.clamp(400.0, 4000.0);
    return Size(width, height);
  }

  void _handleTap(Offset localPosition, MapData snapshot) {
    const double hitRadius = 40;
    AprsStation? best;
    double bestDistance = double.infinity;
    for (final AprsStation station in snapshot.stations) {
      final Offset p = _bounds!.project(station.latitude, station.longitude, _canvasSize);
      final double d = (p - localPosition).distance;
      if (d < hitRadius && d < bestDistance) {
        best = station;
        bestDistance = d;
      }
    }
    if (best == null) return;
    setState(() => _focused = best!.callsign);
    _centerOnCallsign(best.callsign);
  }

  /// 把某个呼号移到视口正中（需求里的「居中对其」）。
  void _centerOnCallsign(String callsign) {
    final AprsStation? station = context.read<StationStore>().byCallsign(callsign);
    if (station == null || _bounds == null || _viewport.isEmpty) return;

    final Offset target = _bounds!
        .project(station.latitude, station.longitude, _canvasSize);

    // 目标是：视口中心 = 缩放后的点位坐标
    // p' = T(center) · S(scale) · T(-target) · p
    // 用 translateByDouble/scaleByDouble（translate/scale 在 vector_math 2.4 已弃用）。
    _controller.value = Matrix4.identity()
      ..translateByDouble(_viewport.width / 2, _viewport.height / 2, 0, 1)
      ..scaleByDouble(_focusScale, _focusScale, 1, 1)
      ..translateByDouble(-target.dx, -target.dy, 0, 1);
  }
}

/// 地图页需要的一小组数据（一次 build 里算好，避免重复 watch）。
class MapData {
  const MapData({
    required this.stations,
    required this.points,
    required this.mapBounds,
    required this.unit,
    required this.field11,
    required this.referenceLatitude,
    required this.referenceLongitude,
  });

  final List<AprsStation> stations;
  final List<MapPoint> points;
  final MapBounds? mapBounds;
  final DistanceUnit unit;
  final Field11Meaning field11;
  final double? referenceLatitude;
  final double? referenceLongitude;

  factory MapData.from(StationStore store, AppSettings settings) {
    final List<AprsStation> stations = store.stations;
    return MapData(
      stations: stations,
      points: <MapPoint>[
        for (final AprsStation station in stations)
          MapPoint(
            callsign: station.callsign,
            latitude: station.latitude,
            longitude: station.longitude,
            iconRaw: station.iconRaw,
            courseDegrees: station.courseDegrees,
            distanceMeters: station.distanceMeters?.toDouble(),
          ),
      ],
      mapBounds: settings.mapBounds,
      unit: settings.distanceUnit,
      field11: settings.field11Meaning,
      referenceLatitude: settings.referenceLatitude,
      referenceLongitude: settings.referenceLongitude,
    );
  }
}

// -----------------------------------------------------------------------------
// 画布
// -----------------------------------------------------------------------------

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({
    required this.bounds,
    required this.points,
    required this.focused,
    required this.referenceLatitude,
    required this.referenceLongitude,
    required this.baseImage,
    required this.showGrid,
  });

  final MapBounds bounds;
  final List<MapPoint> points;
  final String? focused;
  final double? referenceLatitude;
  final double? referenceLongitude;
  final Widget? baseImage;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (baseImage != null)
          Positioned.fill(child: baseImage!)
        else
          Positioned.fill(
            child: ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: _MapPainter(
              bounds: bounds,
              points: points,
              focused: focused,
              referenceLatitude: referenceLatitude,
              referenceLongitude: referenceLongitude,
              gridColor: theme.colorScheme.outlineVariant,
              pointColor: theme.colorScheme.primary,
              pointLabelColor: theme.colorScheme.onSurface,
              focusColor: theme.colorScheme.error,
              referenceColor: theme.colorScheme.tertiary,
              labelBackground: theme.colorScheme.surface.withValues(alpha: 0.8),
              showGrid: showGrid,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.bounds,
    required this.points,
    required this.focused,
    required this.referenceLatitude,
    required this.referenceLongitude,
    required this.gridColor,
    required this.pointColor,
    required this.pointLabelColor,
    required this.focusColor,
    required this.referenceColor,
    required this.labelBackground,
    required this.showGrid,
  });

  final MapBounds bounds;
  final List<MapPoint> points;
  final String? focused;
  final double? referenceLatitude;
  final double? referenceLongitude;
  final Color gridColor;
  final Color pointColor;
  final Color pointLabelColor;
  final Color focusColor;
  final Color referenceColor;
  final Color labelBackground;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) _paintGrid(canvas, size);
    _paintScaleBar(canvas, size);
    _paintPoints(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    // 经纬网格：跨度越大，网格越粗（保持 6~12 条线）。
    final double latStep = _niceStep(bounds.latitudeSpan);
    final double lonStep = _niceStep(bounds.longitudeSpan);

    for (double lat = (bounds.minLatitude / latStep).ceil() * latStep;
        lat <= bounds.maxLatitude;
        lat += latStep) {
      final double y = bounds.project(lat, bounds.minLongitude, size).dy;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      _label(canvas, Offset(6, y + 2), '${lat.toStringAsFixed(1)}°N');
    }
    for (double lon = (bounds.minLongitude / lonStep).ceil() * lonStep;
        lon <= bounds.maxLongitude;
        lon += lonStep) {
      final double x = bounds.project(bounds.minLatitude, lon, size).dx;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      _label(canvas, Offset(x + 4, size.height - 30), '${lon.toStringAsFixed(1)}°E');
    }
  }

  double _niceStep(double span) {
    if (span <= 0) return 1;
    const List<double> candidates = <double>[
      0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 45,
    ];
    for (final double c in candidates) {
      if (span / c <= 12) return c;
    }
    return candidates.last;
  }

  void _paintScaleBar(Canvas canvas, Size size) {
    final double metersPerPixel =
        (bounds.latitudeSpan * 111320.0) / (size.height == 0 ? 1 : size.height);
    if (metersPerPixel <= 0) return;

    // 找一个「好看」的比例尺长度（不超过画布宽度 1/4）。
    const List<double> niceMeters = <double>[
      100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000,
    ];
    double chosen = niceMeters.first;
    for (final double m in niceMeters) {
      if (m / metersPerPixel <= size.width / 4) chosen = m;
    }
    final double barPixels = chosen / metersPerPixel;

    const double x = 20;
    final double y = 44;
    final Paint paint = Paint()
      ..color = pointColor
      ..strokeWidth = 4;
    canvas.drawLine(Offset(x, y), Offset(x + barPixels, y), paint);

    _label(
      canvas,
      Offset(x, y - 20),
      chosen >= 1000 ? '${(chosen / 1000).round()} km' : '${chosen.round()} m',
    );
  }

  void _paintPoints(Canvas canvas, Size size) {
    // 本机参考点
    if (referenceLatitude != null && referenceLongitude != null) {
      final Offset p = bounds.project(referenceLatitude!, referenceLongitude!, size);
      canvas.drawCircle(
        p,
        7,
        Paint()..color = referenceColor,
      );
      canvas.drawCircle(
        p,
        14,
        Paint()
          ..color = referenceColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _label(canvas, p + const Offset(16, -8), 'ME');
    }

    for (final MapPoint point in points) {
      final Offset p = bounds.project(point.latitude, point.longitude, size);
      final bool isFocused = focused != null && focused == point.callsign;

      // ① 航向指示（有航向时画一小段箭头，先画所以图标会盖在上面）
      if (point.courseDegrees != null) {
        final double radians = point.courseDegrees! * math.pi / 180.0;
        final Offset tip = p +
            Offset(
              math.sin(radians) * (isFocused ? 40 : 28),
              -math.cos(radians) * (isFocused ? 40 : 28),
            );
        canvas.drawLine(
          p,
          tip,
          Paint()
            ..color = isFocused ? focusColor : pointColor.withValues(alpha: 0.75)
            ..strokeWidth = isFocused ? 3.5 : 2.5,
        );
      }

      // ② 官方 APRS 符号 PNG（来自图标包）；没解码好/不可用时退化成圆点
      final double side = isFocused ? 46 : 34;
      final ui.Image? symbol = AprsSymbolImageCache.instance.imageFor(point.iconRaw);
      if (symbol != null) {
        canvas.drawImageRect(
          symbol,
          Rect.fromLTWH(0, 0, symbol.width.toDouble(), symbol.height.toDouble()),
          Rect.fromCenter(center: p, width: side, height: side),
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else {
        canvas.drawCircle(
          p,
          isFocused ? 9 : 7,
          Paint()..color = isFocused ? focusColor : pointColor,
        );
        canvas.drawCircle(
          p,
          isFocused ? 9 : 7,
          Paint()
            ..color = labelBackground
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      // ③ 选中态光环
      if (isFocused) {
        canvas.drawCircle(
          p,
          side / 2 + 6,
          Paint()
            ..color = focusColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        canvas.drawCircle(
          p,
          side / 2 + 14,
          Paint()
            ..color = focusColor.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      _label(
        canvas,
        p + Offset(-8, side / 2 + 4),
        point.callsign,
        bold: isFocused,
      );
    }
  }

  void _label(Canvas canvas, Offset offset, String text, {bool bold = false}) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: bold ? 26 : 20,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: pointLabelColor,
          backgroundColor: labelBackground,
        ),
      ),
      // 显式用 dart:ui 的 TextDirection：easy_localization 会间接带来 intl 的
      // 同名类型（它的枚举是 LTR/RTL），不限定前缀会解析错。
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.bounds != bounds ||
      old.signature != signature ||
      old.focused != focused ||
      old.referenceLatitude != referenceLatitude ||
      old.referenceLongitude != referenceLongitude ||
      old.showGrid != showGrid;

  /// 点位「指纹」：位置、图标、航向任一变化都重画。
  int get signature => Object.hashAll(<Object>[
        for (final MapPoint p in points)
          Object.hash(p.callsign, p.latitude, p.longitude, p.iconRaw, p.courseDegrees),
      ]);
}

// -----------------------------------------------------------------------------
// 底部信息条
// -----------------------------------------------------------------------------

class _InfoBar extends StatelessWidget {
  const _InfoBar({
    required this.station,
    required this.bounds,
    required this.unit,
    required this.field11,
    required this.referenceLatitude,
    required this.referenceLongitude,
    required this.hasBaseImage,
    required this.stationCount,
  });

  final AprsStation? station;
  final MapBounds bounds;
  final DistanceUnit unit;
  final Field11Meaning field11;
  final double? referenceLatitude;
  final double? referenceLongitude;
  final bool hasBaseImage;
  final int stationCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AprsStation? data = station;
    final DistanceView distance = data == null
        ? const DistanceView(null, DistanceSource.none)
        : Formats.distance(
            data,
            unit: unit,
            field11: field11,
            referenceLatitude: referenceLatitude,
            referenceLongitude: referenceLongitude,
          );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(data?.icon ?? Icons.public, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data == null
                        ? context.tr('map.center_on_hint')
                        : '${data.callsign}   ·   ${Formats.coordinates(data)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (data != null)
                  Text(
                    distance.text ?? '--',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                TagChip(
                  context.tr('map.points', args: <String>['$stationCount']),
                  icon: Icons.place,
                ),
                TagChip(
                  bounds.label,
                  icon: Icons.crop_free,
                  color: theme.colorScheme.secondary,
                ),
                TagChip(
                  hasBaseImage
                      ? context.tr('map.base_image_on')
                      : context.tr('map.base_image_off'),
                  icon: hasBaseImage ? Icons.image : Icons.grid_4x4,
                  color: hasBaseImage
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                if (data != null && data.courseDegrees != null)
                  TagChip(
                    Formats.course(data.courseDegrees),
                    icon: Icons.navigation,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('map.tap_hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
