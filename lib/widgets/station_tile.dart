import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/app_theme.dart';
import '../core/formats.dart';
import '../models/aprs_icon.dart';
import '../models/aprs_station.dart';

/// 台站列表项 —— **一个信标只用一行**。
///
/// 固定列布局（各列位置固定，右侧列宽固定 → 图标位置也就固定了）：
///
/// ```text
///  呼号         图标 方向   距离       时间
///  BG1UBU-9     🚗    ↑     50.0 km   10:23:53
/// ```
///
/// 设计约束：
/// * 所有字段**字号完全一致**，且只按用户在菜单里选的 [ListScale] 缩放
///   （不叠加系统字号 —— 否则列宽与字号错配，右侧字段会被挤掉）；
/// * **图标紧挨方向箭头**：图标与箭头之间只留 4px（tiget gap），
///   之前图标跟在呼号后面、方向在右侧，中间会空出一大截；
/// * 方向**只画箭头、不显示度数**；
/// * **绝不换行**：超长一律省略号；
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
    final ListMetrics m = AppTheme.metricsFor(settings.listScale);

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
      child: AppTheme.scaledForList(
        scale: settings.listScale,
        child: SizedBox(
          height: m.rowHeight, // 单行固定行高（随档位缩放）
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * m.scale),
            child: Row(
              // 全部列宽固定 ⇒ 各列位置完全固定，且整体靠左
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                // ① 呼号（Expanded 吃掉剩余空间；右侧列宽固定 ⇒ 图标位置也固定）
                Expanded(
                  child: Text(
                    station.callsign,
                    style: mainStyle, // 不加粗、不放大，与其它列同字号
                    maxLines: AppTheme.listMaxLines,
                    softWrap: AppTheme.listSoftWrap,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: m.gap),

                // ② 设备图标 —— 紧挨着方向箭头
                AprsSymbolIcon(
                  icon: station.iconRaw,
                  size: m.iconSize,
                  semanticLabel: station.iconLabel,
                ),
                SizedBox(width: m.tightGap),

                // ③ 方向：只有箭头，不显示度数
                SizedBox(
                  width: m.colDir,
                  child: _DirectionArrow(
                    courseDegrees: station.courseDegrees,
                    size: 15 * m.scale, // ≤ colDir，避免图标溢出挤到邻居
                  ),
                ),
                SizedBox(width: m.gap),

                // ④ 距离
                SizedBox(
                  width: m.colDistance,
                  child: Text(
                    distance.text ?? '--',
                    style: mainStyle,
                    textAlign: TextAlign.right,
                    maxLines: AppTheme.listMaxLines,
                    softWrap: AppTheme.listSoftWrap,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: m.gap),

                // ⑤ 接收时间（默认 HH:mm；可在菜单里切换是否显示秒）
                SizedBox(
                  width: m.colTime,
                  child: Text(
                    settings.showSeconds
                        ? Formats.localTimeOnly(station.receivedAt)
                        : Formats.localTimeShort(station.receivedAt),
                    style: subtleStyle,
                    textAlign: TextAlign.right,
                    maxLines: AppTheme.listMaxLines,
                    softWrap: AppTheme.listSoftWrap,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 数据有问题的行：一个很轻的提示图标（不占额外行）
                if (station.hasWarnings) ...<Widget>[
                  SizedBox(width: 4 * m.scale),
                  Icon(
                    Icons.error_outline,
                    size: 12 * m.scale,
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
  const _DirectionArrow({required this.courseDegrees, required this.size});

  final int? courseDegrees;
  final double size;

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
        size: size,
        color: AppTheme.green, // 绿色点缀
        semanticLabel: Formats.course(courseDegrees),
      ),
    );
  }
}
