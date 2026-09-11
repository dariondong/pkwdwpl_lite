import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/core/app_theme.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/models/geo_math.dart' show DistanceUnit;
import 'package:pkwdwpl_lite/widgets/station_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 台站列表行的硬性约束测试（每次改字号 / 列宽都要过一遍）：
///
///   1. **一个信标一行** —— 行高固定，不因换行被撑高；
///   2. **不显示接收序号** —— 需求明确要求去掉编号列；
///   3. **字体统一** —— 所有列字号相同、且都不加粗；
///   4. **系统字号放大也不塌** —— 列表内缩放被封顶（用户反馈
///      「后面的字体都挤没了」，就是字号 14 + 系统放大导致的）；
///   5. 切换距离单位（KM/MI）后仍单行。
///
/// 实现说明：这里**直接渲染 [StationTile]**，不渲染整个 App。
/// 因为 `EasyLocalization` 是单例 —— 同一测试文件里第二次 `pumpWidget`
/// 会挂不上 widget 树（现象：找不到 Scaffold 且没有任何报错），
/// 那样就只能一个文件一个用例，没法在多种「屏宽 × 字号」下跑。
/// StationTile 本身不调用 tr()，所以可以直接渲染。
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

  /// 在指定「屏宽 + 系统字号」下渲染 4 条真实台站，并逐条校验所有约束。
  Future<void> verify({
    required WidgetTester tester,
    required double widthDp,
    required double textScale,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await AppSettings.load();

    final List<AprsStation> stations = <AprsStation>[
      // 有航向 + 有距离 + 状态 A
      AprsStationParser.parse(sentence(
        callsign: 'BG1UBU-9', icon: '/j', time: '102353', status: 'A',
        altitude: '4', course: '103', distance: '000050',
      )),
      // 长呼号、无航向、无距离
      AprsStationParser.parse(sentence(
        callsign: 'BI4PGN-11', icon: '/i', time: '102339',
        latDm: '3958.55', lonDm: '11625.70',
      )),
      // 最长呼号
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

    final String ctxInfo = '${widthDp.toInt()}dp x$textScale';

    // ---- 约束 1 & 4：一行一个信标；系统字号放大也不塌 ----
    for (int i = 0; i < stations.length; i++) {
      expect(
        tester.getSize(tiles.at(i)).height,
        AppTheme.listRowHeight,
        reason: '$ctxInfo 下第 ${i + 1} 行高度异常（有字段换行或溢出）',
      );
    }

    // ---- 约束 2：不再显示接收序号 ----
    for (int seq = 1; seq <= stations.length; seq++) {
      expect(find.text('#$seq'), findsNothing,
          reason: '$ctxInfo 下列表仍显示接收序号 #$seq');
    }

    // ---- 约束 3：字体统一（字号 / 粗细 / 字体族）----
    //
    // 不去按内容找字段（距离会随单位/字号变化、时间用的是本机接收时刻，
    // 写死文案很脆），而是直接遍历**行内所有 Text**，逐个校验样式。
    for (int i = 0; i < stations.length; i++) {
      final Iterable<Element> texts =
          find.descendant(of: tiles.at(i), matching: find.byType(Text)).evaluate();
      expect(texts, isNotEmpty, reason: '$ctxInfo 第 ${i + 1} 行没有可校验的文本');
      for (final Element e in texts) {
        final String content = (e.widget as Text).data ?? '';
        if (content.trim().isEmpty) continue; // 空占位不算
        final TextStyle s = (e.widget as Text).style!;
        expect(s.fontSize, AppTheme.listFontSize,
            reason: '$ctxInfo 第 ${i + 1} 行「$content」字号 ${s.fontSize}'
                ' ≠ 统一的 ${AppTheme.listFontSize}');
        expect(s.fontWeight, FontWeight.w400,
            reason: '$ctxInfo 第 ${i + 1} 行「$content」不应加粗');
        expect(s.fontFamily, AppTheme.monoFont,
            reason: '$ctxInfo 第 ${i + 1} 行「$content」字体族应为等宽');
      }
    }

    // ---- 约束 5：切换距离单位后仍单行 ----
    await settings.setDistanceUnit(
      settings.distanceUnit == DistanceUnit.metric
          ? DistanceUnit.imperial
          : DistanceUnit.metric,
    );
    await tester.pump();
    for (int i = 0; i < stations.length; i++) {
      expect(tester.getSize(tiles.at(i)).height, AppTheme.listRowHeight,
          reason: '$ctxInfo 下切换距离单位后第 ${i + 1} 行被撑高');
    }
  }

  testWidgets('列表行约束：常见屏 + 默认字号', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 360, textScale: 1.0);
  });

  testWidgets('列表行约束：小屏 + 系统字号 1.3x', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 320, textScale: 1.3);
  });

  testWidgets('列表行约束：系统字号 1.5x（用户反馈的典型场景）',
      (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 360, textScale: 1.5);
  });

  testWidgets('列表行约束：系统字号 2.0x（极端）', (WidgetTester tester) async {
    await verify(tester: tester, widthDp: 411, textScale: 2.0);
  });
}
