/// 应用元数据（需求 1：作者 / 协议提供者必须体现在「关于」页）。
///
/// 发版时只需同步改这里和 `pubspec.yaml` 的 `version:`，
/// 可用 `python3 tool/sync_version.py` 校验两者是否一致。
class AppInfo {
  const AppInfo._();

  static const String appName = 'PKWDWPL Lite';

  /// 与 pubspec.yaml 的 version 前半段保持一致。
  static const String appVersion = '1.1.0';

  /// 与 pubspec.yaml 的 version 后半段（+N）保持一致。
  static const String buildNumber = '2';

  /// 作者 / 开发者。
  static const String author = 'BG7LZQ';

  /// 技术接口协议提供者。
  static const String protocolProvider = 'BH7NOR';

  /// 包名。
  static const String packageName = 'pkwdwpl_lite';

  /// Android applicationId。
  static const String applicationId = 'top.theez.pkwdwpl_lite';

  /// 数据协议。
  static const String protocolName = r'Kenwood $PKWDWPL (NMEA 0183)';

  /// 平台说明。
  static const String platform = 'Android / Classic Bluetooth SPP';

  static String get versionLabel =>
      buildNumber.isEmpty ? appVersion : '$appVersion+$buildNumber';
}
