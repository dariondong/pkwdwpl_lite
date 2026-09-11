import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/core/app_theme.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/models/aprs_icon.dart';
import 'package:pkwdwpl_lite/models/geo_math.dart' show DistanceUnit;
import 'package:pkwdwpl_lite/widgets/station_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 台站列表行的硬性约束测试（每次改字号 / 列宽 / 间距都要过一遍）：
///
///   1. **一个信标一行** —— 行高固定，不因换行被撑高；
///   2. **不显示接收序号**；
///   3. **图标紧邻方向箭头** —— 中间只留很小的间隔
///      （用户反馈「图标和方向中间隔得太多」）；
///   4. **字体统一** —— 所有列字号相同、且都不加粗；
///   5. **界面缩放** —— 四档（小/标准/大/特大）都不塌，
///      且字号与行高同步缩放；
///   6. 切换距离单位后仍单行。
///
/// 实现说明：直接渲染 [StationTile]（它不调用 tr()），
/// 因为 `EasyLocalization` 是单例，同一文件里第二次 `pumpWidget` 会挂不上树
/// （现象：找不到 Scaffold 且没有任何报错），那样就没法在一个文件里跑多组配置。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String sentence({
    required String callsign,
    required String icon,
    required String time,
    String status = 'V',
    String latDm = '3955.09',
    String lonDm = '11616.91',
    String altitude = '',
    String course = '',
    String distance = '',
  }) {
    final String body = <String>[
      'PKWDWPL', time, status, latDm, 'N', lonDm, 'E',
      altitude, course, '110926', distance, callsign, icon,
    ].join(',');
    return r'$' '$body*${NmeaChecksum.format(NmeaChecksum.computeFrom(body))}';
  }

  /// 在指定「屏宽 × 系统字号 × 界面缩放档位」下渲染并校验所有约束。
  Future<void> verify({
    required WidgetTester tester,
    required double widthDp,
    required double textScale,
    ListScale scale = ListScale.normal,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'list_scale': scale.name,
    });
    final AppSettings settings = await AppSettings.load();
    expect(settings.listScale, scale, reason: '缩放档位没有正确读回');

    final ListMetrics m = AppTheme.metricsFor(scale);

    final List<AprsStation> stations = <AprsStation>[
      // 有航向（→ 画箭头，可以量间距）+ 有距离 + 状态 A
      AprsStationParser.parse(sentence(
        callsign: 'BG1UBU-9', icon: '/j', time: '102353', status: 'A',
        altitude: '4', course: '103', distance: '000050',
      )),
      // 长呼号、无航向（显示 --）、无距离
      AprsStationParser.parse(sentence(
        callsign: 'BI4PGN-11', icon: '/i', time: '102339',
        latDm: '3958.55', lonDm: '11625.70',
      )),
      AprsStationParser.parse(sentence(
        callsign: 'BG1QGD-10', icon: '/&', time: '102921',
        latDm: '4000.46', lonDm: '11632.53', course: '359',
      )),
      AprsStationParser.parse(sentence(
        callsign: 'BH3BBJ-1', icon: '/r', time: '102627',
        latDm: '3907.80', lonDm: '11712.20',
      )),
    ];

    await tester.pumpWidget(
      MediaQuery(
        // 模拟系统字号缩放
        data: MediaQueryData(
          size: Size(widthDp, 600),
          textScaler: TextScaler.linear(textScale),
        ),
        child: ChangeNotifierProvider<AppSettings>.value(
          value: settings,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: Scaffold(
              backgroundColor: Colors.white,
              body: SizedBox(
                width: widthDp,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: <Widget>[
                    for (final AprsStation station in stations)
                      StationTile(
                        station: station,
                        onTap: () {},
                        onDoubleTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final Finder tiles = find.byType(StationTile);
    expect(tiles, findsNWidgets(stations.length));

    final String info =
        '${widthDp.toInt()}dp/系统${textScale}x/界面${scale.name}';

    // ---- 约束 1 & 5：一行一个信标；行高随档位缩放且不塌 ----
    for (int i = 0; i < stations.length; i++) {
      expect(
        tester.getSize(tiles.at(i)).height,
        m.rowHeight,
        reason: '$info 下第 ${i + 1} 行高度异常（有字段换行或溢出）',
      );
    }

    // ---- 约束 2：不再显示接收序号 ----
    for (int seq = 1; seq <= stations.length; seq++) {
      expect(find.text('#$seq'), findsNothing,
          reason: '$info 下列表仍显示接收序号 #$seq');
    }

    // ---- 约束 3：图标紧邻方向箭头 ----
    // 第 3 条（BG1QGD-10）有航向 → 会画箭头，可量水平间距。
    final Finder tile3 = tiles.at(2);
    final Finder iconIn3 =
        find.descendant(of: tile3, matching: find.byType(AprsSymbolIcon));
    final Finder arrowIn3 =
        find.descendant(of: tile3, matching: find.byIcon(Icons.navigation));
    expect(iconIn3, findsOneWidget, reason: '$info 下第 3 行没有找到图标');
    expect(arrowIn3, findsOneWidget, reason: '$info 下第 3 行没有找到方向箭头');

    final Rect iconRect = tester.getRect(iconIn3);
    final Rect arrowRect = tester.getRect(arrowIn3);
    final double gapPx = arrowRect.left - iconRect.right;
    // 允许一点点浮动（图标本身有内边距），但绝不允许空出一大截
    expect(gapPx, lessThanOrEqualTo(m.tightGap + 8 * m.scale),
        reason: '$info 下图标与方向箭头间隔 $gapPx px 过大（应约 ${m.tightGap} px）');

    // ---- 约束 4：字体统一（字号 = 基准值；实际大小由 MediaQuery 缩放）----
    for (int i = 0; i < stations.length; i++) {
      final Iterable<Element> texts =
          find.descendant(of: tiles.at(i), matching: find.byType(Text)).evaluate();
      expect(texts, isNotEmpty, reason: '$info 第 ${i + 1} 行没有可校验的文本');
      for (final Element e in texts) {
        final Text w = e.widget as Text;
        final String content = w.data ?? '';
        if (content.trim().isEmpty) continue;
        final TextStyle s = w.style!;
        expect(s.fontSize, AppTheme.baseListFontSize,
            reason: '$info 第 ${i + 1} 行「$content」字号 ${s.fontSize}'
                ' ≠ 基准 ${AppTheme.baseListFontSize}');
        expect(s.fontWeight, FontWeight.w400,
            reason: '$info 第 ${i + 1} 行「$content」不应加粗');
        expect(s.fontFamily, AppTheme.monoFont,
            reason: '$info 第 ${i + 1} 行「$content」字体族应为等宽');
      }
    }

    // ---- 约束 5：列表不叠加系统字号（否则列宽会与字号错配）----
    final TextStyle callsignStyle =
        (find.text('BG1UBU-9').evaluate().first.widget as Text).style!;
    expect(callsignStyle.fontSize, AppTheme.baseListFontSize,
        reason: '$info 下系统字号不应影响列表基准字号');

    // ---- 约束 6：切换距离单位后仍单行 ----
    await settings.setDistanceUnit(
      settings.distanceUnit == DistanceUnit.metric
          ? DistanceUnit.imperial
          : DistanceUnit.metric,
    );
    await tester.pump();
    for (int i = 0; i < stations.length; i++) {
      expect(tester.getSize(tiles.at(i)).height, m.rowHeight,
          reason: '$info 下切换距离单位后第 ${i + 1} 行被撑高');
    }
  }

  testWidgets('常见屏 + 默认字号', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 360, textScale: 1.0);
  });

  testWidgets('小屏 + 系统字号 1.3x', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 320, textScale: 1.3);
  });

  testWidgets('系统字号 2.0x（极端，列表不受其影响）', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 360, textScale: 2.0);
  });

  testWidgets('界面缩放：小档（0.85x）', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 360, textScale: 1.0, scale: ListScale.small);
  });

  testWidgets('界面缩放：大档（1.15x）', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 360, textScale: 1.0, scale: ListScale.large);
  });

  testWidgets('界面缩放：特大档（1.3x）+ 小屏（最严苛）', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 320, textScale: 1.0, scale: ListScale.huge);
  });

  testWidgets('界面缩放：档位循环 小→标准→大→特大→小', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await AppSettings.load();
    expect(settings.listScale, ListScale.normal, reason: '默认应为标准');

    await settings.cycleListScale();
    expect(settings.listScale, ListScale.large);
    await settings.cycleListScale();
    expect(settings.listScale, ListScale.huge);
    await settings.cycleListScale();
    expect(settings.listScale, ListScale.small, reason: '应循环回小');
    await settings.cycleListScale();
    expect(settings.listScale, ListScale.normal);

    // 落盘校验
    await settings.setListScale(ListScale.large);
    final AppSettings reloaded = await AppSettings.load();
    expect(reloaded.listScale, ListScale.large, reason: '档位未持久化');
  });
}
