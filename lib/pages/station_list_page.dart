import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/app_theme.dart';
import '../core/formats.dart';
import '../data/aprs_ingest.dart';
import '../data/station_store.dart';
import '../models/aprs_station.dart';
import '../models/geo_math.dart' show DistanceUnit;
import '../widgets/common.dart';
import '../widgets/station_tile.dart';
import 'about_page.dart';
import 'bluetooth_page.dart';
import 'offline_map_page.dart';
import 'station_detail_page.dart';

/// 主页面：APRS 站台列表（**一行一个信标**）。
///
/// 界面刻意做得极简（按需求）：
/// * 没有底部导航，所有入口收进右上角**「三个点」菜单**；
/// * 列表上方只有**一行**很轻的状态条（台站数 + 最后更新时间 + 连接状态点）；
/// * 列表项：`#序号 · 呼号 · 图标 · 方向箭头 · 距离 · 时间`，全部同一字号。
class StationListPage extends StatefulWidget {
  const StationListPage({super.key});

  @override
  State<StationListPage> createState() => _StationListPageState();
}

class _StationListPageState extends State<StationListPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 让「3 秒前」这类相对时间自动刷新。
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 页面跳转
  // ---------------------------------------------------------------------------

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  void _openMap(String callsign) => _push(OfflineMapPage(focusCallsign: callsign));

  Future<void> _confirmClear(StationStore store) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.tr('common.clear_all')),
        content: Text(context.tr('common.clear_confirm')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('common.ok')),
          ),
        ],
      ),
    );
    if (ok ?? false) store.clear();
  }

  @override
  Widget build(BuildContext context) {
    final StationStore store = context.watch<StationStore>();
    final List<AprsStation> stations = store.stations;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('stations.title')),
        actions: <Widget>[
          // 「三个点」——所有菜单都藏在这里，保持界面简洁
          PopupMenuButton<_MenuAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: context.tr('common.menu'),
            onSelected: (_MenuAction action) {
              switch (action) {
                case _MenuAction.connect:
                  _push(const BluetoothPage());
                case _MenuAction.map:
                  _openMap('');
                case _MenuAction.unit:
                  context.read<AppSettings>().toggleDistanceUnit();
                case _MenuAction.scale:
                  context.read<AppSettings>().cycleListScale();
                case _MenuAction.seconds:
                  context.read<AppSettings>().toggleShowSeconds();
                case _MenuAction.language:
                  _toggleLanguage();
                case _MenuAction.clear:
                  _confirmClear(store);
                case _MenuAction.about:
                  _push(const AboutPage());
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<_MenuAction>>[
              _menuItem(context, _MenuAction.connect, Icons.bluetooth,
                  context.tr('nav.connect')),
              _menuItem(context, _MenuAction.map, Icons.map_outlined,
                  context.tr('map.title')),
              const PopupMenuDivider(),
              _menuItem(
                context,
                _MenuAction.unit,
                Icons.straighten,
                '${context.tr('settings.distance_unit')}'
                    '：${context.read<AppSettings>().distanceUnit == DistanceUnit.metric ? 'KM' : 'MI'}',
              ),
              // 界面缩放：点一下切到下一档（小 → 标准 → 大 → 特大）
              _menuItem(
                context,
                _MenuAction.scale,
                Icons.zoom_in,
                '${context.tr('settings.list_scale')}：'
                    '${context.tr(context.read<AppSettings>().listScale.i18nKey)}',
              ),
              // 时间是否显示到秒（不要秒可给呼号腾出宽度）
              _menuItem(
                context,
                _MenuAction.seconds,
                Icons.timer_outlined,
                '${context.tr('settings.show_seconds')}：'
                    '${context.read<AppSettings>().showSeconds ? context.tr('common.enabled') : context.tr('common.disabled')}',
              ),
              // 语言：直接显示当前语言，点一下就切
              _menuItem(
                context,
                _MenuAction.language,
                Icons.language,
                '${context.tr('common.language')}：'
                    '${Localizations.localeOf(context).languageCode == 'zh' ? '中' : 'EN'}',
              ),
              if (store.count > 0)
                _menuItem(context, _MenuAction.clear, Icons.delete_sweep,
                    context.tr('common.clear_all')),
              const PopupMenuDivider(),
              _menuItem(context, _MenuAction.about, Icons.info_outline,
                  context.tr('about.title')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          const _StatusBar(),
          const Divider(height: 1),
          Expanded(
            child: stations.isEmpty
                ? EmptyHint(
                    icon: Icons.satellite_alt,
                    text: context.tr('stations.empty'),
                    action: FilledButton.icon(
                      onPressed: () => _push(const BluetoothPage()),
                      icon: const Icon(Icons.bluetooth_searching),
                      label: Text(context.tr('nav.connect')),
                    ),
                  )
                : ListView.separated(
                    // 列表本身也是最简：无分割线，靠行距区分
                    itemCount: stations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final AprsStation station = stations[index];
                      return StationTile(
                        key: ValueKey<String>(station.callsign),
                        station: station,
                        onTap: () => _push(StationDetailPage(station: station)),
                        // 双击 → 离线地图，居中该台站
                        onDoubleTap: () => _openMap(station.callsign),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _toggleLanguage() {
    final String code = Localizations.localeOf(context).languageCode;
    context.setLocale(
      code == 'zh' ? const Locale('en', 'US') : const Locale('zh', 'CN'),
    );
  }

  PopupMenuItem<_MenuAction> _menuItem(
    BuildContext context,
    _MenuAction action,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_MenuAction>(
      value: action,
      height: 44,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppTheme.green),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}

enum _MenuAction { connect, map, unit, scale, seconds, language, clear, about }

/// 列表上方**仅一行**的轻量状态条：连接状态点 + 台站数 + 最后更新时间
/// （有校验失败的语句才追加一项）。白底深色字，绿色只做圆点。
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final StationStore store = context.watch<StationStore>();
    final AprsIngest ingest = context.watch<AprsIngest>();
    final ThemeData theme = Theme.of(context);
    final AprsStation? latest = store.latest;

    final List<String> parts = <String>[
      context.tr('stations.count', args: <String>['${store.count}']),
      if (latest != null) Formats.relativeTime(context, latest.receivedAt),
      if (store.stats.checksumFailed > 0)
        '${context.tr('stations.bad_checksum')} ${store.stats.checksumFailed}',
    ];

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface, // 白底
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          // 连接状态：绿色实心点 / 灰色空心点
          Tooltip(
            message: ingest.isConnected
                ? context.tr('connect.state.connected')
                : context.tr('connect.state.ready'),
            child: Icon(
              ingest.isConnected ? Icons.circle : Icons.circle_outlined,
              size: 10,
              color: ingest.isConnected
                  ? AppTheme.green
                  : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join('   ·   '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
