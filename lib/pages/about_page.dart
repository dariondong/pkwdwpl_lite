import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../core/app_theme.dart';
import '../widgets/common.dart';

/// 页面 4：关于页。
///
/// 展示：
///   * App 名称 / 版本
///   * 作者 / 开发者 **BG7LZQ**
///   * 技术接口协议提供者 **BH7NOR**
///   * 支持者 **BA3RZL**
///   * **推荐作者的另一款作品 APRSLocus**（可点链接：官网 / 源码 / 下载）
///   * 数据与协议、免责声明
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
          // ---- 抬头 ----
          Column(
            children: <Widget>[
              const CircleAvatar(
                radius: 38,
                backgroundColor: AppTheme.green,
                child: Icon(Icons.radio, size: 40, color: Colors.white),
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

          // ---- 基本信息 ----
          _Card(
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
                valueStyle: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              InfoRow(
                label: context.tr('about.protocol_provider'),
                value: AppInfo.protocolProvider,
                valueStyle: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              // 支持者（BA3RZL 等；名单在 AppInfo.supporters 里）
              InfoRow(
                label: context.tr('about.support'),
                value: AppInfo.supporters.join('、'),
                valueStyle: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Divider(),
              InfoRow(
                label: context.tr('about.source_format'),
                value: AppInfo.protocolName,
                monospace: true,
              ),
              InfoRow(label: context.tr('about.platform'), value: AppInfo.platform),
              InfoRow(
                label: 'applicationId',
                value: AppInfo.applicationId,
                monospace: true,
              ),
              InfoRow(
                label: context.tr('about.tech'),
                value: context.tr('about.tech_value'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- 推荐：作者的另一款作品 ----
          _RelatedAppCard(),
          const SizedBox(height: 16),

          // ---- 数据与协议 ----
          _SectionCard(
            title: context.tr('about.credits'),
            body: context.tr('about.credits_text'),
          ),
          const SizedBox(height: 16),

          // ---- 免责声明 ----
          _SectionCard(
            title: context.tr('about.disclaimer'),
            body: context.tr('about.disclaimer_text'),
          ),
        ],
      ),
    );
  }
}

/// 推荐卡片：APRSLocus（可点链接）。
class _RelatedAppCard extends StatelessWidget {
  const _RelatedAppCard();

  Future<void> _open(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    // 异步之前先取好需要的对象：异步后用 context 会被 lint 拦（use_build_context_synchronously）
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String copiedText =
        context.tr('about.link_copied', args: <String>[url]);
    final String failedText =
        context.tr('about.link_failed', args: <String>[url]);

    try {
      final bool ok =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
      // 返回 false 表示系统没有可处理该链接的应用
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(SnackBar(content: Text(copiedText)));
    } catch (error) {
      // 被系统拒绝 / 没装浏览器：提示一下并顺手把链接复制进剪贴板，
      // 不让操作静默失败。
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(SnackBar(content: Text(failedText)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.recommend, size: 20, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('about.related_title'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${AppInfo.relatedAppName} · ${context.tr('about.related_subtitle')}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('about.related_desc'),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
            ),
            const Divider(height: 20),
            _LinkTile(
              icon: Icons.language,
              label: context.tr('about.related_website'),
              value: AppInfo.relatedAppWebsite,
              onTap: () => _open(context, AppInfo.relatedAppWebsite),
            ),
            _LinkTile(
              icon: Icons.download,
              label: context.tr('about.related_releases'),
              value: AppInfo.relatedAppReleases,
              onTap: () => _open(context, AppInfo.relatedAppReleases),
            ),
            _LinkTile(
              icon: Icons.code,
              label: context.tr('about.related_source'),
              value: AppInfo.relatedAppRepository,
              onTap: () => _open(context, AppInfo.relatedAppRepository),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// 一行可点击链接：左图标 + 名称 + 链接（等宽小字）。
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // 显示时去掉 https:// 前缀，短一点更好看
    final String shown = value.replaceFirst(RegExp(r'^https?://'), '');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: AppTheme.green),
            const SizedBox(width: 10),
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                shown,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.monoFont,
                  fontSize: 12,
                  color: AppTheme.green,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.green,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 14),
          ],
        ),
      ),
    );
  }
}

/// 统一样式的卡片（圆角 + 白底）。
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );
}

/// 「标题 + 正文」的小节卡片。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppTheme.green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
