import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../widgets/common.dart';

/// 页面 4：关于页。
///
/// 需求 1 要求在这里展示：
///   * App 名称 **PKWDWPL Lite**
///   * 作者 / 开发者 **BG7LZQ**
///   * 技术接口协议提供者 **BH7NOR**
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('about.title')),
        actions: const <Widget>[LanguageButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: <Widget>[
          Column(
            children: <Widget>[
              CircleAvatar(
                radius: 38,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.radio,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppInfo.appName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('app.subtitle'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  InfoRow(label: context.tr('about.app_name'), value: AppInfo.appName),
                  InfoRow(
                    label: context.tr('about.version'),
                    value: AppInfo.versionLabel,
                    monospace: true,
                  ),
                  const Divider(),
                  InfoRow(
                    label: context.tr('about.author'),
                    value: AppInfo.author,
                    valueStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  InfoRow(
                    label: context.tr('about.protocol_provider'),
                    value: AppInfo.protocolProvider,
                    valueStyle: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Divider(),
                  InfoRow(
                    label: context.tr('about.source_format'),
                    value: AppInfo.protocolName,
                    monospace: true,
                  ),
                  InfoRow(label: context.tr('about.platform'), value: AppInfo.platform),
                  InfoRow(label: 'applicationId', value: AppInfo.applicationId, monospace: true),
                  InfoRow(label: context.tr('about.tech'), value: context.tr('about.tech_value')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('about.credits'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('about.credits_text'),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.tr('about.disclaimer'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('about.disclaimer_text'),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
