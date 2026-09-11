import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/formats.dart';
import '../models/aprs_icon.dart';
import '../models/aprs_station.dart';

/// 台站列表项。
///
/// 列表格式按需求定制：
/// **接收序号 · 图标 · 呼号 · 方向 · 距离(单位可切换) · 接收时间**
///
/// * 单击 → 台站详情页；
/// * **双击 → 离线地图（并把该台站居中）**。
class StationTile extends StatelessWidget {
  const StationTile({
    super.key,
    required this.station,
    required this.onTap,
    required this.onDoubleTap,
  });

  final AprsStation station;
  final VoidCallback onTap;

  /// 双击：跳转离线地图并居中。
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSettings settings = context.watch<AppSettings>();

    final DistanceView distance = Formats.distance(
      station,
      unit: settings.distanceUnit,
      field11: settings.field11Meaning,
      referenceLatitude: settings.referenceLatitude,
      referenceLongitude: settings.referenceLongitude,
    );

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: <Widget>[
            // ① 接收序号
            SizedBox(
              width: 34,
              child: Text(
                '#${station.receiveSeq}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 4),

            // ② APRS 图标（官方图标包优先，缺失时回退 Material 图标）
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: AprsSymbolIcon(
                icon: station.iconRaw,
                size: 26,
                semanticLabel: station.iconLabel,
              ),
            ),
            const SizedBox(width: 12),

            // ③ 呼号 + ④ 距离 + ⑥ 接收时间
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          station.callsign,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (station.statusValid == false)
                        _MiniTag(
                          text: context.tr('stations.tag_invalid'),
                          color: theme.colorScheme.outline,
                        ),
                      if (station.hasWarnings)
                        _MiniTag(
                          text: context.tr('stations.tag_flagged'),
                          color: theme.colorScheme.error,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      '${distance.text ?? '--'}'
                          '${distance.source == DistanceSource.estimated ? ' *' : ''}',
                      Formats.localTimeOnly(station.receivedAt),
                    ].join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),

            // ⑤ 方向（航向箭头 + 度数）
            _DirectionBadge(
              courseDegrees: station.courseDegrees,
              color: theme.colorScheme.primary,
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

/// 方向：把箭头按航向旋转（无航向时显示 `--`）。
class _DirectionBadge extends StatelessWidget {
  const _DirectionBadge({required this.courseDegrees, required this.color});

  final int? courseDegrees;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double? radians = Formats.courseRadians(courseDegrees);
    return SizedBox(
      width: 46,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (radians == null)
            Text(
              '--',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Transform.rotate(
              angle: radians, // 0° = 正北（屏幕上方）
              child: Icon(Icons.navigation, size: 20, color: color),
            ),
          Text(
            courseDegrees == null ? '' : '$courseDegrees°',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
