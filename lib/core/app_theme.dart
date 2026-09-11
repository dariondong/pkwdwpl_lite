import 'package:flutter/material.dart';

/// 全局配色与尺寸。
///
/// 设计原则（按需求）：
/// * **绿色 + 白色**：绿色只做点缀（AppBar 底色、方向箭头、连接状态点），
///   列表区域一律白底深色字 —— 彻底避免「绿字融进绿底」看不清的问题；
/// * **精简**：不用底部导航，页面入口收进右上角「三个点」菜单；
/// * **字体统一**：列表里每个字段（呼号/方向/距离/时间）用**同一个字号**，
///   呼号不加粗、不放大（App 是记录日志用的，不需要突出呼号）。
/// 列表界面的缩放档位（用户可在右上角菜单里切换）。
///
/// 为什么要有这个：列表是**固定列布局**，对字号很敏感。
/// 与其替用户猜一个合适的字号，不如直接给他一个开关。
///
/// 注意：列表**不跟随系统字号**，只用这里的档位 ——
/// 这样列宽 / 行高永远和字号同步缩放，任何一档都不会把字段挤没。
/// （其它页面照常跟随系统字号。）
enum ListScale {
  small(0.85, 'settings.list_scale_small'),
  normal(1.0, 'settings.list_scale_normal'),
  large(1.15, 'settings.list_scale_large'),
  huge(1.3, 'settings.list_scale_huge');

  const ListScale(this.factor, this.i18nKey);

  /// 相对于基准尺寸（字号 12 / 行高 34）的缩放倍数。
  final double factor;

  /// 多语言 key。
  final String i18nKey;

  /// 菜单里点一下切到下一档（循环）。
  ListScale get next => ListScale.values[(index + 1) % ListScale.values.length];

  static ListScale fromName(String? name) => ListScale.values.firstWhere(
        (ListScale value) => value.name == name,
        orElse: () => ListScale.normal,
      );
}

/// 列表行的一套尺寸（字号 / 图标 / 行高 / 各列宽度）。
///
/// 全部由 [scale] 统一推导 —— 改档位时字号与列宽一起变，
/// 不会出现「字大了但列宽没变，右侧字段被挤掉」的情况。
class ListMetrics {
  const ListMetrics(this.scale);

  final double scale;

  double get fontSize => AppTheme.baseListFontSize * scale;
  double get iconSize => 18 * scale;
  double get rowHeight => 34 * scale;
  /// 方向箭头列。取 16 是为了刚好装下 15px 的箭头图标 ——
  /// 若列宽比图标小，图标会“溢出”绘制，和旁边的图标看着像粘在一起。
  double get colDir => 16 * scale;
  double get colDistance => 58 * scale;
  double get colTime => 46 * scale;

  // 上面这组数字是**算出来**的，不是猜的（脚本核过 12 种「屏宽 × 档位」组合）：
  //   呼号用 Expanded 吃掉剩余空间，其余列宽固定 →
  //   即使 320dp 小屏 + 特大档（最严苛），呼号也还有 8.9 个字符位，
  //   足够放下 `BI4PGN-11` 这类 8~9 位呼号。
  //   时间列按 `HH:mm`（5 字符）配：全程不再溢出一像素。

  /// 列与列之间的间隔（图标与箭头之间用更小的 [tightGap]，
  /// 否则中间会空出一大截 —— 用户反馈过这个）。
  ///
  /// 实测（360dp / 标准档）：呼号→图标 6.0px、**图标→箭头 5.5px**、
  /// 箭头→距离 3.6px —— 用 `flutter test test/tmp_gap_check_test.dart`
  /// 这类小脚本量出来的，不靠肉眼估。
  double get gap => 6 * scale;
  double get tightGap => 5 * scale;
}

class AppTheme {
  const AppTheme._();

  /// 品牌绿。
  static const Color green = Color(0xFF2E7D32);

  /// 列表字段的**基准**字号（实际显示 = 该值 × 用户选的缩放档位）。
  ///
  /// 从 14 降到 12：14 时再加上系统字号放大，右侧的「距离 / 时间」会被挤掉
  /// （用户反馈「一行都看不见了，后面的字体都挤没了」）。
  static const double baseListFontSize = 12;

  /// 列表里统一的等宽字体，保证各列对齐（固定布局）。
  static const String monoFont = 'monospace';

  /// 列表里任何文本都必须带上的「不换行」参数。
  static const int listMaxLines = 1;
  static const bool listSoftWrap = false;

  /// 取某个缩放档位下的一整套尺寸。
  static ListMetrics metricsFor(ListScale scale) => ListMetrics(scale.factor);

  /// 列表行的统一文字样式（**所有列共用**，只有颜色可以不同）。
  ///
  /// 字号写的是基准值，实际大小由行外层包着的
  /// `MediaQuery(textScaler: TextScaler.linear(scale))` 统一缩放 ——
  /// 这样字号与列宽一定同步，不会出现「字大了列宽没变」。
  static TextStyle listText(BuildContext context, {Color? color}) => TextStyle(
        fontFamily: monoFont,
        fontSize: baseListFontSize,
        fontWeight: FontWeight.w400,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      );

  /// 次要信息（时间）的柔和色：只是颜色变浅，字号仍是统一字号。
  static Color subtleColor(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

  /// 让列表行**只按用户选的档位缩放**（不叠加系统字号）。
  ///
  /// 固定列布局最怕「字号来自系统、列宽写死在代码里」这种错配 ——
  /// 系统字号一旦调大，右侧字段必被挤掉。
  /// 所以列表干脆完全由 App 内的档位决定；其它页面仍然跟随系统字号。
  static Widget scaledForList({
    required ListScale scale,
    required Widget child,
  }) =>
      Builder(
        builder: (BuildContext context) {
          // 必须基于**环境里的** MediaQueryData 做 copyWith：
          // 直接 new 一个 MediaQueryData 会把屏幕尺寸/内边距等全丢掉，
          // 布局会直接塔掉。copyWith(textScaler:) 同时会把系统字号替换掉。
          final MediaQueryData data = MediaQuery.of(context);
          return MediaQuery(
            data: data.copyWith(textScaler: TextScaler.linear(scale.factor)),
            child: child,
          );
        },
      );

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
