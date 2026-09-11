import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/formats.dart';
import '../data/aprs_ingest.dart';
import '../data/station_store.dart';
import '../models/aprs_station.dart';
import '../models/geo_math.dart';
import '../widgets/common.dart';
import '../widgets/station_tile.dart';
import 'offline_map_page.dart';
import 'station_detail_page.dart';

/// 页面 2：APRS 站台列表页（主页面）。
///
/// * 数据来自 [StationStore]（呼号为 Key 的 Map，新数据覆盖并置顶）；
/// * 列表格式：**序号 · 图标 · 呼号 · 方向 · 距离 · 接收时间**；
/// * 距离单位 KM/MI 一键切换；
/// * 单击 → 详情页；**双击 → 离线地图并居中**。
class StationListPage extends StatefulWidget {
  const StationListPage({super.key, required this.onOpenConnect});

  /// 空列表时引导用户去连接页。
  final VoidCallback onOpenConnect;

  @override
  State<StationListPage> createState() => _StationListPageState();
}

class _StationListPageState extends State<StationListPage> {
  Timer? _ticker;
  StationFilter _filter = StationFilter.all;

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

  void _openMap(String callsign) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfflineMapPage(focusCallsign: callsign),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StationStore store = context.watch<StationStore>();
    final AprsIngest ingest = context.watch<AprsIngest>();
    final AppSettings settings = context.watch<AppSettings>();
    final List<AprsStation> stations = store.filteredStations(_filter);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('stations.title')),
        actions: <Widget>[
          // 距离单位切换（KM / MI）
          TextButton(
            onPressed: settings.toggleDistanceUnit,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: const Size(52, 36),
            ),
            child: Text(
              settings.distanceUnit == DistanceUnit.metric ? 'KM' : 'MI',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const LanguageButton(),
          IconButton(
            tooltip: ingest.isConnected
                ? context.tr('connect.state.connected')
                : context.tr('connect.title'),
            icon: Icon(
              ingest.isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            ),
            onPressed: widget.onOpenConnect,
          ),
          // 收进菜单，避免窄屏上 AppBar 放不下（标题被挤没或溢出）。
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case 'map':
                  _openMap('');
                case 'clear':
                  _confirmClear(context, store);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'map',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.map_outlined),
                  title: Text(context.tr('map.title')),
                ),
              ),
              if (store.count > 0)
                PopupMenuItem<String>(
                  value: 'clear',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_sweep),
                    title: Text(context.tr('common.clear_all')),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _StatsBar(store: store, filter: _filter, onFilter: (StationFilter f) {
            setState(() => _filter = f);
          }),
          const Divider(height: 1),
          Expanded(
            child: stations.isEmpty
                ? EmptyHint(
                    icon: Icons.satellite_alt,
                    text: store.isEmpty
                        ? context.tr('stations.empty')
                        : context.tr('stations.empty_filtered'),
                    action: store.isEmpty
                        ? FilledButton.icon(
                            onPressed: widget.onOpenConnect,
                            icon: const Icon(Icons.bluetooth_searching),
                            label: Text(context.tr('connect.title')),
                          )
                        : null,
                  )
                : ListView.separated(
                    itemCount: stations.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 62),
                    itemBuilder: (BuildContext context, int index) {
                      final AprsStation station = stations[index];
                      return StationTile(
                        key: ValueKey<String>(station.callsign),
                        station: station,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StationDetailPage(station: station),
                          ),
                        ),
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

  Future<void> _confirmClear(BuildContext context, StationStore store) async {
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
}

/// 顶部统计条 + 筛选（现场判断链路是否正常非常有用）。
class _StatsBar extends StatelessWidget {
  const _StatsBar({
    required this.store,
    required this.filter,
    required this.onFilter,
  });

  final StationStore store;
  final StationFilter filter;
  final ValueChanged<StationFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AprsStation? latest = store.latest;

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TagChip(
                context.tr('stations.count', args: <String>['${store.count}']),
                icon: Icons.radar,
                color: theme.colorScheme.primary,
              ),
              TagChip(
                '${context.tr('stations.good')} ${store.stats.accepted}',
                icon: Icons.check_circle,
                color: Colors.green.shade700,
              ),
              if (store.stats.checksumFailed > 0)
                TagChip(
                  '${context.tr('stations.bad_checksum')} ${store.stats.checksumFailed}',
                  icon: Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
              if (store.stats.malformed > 0)
                TagChip(
                  '${context.tr('stations.bad_format')} ${store.stats.malformed}',
                  icon: Icons.warning_amber,
                  color: Colors.orange.shade800,
                ),
              if (store.stats.flagged > 0)
                TagChip(
                  '${context.tr('stations.flagged')} ${store.stats.flagged}',
                  icon: Icons.flag_outlined,
                  color: Colors.orange.shade900,
                ),
              if (latest != null)
                TagChip(
                  Formats.relativeTime(context, latest.receivedAt),
                  icon: Icons.schedule,
                  color: theme.colorScheme.secondary,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              for (final StationFilter value in StationFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      context.tr(value.i18nKey),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: filter == value,
                    onSelected: (_) => onFilter(value),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.tr('stations.double_tap_hint'),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
