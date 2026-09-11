import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';

/// AppBar 上的「中/EN」语言切换按钮（需求：所有页面顶部可切换）。
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isZh = L10n.isChinese(context);
    return TextButton(
      onPressed: () => L10n.toggleLanguage(context),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size(56, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.language, size: 18),
          const SizedBox(width: 4),
          Text(
            isZh ? '中' : 'EN',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 统一的「标签 : 值」信息行（详情页 / 关于页用）。
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.monospace = false,
    this.trailing,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool monospace;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: (valueStyle ?? theme.textTheme.bodyMedium)?.copyWith(
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 小圆角标签（状态、校验结果等）。
class TagChip extends StatelessWidget {
  const TagChip(
    this.text, {
    super.key,
    this.color,
    this.icon,
  });

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color tone = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(fontSize: 12, color: tone, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 空状态占位。
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// `context.tr` 的简写（带位置参数时少写点样板）。
String trArgs(
  BuildContext context,
  String key, {
  List<String> args = const <String>[],
}) =>
    args.isEmpty ? context.tr(key) : context.tr(key, args: args);
