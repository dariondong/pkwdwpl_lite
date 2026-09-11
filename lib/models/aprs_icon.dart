import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'aprs_symbol_assets.dart';

/// APRS 符号图标：
///
/// * **优先**用 APRSLocus 项目带来的官方 PNG 图标包（`assets/aprs_syms/`，
///   38 个符号表 × 符号码 0x21~0x7E，3571 张），字形是国际通用的 APRS 符号；
/// * 图标包不可用（或图标字段不是官方 2 字符写法）时，**回退**到
///   [AprsIconMapper] 的 Material 图标（`/j`→汽车、`/`→房屋、未知→电台）。
///
/// 用法：
/// ```dart
/// AprsSymbolIcon(icon: station.iconRaw, size: 28)
/// ```
class AprsSymbolIcon extends StatelessWidget {
  const AprsSymbolIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.fallbackColor,
    this.semanticLabel,
  });

  /// `$PKWDWPL` 第 13 字段原文，如 `/j`。
  final String? icon;

  /// 边长（正方形）。
  final double size;

  /// 回退 Material 图标时的颜色（PNG 图标自带颜色，不受此影响）。
  final Color? fallbackColor;

  final String? semanticLabel;

  /// 图标包路径；不可用时为 null。
  static String? assetPathOf(String? icon) => AprsSymbolAssets.assetPathFor(icon);

  @override
  Widget build(BuildContext context) {
    final String? asset = assetPathOf(icon);
    final String label = semanticLabel ?? AprsIconMapper.labelFor(icon);

    if (asset == null) {
      return Icon(
        AprsIconMapper.iconFor(icon),
        size: size,
        color: fallbackColor ?? Theme.of(context).colorScheme.onPrimaryContainer,
        semanticLabel: label,
      );
    }

    return Semantics(
      label: label,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        // 万一某个 PNG 缺失/损坏，也不要让界面炸掉：回退 Material 图标。
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            Icon(
          AprsIconMapper.iconFor(icon),
          size: size,
          color:
              fallbackColor ?? Theme.of(context).colorScheme.onPrimaryContainer,
          semanticLabel: label,
        ),
      ),
    );
  }
}

/// 给 `CustomPainter`（离线地图）用的同步绘制助手。
///
/// `Image.asset` 是异步解码的，而 `CustomPainter.paint` 是同步的，
/// 所以这里提前把 PNG 解码成 [ui.Image] 缓存起来；
/// 某一帧还没解码完就返回 null（这一帧不画图标，下一帧补上）。
class AprsSymbolImageCache {
  AprsSymbolImageCache._();

  static final AprsSymbolImageCache instance = AprsSymbolImageCache._();

  final Map<String, ui.Image?> _decoded = <String, ui.Image?>{};
  final Set<String> _pending = <String>{};

  /// 取已解码的图标；未就绪返回 null。
  ui.Image? imageFor(String? icon) {
    final String? asset = AprsSymbolAssets.assetPathFor(icon);
    if (asset == null) return null;

    if (_decoded.containsKey(asset)) return _decoded[asset];
    if (_pending.add(asset)) {
      unawaited(
        _resolve(asset).then<void>(
          (ui.Image image) => _decoded[asset] = image,
          onError: (Object error, StackTrace stack) => _decoded[asset] = null,
        ),
      );
    }
    return null;
  }

  /// 预热（进入地图页时调一次，避免刚进去的几帧没有图标）。
  void preload(Iterable<String?> icons) {
    for (final String? icon in icons) {
      imageFor(icon);
    }
  }

  Future<ui.Image> _resolve(String asset) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    final ImageStream stream = AssetImage(asset).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!completer.isCompleted) completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stack) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}

/// Material 图标兜底表（当官方图标包不可用时使用）。
///
/// 需求约定：
///   * `/j` 与 `/>` → 汽车；
///   * `/`（只有符号表、没有符号码）→ `Icons.home`；
///   * 其余未知 → `Icons.radio` 兜底。
class AprsIconMapper {
  const AprsIconMapper._();

