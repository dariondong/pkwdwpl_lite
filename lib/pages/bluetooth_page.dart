import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/l10n.dart';
import '../data/aprs_ingest.dart';
import '../models/geo_math.dart';
import '../services/bluetooth_service.dart';
import '../widgets/common.dart';

/// 页面 1：蓝牙连接页。
///
/// * 列出已配对设备，点击即连接；
/// * 顶部实时显示连接状态；
/// * 提供「演示模式」与「严格校验」开关，以及本机参考坐标（用于算距离）。
class BluetoothPage extends StatelessWidget {
  const BluetoothPage({super.key, required this.onOpenStations});

  /// 连接成功后引导去看台站列表。
  final VoidCallback onOpenStations;

  @override
  Widget build(BuildContext context) {
    final AprsIngest ingest = context.watch<AprsIngest>();
    final AppSettings settings = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('connect.title')),
        actions: const <Widget>[LanguageButton()],
      ),
      body: RefreshIndicator(
        onRefresh: ingest.refreshPeers,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _StatusCard(ingest: ingest, onOpenStations: onOpenStations),
            if (ingest.lastError != null) ...<Widget>[
              const SizedBox(height: 12),
              _Card(
                title: context.tr('connect.last_error'),
                children: <Widget>[
                  Text(
                    ingest.lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _SettingsCard(ingest: ingest, settings: settings),
            const SizedBox(height: 12),
            _DeviceListCard(ingest: ingest),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 状态卡
// -----------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ingest, required this.onOpenStations});

  final AprsIngest ingest;
  final VoidCallback onOpenStations;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BluetoothStage stage = ingest.stage;
    final (IconData icon, Color color) = switch (stage) {
      BluetoothStage.connected => (Icons.bluetooth_connected, Colors.green.shade600),
      BluetoothStage.connecting => (Icons.bluetooth_searching, Colors.orange.shade700),
      BluetoothStage.off => (Icons.bluetooth_disabled, theme.colorScheme.error),
      BluetoothStage.unauthorized => (Icons.lock_outline, theme.colorScheme.error),
      BluetoothStage.unavailable => (Icons.error_outline, theme.colorScheme.outline),
      BluetoothStage.ready => (Icons.bluetooth, theme.colorScheme.primary),
    };

    return _Card(
      title: context.tr('connect.status'),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 36, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    L10n.stageText(context, stage.name),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ingest.activePeer?.label ??
                        (ingest.isDemo
                            ? context.tr('connect.demo_mode')
                            : context.tr('connect.no_devices').split('\n').first),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (ingest.isConnected)
              TagChip(
                context.tr('connect.state.connected'),
                color: Colors.green.shade600,
                icon: Icons.check_circle,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (stage == BluetoothStage.off)
              FilledButton.icon(
                onPressed: () => _fire(context, ingest.requestEnable()),
                icon: const Icon(Icons.bluetooth),
                label: Text(context.tr('connect.bluetooth_off_hint')),
              ),
            if (stage == BluetoothStage.unauthorized)
              FilledButton.icon(
                onPressed: () => _fire(context, ingest.ensurePermissions()),
                icon: const Icon(Icons.lock_open),
                label: Text(context.tr('connect.permission_hint')),
              ),
            if (ingest.isConnected)
              OutlinedButton.icon(
                onPressed: () => _fire(context, ingest.disconnect()),
                icon: const Icon(Icons.link_off),
                label: Text(context.tr('connect.disconnect')),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _fire(context, ingest.refreshPeers()),
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('connect.refresh_devices')),
              ),
            if (ingest.isConnected)
              TextButton.icon(
                onPressed: onOpenStations,
                icon: const Icon(Icons.list_alt),
                label: Text(context.tr('connect.goto_stations')),
              ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 设置卡
// -----------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.ingest, required this.settings});

  final AprsIngest ingest;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.tr('common.settings'),
      children: <Widget>[
        // ---- 距离单位 KM / MI（列表页也可一键切换）----
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.straighten),
          title: Text(context.tr('settings.distance_unit')),
          trailing: SegmentedButton<DistanceUnit>(
            segments: const <ButtonSegment<DistanceUnit>>[
              ButtonSegment<DistanceUnit>(value: DistanceUnit.metric, label: Text('KM')),
              ButtonSegment<DistanceUnit>(
                value: DistanceUnit.imperial,
                label: Text('MI'),
              ),
            ],
            selected: <DistanceUnit>{settings.distanceUnit},
            showSelectedIcon: false,
            onSelectionChanged: (Set<DistanceUnit> value) =>
                settings.setDistanceUnit(value.first),
          ),
        ),
        const Divider(height: 1),

        // ---- 字段 11 含义（距离 km/m 或速度 km/h）----
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline),
          title: Text(context.tr('settings.field11_meaning')),
          subtitle: Text(
            context.tr('settings.field11_hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: DropdownButton<Field11Meaning>(
            value: settings.field11Meaning,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<Field11Meaning>>[
              for (final Field11Meaning value in Field11Meaning.values)
                DropdownMenuItem<Field11Meaning>(
                  value: value,
                  child: Text(
                    context.tr(value.i18nKey),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: (Field11Meaning? value) {
              if (value != null) settings.setField11Meaning(value);
            },
          ),
        ),
        const Divider(height: 1),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: ingest.isDemo,
          onChanged: (bool value) async {
            await ingest.setDemoMode(value);
            if (value) {
              await ingest.connect(
                ingest.peers.isEmpty
                    ? BluetoothPeer(address: 'DEMO', name: 'DEMO')
                    : ingest.peers.first,
              );
            }
          },
          title: Text(context.tr('connect.demo_mode')),
          subtitle: Text(
            context.tr('connect.demo_hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          secondary: const Icon(Icons.science_outlined),
        ),
        const Divider(height: 1),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.strictChecksum,
          onChanged: (bool value) => settings.setStrictChecksum(value),
          title: Text(context.tr('connect.strict_checksum')),
          subtitle: Text(
            context.tr('connect.strict_checksum_hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          secondary: const Icon(Icons.verified_outlined),
        ),
        const Divider(height: 1),

        // ---- 本机参考坐标（不申请 GPS，手填或由你的定位模块写入）----
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.my_location),
          title: Text(context.tr('settings.reference_position')),
          subtitle: Text(
            settings.hasReferencePosition
                ? '${settings.referenceLatitude!.toStringAsFixed(5)}, '
                    '${settings.referenceLongitude!.toStringAsFixed(5)}'
                : context.tr('settings.reference_none'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editReferencePosition(context, settings),
        ),
        const Divider(height: 1),

        // ---- 离线地图底图（可选，留空就用经纬网格）----
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.image_outlined),
          title: Text(context.tr('settings.map_image')),
          subtitle: Text(
            settings.mapImagePath ?? context.tr('settings.map_image_hint'),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editMapImagePath(context, settings),
        ),
      ],
    );
  }

  /// 输入离线底图图片的绝对路径（留空 = 只用经纬网格）。
  Future<void> _editMapImagePath(
    BuildContext context,
    AppSettings settings,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: settings.mapImagePath ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.tr('settings.map_image')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '/sdcard/PKWDWPL/map.png',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('settings.map_image_hint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(context.tr('common.clear')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.tr('common.save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    await settings.setMapImagePath(result);
  }

  Future<void> _editReferencePosition(
    BuildContext context,
    AppSettings settings,
  ) async {
    final (double?, double?)? result = await showDialog<(double?, double?)>(
      context: context,
      builder: (BuildContext context) => _ReferencePositionDialog(
        latitude: settings.referenceLatitude,
        longitude: settings.referenceLongitude,
      ),
    );
    if (result == null) return;
    await settings.setReferencePosition(result.$1, result.$2);
  }
}

/// 手动填写本机坐标（用于计算与台站的距离）。
///
/// 接入你自己的定位实现时，直接调用
/// `settings.setReferencePosition(lat, lon)` 即可，无需改这里。
class _ReferencePositionDialog extends StatefulWidget {
  const _ReferencePositionDialog({this.latitude, this.longitude});

  final double? latitude;
  final double? longitude;

  @override
  State<_ReferencePositionDialog> createState() => _ReferencePositionDialogState();
}

class _ReferencePositionDialogState extends State<_ReferencePositionDialog> {
  late final TextEditingController _latController = TextEditingController(
    text: widget.latitude?.toString() ?? '',
  );
  late final TextEditingController _lonController = TextEditingController(
    text: widget.longitude?.toString() ?? '',
  );

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('detail.distance')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _latController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: 'Latitude',
              hintText: '39.91633',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lonController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(
              labelText: 'Longitude',
              hintText: '116.27717',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop((null, null)),
          child: Text(context.tr('common.clear')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final double? lat = double.tryParse(_latController.text.trim());
            final double? lon = double.tryParse(_lonController.text.trim());
            Navigator.of(context).pop((lat, lon));
          },
          child: Text(context.tr('common.save')),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 设备列表
// -----------------------------------------------------------------------------

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({required this.ingest});

  final AprsIngest ingest;

  @override
  Widget build(BuildContext context) {
    final List<BluetoothPeer> peers = ingest.peers;

    return _Card(
      title: context.tr('connect.paired_devices'),
      trailing: IconButton(
        tooltip: context.tr('connect.refresh_devices'),
        icon: const Icon(Icons.refresh, size: 20),
        onPressed: () => _fire(context, ingest.refreshPeers()),
      ),
      children: <Widget>[
        if (peers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              context.tr('connect.no_devices'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
          )
        else
          ...peers.map((BluetoothPeer peer) {
            final bool active = ingest.activePeer == peer;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                active ? Icons.bluetooth_connected : Icons.bluetooth,
                color: active ? Colors.green.shade600 : null,
              ),
              title: Text(peer.label, style: const TextStyle(fontFamily: 'monospace')),
              subtitle: Text(peer.address, style: Theme.of(context).textTheme.bodySmall),
              trailing: active
                  ? OutlinedButton(
                      onPressed: () => _fire(context, ingest.disconnect()),
                      child: Text(context.tr('connect.disconnect')),
                    )
                  : FilledButton(
                      onPressed: () => _fire(context, ingest.connect(peer)),
                      child: Text(context.tr('connect.connect')),
                    ),
            );
          }),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 通用小部件
// -----------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 触发一个异步操作并把异常吞到调试输出（失败信息会通过 service.lastError 显示）。
void _fire(BuildContext context, Future<Object?> future) {
  future.catchError((Object error) {
    debugPrint('[PKWDWPL] 操作失败: $error');
    return null;
  });
}
