import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_settings.dart';
import '../core/formats.dart';
import '../core/l10n.dart';
import '../data/station_store.dart';
import '../models/aprs_icon.dart';
import '../models/aprs_station.dart';
import '../widgets/common.dart';
import 'offline_map_page.dart';

/// 页面 3：台站详情页（台账信息）。
///
/// 接收完整的 [AprsStation] 对象渲染；如果同一呼号又收到新语句，
/// 会自动切换到最新的一条（仍以传入对象作为兜底数据）。
class StationDetailPage extends StatelessWidget {
  const StationDetailPage({super.key, required this.station});

  final AprsStation station;

  @override
  Widget build(BuildContext context) {
    final StationStore store = context.watch<StationStore>();
    final AprsStation data = store.byCallsign(station.callsign) ?? station;
    final AppSettings settings = context.watch<AppSettings>();
    final ThemeData theme = Theme.of(context);

    final DistanceView distance = Formats.distance(
      data,
      unit: settings.distanceUnit,
      field11: settings.field11Meaning,
      referenceLatitude: settings.referenceLatitude,
      referenceLongitude: settings.referenceLongitude,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(data.callsign),
        actions: <Widget>[
          IconButton(
            tooltip: context.tr('map.center_on'),
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OfflineMapPage(focusCallsign: data.callsign),
              ),
            ),
          ),
          const LanguageButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          // ---- 数据质量提示（字段数异常 / 呼号可疑 / 校验不符）----
          if (data.hasWarnings) _WarningBanner(station: data),

          // ---- 抬头：图标 + 呼号 + 状态标签 ----
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 30,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: AprsSymbolIcon(
                  icon: data.iconRaw,
                  size: 40,
                  semanticLabel: data.iconLabel,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      data.callsign,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        TagChip(
                          Formats.statusLabel(context, data),
                          color: data.statusValid == false
                              ? theme.colorScheme.error
                              : Colors.green.shade700,
                          icon: data.statusValid == false
                              ? Icons.block
                              : Icons.check_circle,
                        ),
                        TagChip(
                          data.iconLabel,
                          icon: data.hasOfficialIcon ? Icons.image : data.icon,
                        ),
                        if (data.receiveSeq > 0)
                          TagChip(
                            '#${data.receiveSeq}',
                            icon: Icons.tag,
                            color: theme.colorScheme.secondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ---- 台账信息 ----
          _SectionCard(
            title: context.tr('stations.detail'),
            children: <Widget>[
              InfoRow(
                label: context.tr('detail.seq'),
                value: '#${data.receiveSeq}',
                monospace: true,
              ),
              InfoRow(
                label: context.tr('detail.callsign'),
                value: data.callsign,
                monospace: true,
                trailing: data.callsignSuspicious
                    ? Icon(Icons.help_outline,
                        size: 18, color: theme.colorScheme.error)
                    : null,
              ),
              InfoRow(
                label: context.tr('detail.icon'),
                value: '${data.iconRaw}  (${data.iconLabel})',
                monospace: true,
              ),
              InfoRow(
                label: context.tr('detail.status'),
                value: Formats.statusLabel(context, data),
              ),
              const Divider(),
              InfoRow(
                label: context.tr('detail.latitude'),
                value: Formats.latLon(data.latitude, isLatitude: true),
                monospace: true,
              ),
              InfoRow(
                label: context.tr('detail.longitude'),
                value: Formats.latLon(data.longitude, isLatitude: false),
                monospace: true,
              ),
              InfoRow(
                label: context.tr('detail.altitude'),
                value: Formats.altitude(data.altitudeMeters),
              ),
              InfoRow(
                label: context.tr('detail.course'),
                value: Formats.course(data.courseDegrees),
              ),
              InfoRow(
                label: context.tr('detail.distance'),
                value: distance.hasValue
                    ? '${distance.text!}'
                        '${distance.source == DistanceSource.estimated ? ' *' : ''}'
                    : '--',
              ),
              InfoRow(
                label: context.tr('detail.field11_raw'),
                value: Formats.rawField11(data),
                monospace: true,
                trailing: Text(
                  context.tr(settings.field11Meaning.i18nKey),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (distance.source == DistanceSource.estimated)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr('detail.distance_estimated_hint'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const Divider(),
              InfoRow(
                label: context.tr('detail.date'),
                value: data.utcDate.isEmpty ? '--' : '${data.utcDate}  (ddmmyy)',
                monospace: true,
              ),
              InfoRow(
                label: '${context.tr('detail.time')} UTC',
                value: data.utcTime.isEmpty ? '--' : '${data.utcTime}  (hhmmss)',
                monospace: true,
              ),
              if (data.utcDateTime != null)
                InfoRow(
                  label: '${context.tr('detail.time')} ${context.tr('detail.local')}',
                  value: Formats.localDateTimeOfUtc(data.utcDateTime!),
                ),
              InfoRow(
                label: context.tr('detail.received_at'),
                value: Formats.localDateTime(data.receivedAt),
              ),
              InfoRow(
                label: context.tr('detail.field_count'),
                value: '${data.parsedFieldCount}',
                monospace: true,
              ),
              InfoRow(
                label: context.tr('detail.checksum'),
                value: data.claimedChecksum == null
                    ? context.tr('detail.checksum_missing')
                    : data.checksumValid
                        ? '${data.claimedChecksum}  ${context.tr('detail.checksum_ok')}'
                        : context.tr('detail.checksum_bad',
                            args: <String>[data.claimedChecksum!, data.computedChecksum]),
                trailing: Icon(
                  data.checksumValid ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: data.checksumValid
                      ? Colors.green.shade700
                      : theme.colorScheme.error,
                ),
              ),
              if (data.softError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    L10n.errorText(context, data.softError!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- 14 字段分解（调试友好）----
          _SectionCard(
            title: context.tr('detail.fields', args: <String>['${data.fieldRows.length}']),
            children: <Widget>[
              for (final AprsFieldRow row in data.fieldRows)
                InfoRow(
                  label: '${row.index}. ${row.label}',
                  value: row.value.isEmpty
                      ? '␀ ${context.tr('detail.empty_field')}'
                      : row.value,
                  monospace: true,
                ),
            ],
          ),

          const SizedBox(height: 16),

          // ---- 原始语句（放底部，方便调试）----
          _SectionCard(
            title: context.tr('detail.raw'),
            trailing: IconButton(
              tooltip: context.tr('common.copy'),
              icon: const Icon(Icons.copy, size: 20),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: data.raw));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('common.copied'))),
                );
              },
            ),
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  data.raw,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('detail.raw_hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 数据质量提示条。
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.station});

  final AprsStation station;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> messages = <String>[
      if (station.fieldCountAnomaly)
        context.tr('detail.warn_field_count',
            args: <String>['${station.parsedFieldCount}']),
      if (station.callsignSuspicious) context.tr('detail.warn_callsign'),
      if (!station.checksumValid) context.tr('detail.warn_checksum'),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.report_problem,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 6),
              Text(
                context.tr('detail.data_quality'),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final String message in messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $message', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
