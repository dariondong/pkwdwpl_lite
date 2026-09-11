import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/app_theme.dart';
import '../core/formats.dart';
import '../models/aprs_icon.dart';
import '../models/aprs_station.dart';

/// 台站列表项 —— **一个信标只用一行**（接收序号已按需求去掉）。
///
/// 固定列布局（各列位置固定）：
///
/// ```text
///  呼号 图标   方向   距离       时间
///  BG1UBU-9 🚗    ↑    52.0 km   10:23:53
/// ```
///
/// 设计约束：
/// * 所有字段**字号完全一致**（[AppTheme.listFontSize]，12）且不跟随系统字号
///   无限放大（[AppTheme.maxListTextScale] 封顶到 1.15）——
///   否则右侧的距离/时间会被挤没；
/// * 方向**只画箭头、不显示度数**；
/// * 设备图标放在**呼号右侧**；
/// * **绝不换行**：超长一律省略号，保证一行一个信标；
/// * 单击 → 详情页；双击 → 离线地图并居中。
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
    final AppSettings settings = context.watch<AppSettings>();

    final DistanceView distance = Formats.distance(
      station,
      unit: settings.distanceUnit,
      field11: settings.field11Meaning,
      referenceLatitude: settings.referenceLatitude,
      referenceLongitude: settings.referenceLongitude,
    );

    final TextStyle mainStyle = AppTheme.listText(context);
    final TextStyle subtleStyle = AppTheme.listText(
      context,
      color: AppTheme.subtleColor(context),
    );

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: AppTheme.clampTextScale(
        child: SizedBox(
          height: AppTheme.listRowHeight, // 单行固定行高
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                // ① 呼号 + 设备图标（图标在呼号右侧）
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          station.callsign,
                          style: mainStyle, // 不加粗、不放大，与其它列同一个字号
                          maxLines: AppTheme.listMaxLines,
                          softWrap: AppTheme.listSoftWrap,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 5),
                      AprsSymbolIcon(
                        icon: station.iconRaw,
                        size: AppTheme.listIconSize,
                        semanticLabel: station.iconLabel,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.rowGap),

                // ② 方向：只有箭头，不显示度数
                SizedBox(
                  width: AppTheme.colDir,
                  child: _DirectionArrow(courseDegrees: station.courseDegrees),
                ),
                const SizedBox(width: AppTheme.rowGap),

                // ③ 距离
                SizedBox(
                  width: AppTheme.colDistance,
                  child: Text(
                    distance.text ?? '--',
                    style: mainStyle,
                    textAlign: TextAlign.right,
                    maxLines: AppTheme.listMaxLines,
                    softWrap: AppTheme.listSoftWrap,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTheme.rowGap),

                // ④ 接收时间
                SizedBox(
                  width: AppTheme.colTime,
                  child: Text(
                    Formats.localTimeOnly(station.receivedAt),
                    style: subtleStyle,
                    textAlign: TextAlign.right,
                    maxLines: AppTheme.listMaxLines,
                    softWrap: AppTheme.listSoftWrap,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 数据有问题的行：一个很轻的提示图标（不占额外行）
                if (station.hasWarnings) ...<Widget>[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.error_outline,
                    size: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 方向指示：按航向旋转的箭头（**不显示度数**）。
///
/// 0° = 正北（屏幕上方）。没有航向时显示同样字号的 `--`。
class _DirectionArrow extends StatelessWidget {
  const _DirectionArrow({required this.courseDegrees});

  final int? courseDegrees;

  @override
  Widget build(BuildContext context) {
    final double? radians = Formats.courseRadians(courseDegrees);
    if (radians == null) {
      return Text(
        '--',
        textAlign: TextAlign.center,
        maxLines: AppTheme.listMaxLines,
        softWrap: AppTheme.listSoftWrap,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.listText(context, color: AppTheme.subtleColor(context)),
      );
    }
    return Transform.rotate(
      angle: radians,
      child: Icon(
        Icons.navigation,
        size: 16,
        color: AppTheme.green, // 绿色点缀
        semanticLabel: Formats.course(courseDegrees),
      ),
    );
  }
}
