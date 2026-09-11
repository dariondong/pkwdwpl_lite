/// 应用元数据（需求 1：作者 / 协议提供者必须体现在「关于」页）。
///
/// 发版时只需同步改这里和 `pubspec.yaml` 的 `version:`，
/// 可用 `python3 tool/sync_version.py` 校验两者是否一致。
class AppInfo {
  const AppInfo._();

  static const String appName = 'PKWDWPL Lite';

  /// 与 pubspec.yaml 的 version 前半段保持一致。
  static const String appVersion = '1.1.1';

  /// 与 pubspec.yaml 的 version 后半段（+N）保持一致。
  static const String buildNumber = '3';

  /// 作者 / 开发者。
  static const String author = 'BG7LZQ';

  /// 技术接口协议提供者。
  static const String protocolProvider = 'BH7NOR';

  /// 支持者 / 支持单位（可以放多位，关于页会自动逐条列出）。
  ///
  /// 如果你的称呼不是「支持」而是「测试 / 贡献 / 硬件支持」等，
  /// 改翻译文件里的 `about.support` 这一条即可（zh-CN.json / en-US.json）。
  static const List<String> supporters = <String>['BA3RZL'];

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

  // ---------------------------------------------------------------------------
  // 作者的另一款作品（关于页里做推荐）
  // ---------------------------------------------------------------------------

  /// 推荐 App 的名称。
  static const String relatedAppName = 'APRSLocus';

  /// 推荐 App 的官网（同时也是下载入口）。
  static const String relatedAppWebsite = 'https://aprslocus.theez.top/';

  /// 推荐 App 的 GitHub 仓库（看源码 / 提 issue）。
  static const String relatedAppRepository =
      'https://github.com/dariondong/APRSLocus';

  /// 推荐 App 的发布页（拿最新安装包）。
  static const String relatedAppReleases =
      'https://github.com/dariondong/APRSLocus/releases';

  /// 作者主页。
  static const String authorHomepage = 'https://theez.top';
}
