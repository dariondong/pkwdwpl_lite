import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/aprs_station.dart';

/// 语言相关小工具：切换中/英 + 把解析错误翻译成当前语言。
class L10n {
  const L10n._();

  /// 中英实时切换（默认中文）。
  ///
  /// 用 `Localizations.localeOf` 而不是 easy_localization 的 `context.locale`，
  /// 避免某些版本返回 null。
  static void toggleLanguage(BuildContext context) {
    final String code = Localizations.localeOf(context).languageCode;
    context.setLocale(code == 'zh' ? const Locale('en', 'US') : const Locale('zh', 'CN'));
  }

  static bool isChinese(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  /// 把 [AprsParseError] 翻译成当前语言文案。
  static String errorText(BuildContext context, AprsParseError error) {
    switch (error.code) {
      case AprsParseErrorCode.emptyLine:
        return context.tr('errors.empty_line');
      case AprsParseErrorCode.noStart:
        return context.tr('errors.no_start');
      case AprsParseErrorCode.notPkwdwpl:
        return context.tr('errors.not_pkwdwpl');
      case AprsParseErrorCode.checksumMismatch:
        if (error.detail == null || error.detail == 'missing') {
          return context.tr('errors.checksum_missing');
        }
        return context.tr('errors.checksum_mismatch', args: <String>[error.detail!]);
      case AprsParseErrorCode.tooFewFields:
        return context.tr('errors.too_few_fields', args: <String>[error.detail ?? '0']);
      case AprsParseErrorCode.badLatitude:
        return context.tr('errors.bad_latitude', args: <String>[error.detail ?? '']);
      case AprsParseErrorCode.badLongitude:
        return context.tr('errors.bad_longitude', args: <String>[error.detail ?? '']);
      case AprsParseErrorCode.noCallsign:
        return context.tr('errors.no_callsign');
    }
  }

  /// 连接状态文案。
  static String stageText(BuildContext context, String stageName) =>
      context.tr('connect.state.$stageName');
}
