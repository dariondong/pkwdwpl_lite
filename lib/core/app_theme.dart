import 'package:flutter/material.dart';

/// 全局配色与尺寸。
///
/// 设计原则（按需求）：
/// * **绿色 + 白色**：绿色只做点缀（AppBar 底色、方向箭头、连接状态圆点），
///   列表区域一律白底深色字 —— 彻底避免「绿字融进绿底」看不清的问题；
/// * **精简**：不用底部导航，页面入口收进右上角「三个点」菜单；
/// * **字体统一**：列表里每个字段（序号/呼号/方向/距离/时间）用**同一个字号**，
///   呼号不加粗、不放大（App 是记录日志用的，不需要突出呼号）。
class AppTheme {
  const AppTheme._();

  /// 品牌绿。
  static const Color green = Color(0xFF2E7D32);

  /// 列表字段统一字号 —— 所有列都用它，谁也不比谁大。
  static const double listFontSize = 14;

  /// 列表里统一的等宽字体，保证各列对齐（固定布局）。
  static const String monoFont = 'monospace';

  /// 列表行里的图标边长。
  static const double listIconSize = 22;

  /// 各列的固定宽度（保证「固定位置显示」）。
  ///
  /// 宽度必须按**最坏情况**留足：等宽字体下 1 个字符 ≈ 0.6em，
  /// 所以 14px 字号下每字符约 8.4px。算下来：
  ///   * 序号 `#1234`  —— 5 字符 ≈ 42px
  ///   * 时间 `23:59:59` —— 8 字符 ≈ 68px
  ///   * 距离 `1234.5 km` —— 9 字符 ≈ 76px
  /// 之前把时间写成 62px、方向写成 24px，实测会**竖向折行**，
  /// 直接破坏「一个信标一行」（用 test/ui_preview_test.dart 渲染出来才看到）。
  static const double colSeq = 42; // 接收序号
  static const double colDir = 22; // 方向箭头（只显示箭头，不显示度数）
  static const double colDistance = 76; // 距离
  static const double colTime = 70; // 接收时间
  static const double rowGap = 6;

  /// 列表行的统一文字样式（**所有列共用**，只有颜色可以不同）。
  ///
  /// 同时强制「永远单行」：不允许换行、超长用省略号。
  /// 这是「一个信标一行」的硬保障 —— 就算某个字段异常长也不会撑成两行。
  static TextStyle listText(BuildContext context, {Color? color}) => TextStyle(
        fontFamily: monoFont,
        fontSize: listFontSize,
        fontWeight: FontWeight.w400,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  /// 列表里任何文本都必须带上的「不换行」参数。
  static const int listMaxLines = 1;
  static const bool listSoftWrap = false;

  /// 次要信息（序号、时间）的柔和色：只是颜色变浅，字号仍是统一字号。
  static Color subtleColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isLight = brightness == Brightness.light;

    // 只在浅色模式下把绿色注入色板；深色模式保持中性底，
    // 否则「深底 + 深绿文字」同样会有对比度问题。
    final ColorScheme scheme = isLight
        ? ColorScheme.fromSeed(
            seedColor: green,
            brightness: Brightness.light,
          ).copyWith(
            // 白色为主：列表、卡片都在白底上
            surface: Colors.white,
            onSurface: const Color(0xFF1B1B1B),
          )
        : ColorScheme.fromSeed(
            seedColor: green,
            brightness: Brightness.dark,
          );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // 白底（浅色）/ 近黑底（深色），字号统一由 AppTheme 控制
      scaffoldBackgroundColor: isLight ? Colors.white : scheme.surface,
      appBarTheme: AppBarTheme(
        // 绿底白字：绿色 + 白色的主要落点，对比度足够
        backgroundColor: green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      // 列表行更紧凑（一行一个信标）
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
        dense: true,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: isLight ? 0.35 : 0.25),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isLight ? Colors.white : scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
