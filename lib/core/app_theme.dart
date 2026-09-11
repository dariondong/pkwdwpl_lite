import 'package:flutter/material.dart';

/// 全局配色与尺寸。
///
/// 设计原则（按需求）：
/// * **绿色 + 白色**：绿色只做点缀（AppBar 底色、方向箭头、连接状态点），
///   列表区域一律白底深色字 —— 彻底避免「绿字融进绿底」看不清的问题；
/// * **精简**：不用底部导航，页面入口收进右上角「三个点」菜单；
/// * **字体统一**：列表里每个字段（呼号/方向/距离/时间）用**同一个字号**，
///   呼号不加粗、不放大（App 是记录日志用的，不需要突出呼号）。
class AppTheme {
  const AppTheme._();

  /// 品牌绿。
  static const Color green = Color(0xFF2E7D32);

  /// 列表字段统一字号 —— 所有列都用它，谁也不比谁大。
  ///
  /// 从 14 降到 12：14 时再加上系统字号放大，右侧的「距离 / 时间」会被挤掉
  /// （用户反馈「一行都看不见了，后面的字体都挤没了」）。
  static const double listFontSize = 12;

  /// 列表行的最大系统字号缩放。
  ///
  /// 固定列布局对字号很敏感：用户在系统设置里把字体调到 1.5x~2x 时，
  /// 任何列宽都会被撑爆。这里封顶到 1.15 —— 既照顾「想看清一点」的需求，
  /// 又保证「一个信标一行」永远不碎。
  /// 想完全跟随系统字号，把它改成 `null` 即可。
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const double? maxListTextScale = 1.15;

  /// 列表行的固定行高（配合字号缩小一起调小，一屏能看更多条）。
  static const double listRowHeight = 34;

  /// 列表行里的图标边长。
  static const double listIconSize = 20;

  /// 列表里统一的等宽字体，保证各列对齐（固定布局）。
  static const String monoFont = 'monospace';

  /// 各列的固定宽度（保证「固定位置显示」）。
  ///
  /// 宽度按**最坏情况**留足：等宽字体下 1 字符 ≈ 0.6em，
  /// 12px 字号 + 1.15 倍缩放时约 8.3px/字符，于是：
  ///   * 方向 `↑` 或 `--` —— 2 字符 ≈ 17px
  ///   * 距离 `1234.5 km` —— 9 字符 ≈ 75px → 取 72（配合省略号）
  ///   * 时间 `23:59:59`  —— 8 字符 ≈ 66px
  ///
  /// 踩过两次坑，都是**渲染出预览图才发现的**：
  ///   1. 时间写 62px、方向写 24px → 竖向折行，破坏「一行一个信标」；
  ///   2. 字号 14 时整体偏宽，小屏 / 大字号下右侧字段被挤掉。
  static const double colDir = 20; // 方向箭头（只显示箭头，不显示度数）
  static const double colDistance = 72; // 距离
  static const double colTime = 66; // 接收时间
  static const double rowGap = 6;

  /// 列表行的统一文字样式（**所有列共用**，只有颜色可以不同）。
  ///
  /// 同时强制「永远单行」：不允许换行、超长用省略号。
  static TextStyle listText(BuildContext context, {Color? color}) => TextStyle(
        fontFamily: monoFont,
        fontSize: listFontSize,
        fontWeight: FontWeight.w400,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  /// 列表里任何文本都必须带上的「不换行」参数。
  static const int listMaxLines = 1;
  static const bool listSoftWrap = false;

  /// 次要信息（时间）的柔和色：只是颜色变浅，字号仍是统一字号。
  static Color subtleColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  /// 把列表行的字号缩放**封顶**（见 [maxListTextScale]）。
  ///
  /// 只作用于列表，不影响其它页面 —— 用户仍可在系统里把字体调大，
  /// 只是列表为了保住「一行一个信标」而不跟随到那么大。
  static Widget clampTextScale({required Widget child}) {
    // 注意：const 值 + 可空局部变量会让 analyzer 报
    // unnecessary_nullable_for_final_variable_declarations，
    // 所以这里用一个可变的 switch 常量来判断，保留「改成 null 即完全跟随系统」的能力。
    const double? configured = maxListTextScale;
    switch (configured) {
      case null:
        return child;
      default:
        final double max = configured;
        return Builder(
          builder: (BuildContext context) {
            final MediaQueryData data = MediaQuery.of(context);
            final double scale =
                data.textScaler.scale(listFontSize) / listFontSize;
            if (scale <= max) return child;
            return MediaQuery(
              data: data.copyWith(textScaler: TextScaler.linear(max)),
              child: child,
            );
          },
        );
    }
  }

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