  /// 主符号表 `/` 的符号码 → Material 图标（参考 APRS101 第 5 章，只挑常用项）。
  static const Map<String, IconData> _primaryTable = <String, IconData>{
    '-': Icons.home, // House (QTH)
    '>': Icons.directions_car, // Car
    'j': Icons.directions_car, // Jeep / Car
    'k': Icons.local_shipping, // Truck
    'v': Icons.directions_bus, // Van
    'U': Icons.directions_bus, // Bus
    'u': Icons.directions_subway, // Subway
    'b': Icons.pedal_bike, // Bicycle
    '<': Icons.motorcycle, // Motorcycle
    'R': Icons.directions_run, // Runner
    'W': Icons.water_drop, // Weather station
    '_': Icons.cloud, // Weather station (WX)
    's': Icons.sailing, // Ship / boat
    'Y': Icons.sailing, // Yacht
    '^': Icons.flight, // Aircraft (large)
    "'": Icons.flight, // Aircraft (small)
    'O': Icons.flight, // Balloon
    'X': Icons.flight, // Helicopter
    '#': Icons.router, // Digipeater
    '&': Icons.settings_input_antenna, // Gateway / IGate
    'r': Icons.cell_tower, // Repeater / Antenna
    'i': Icons.dns, // TCP/IP network station
    'I': Icons.dns, // TCP/IP（固件大小写不一）
    'h': Icons.hotel, // Hospital（酒店）
    'H': Icons.local_hospital, // Hospital
    'f': Icons.local_fire_department, // Fire station
    'p': Icons.local_police, // Police
    'S': Icons.school, // School
    '+': Icons.emergency, // Red cross / EOC
    '!': Icons.emergency, // Emergency
    'E': Icons.emergency, // Emergency
    '/': Icons.wifi_tethering, // 兼容把 icon 写成 "//" 的情况
  };

  /// 副符号表 `\` 的符号码 → Material 图标（移动/便携类）。
  static const Map<String, IconData> _alternateTable = <String, IconData>{
    'j': Icons.directions_car,
    'k': Icons.local_shipping,
    '>': Icons.directions_car,
    'v': Icons.directions_bus,
    'b': Icons.pedal_bike,
    '<': Icons.motorcycle,
    'y': Icons.directions_walk, // 人员（便携）
    '-': Icons.home,
    'U': Icons.directions_bus,
    'S': Icons.directions_boat,
  };

  /// 未知图标兜底：电台图标。
  static const IconData fallbackIcon = Icons.radio;

  /// 根据原始图标字符串（如 `/j`）取 Material 图标。
  static IconData iconFor(String? rawIcon) {
    if (rawIcon == null || rawIcon.isEmpty) return fallbackIcon;

    final String table = rawIcon[0];
    final String? code = rawIcon.length >= 2 ? rawIcon[1] : null;

    // 需求：`/` 开头但拿不到符号码 → 房屋。
    if (code == null) {
      return table == '/' ? Icons.home : fallbackIcon;
    }

    final Map<String, IconData> dict =
        table == '\\' ? _alternateTable : _primaryTable;

    return dict[code] ?? _alternateTable[code] ?? _primaryTable[code] ?? fallbackIcon;
  }

  /// 中英通用的简短名称，用于 tooltip / 详情页。
  static String labelFor(String? rawIcon) {
    if (rawIcon == null || rawIcon.isEmpty) return 'Unknown';
    final String code = rawIcon.length >= 2 ? rawIcon[1] : '';
    const Map<String, String> labels = <String, String>{
      '-': 'House / 房屋',
      '>': 'Car / 汽车',
      'j': 'Jeep / 汽车',
      'k': 'Truck / 货车',
      'v': 'Van / 厢式车',
      'U': 'Bus / 巴士',
      'b': 'Bicycle / 自行车',
      '<': 'Motorcycle / 摩托',
      's': 'Ship / 船',
      '^': 'Aircraft / 飞机',
      '#': 'Digipeater / 中继',
      'r': 'Repeater / 中继台',
      '&': 'Gateway / 网关',
      'i': 'TCP/IP station / 网络台站',
      'I': 'TCP/IP station / 网络台站',
      'W': 'Weather / 气象',
      '_': 'Weather / 气象',
      'R': 'Runner / 行人',
    };
    return labels[code] ?? 'Symbol ${rawIcon[0]}$code';
  }
}
