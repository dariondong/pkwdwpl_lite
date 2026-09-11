import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/core/app_theme.dart';
import 'package:pkwdwpl_lite/data/station_store.dart';
import 'package:pkwdwpl_lite/main.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/models/geo_math.dart' show DistanceUnit;
import 'package:pkwdwpl_lite/widgets/station_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 界面改版（「一个信标一行 + 字体统一」）的硬性约束测试。
///
/// 三条约束：
///   1. **一个信标一行** —— 每个列表项高度固定 38，不会因为文字换行被撑高；
///   2. **字体统一** —— 所有列的字号都等于呼号的字号，呼号不加粗；
///   3. 切换到英制单位（MI）后仍然单行。
///
/// ⚠️ 三组断言刻意写在**同一个 testWidgets** 里：`EasyLocalization` 是单例，
///    同一个测试文件里第二次 `pumpWidget` 会挂不上 widget 树
///    （现象是 `find.byType(Scaffold)` 找不到任何东西，且没有报错信息），
///    排查这个坑花了不少时间，所以这里固定一个测试只 pump 一次。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 行高（与 StationTile 里的 SizedBox(height:) 必须一致）。
  const double rowHeight = 38;

  /// 用真实校验和拼一条 `$PKWDWPL` 语句。
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
    String date = '110926',
  }) {
    final String body = <String>[
      'PKWDWPL', time, status, latDm, 'N', lonDm, 'E',
      altitude, course, date, distance, callsign, icon,
    ].join(',');
    return r'$' '$body*${NmeaChecksum.format(NmeaChecksum.computeFrom(body))}';
  }

  testWidgets('列表：一个信标一行 + 字体统一 + 切英制仍单行', (WidgetTester tester) async {
    // 360x640 逻辑像素（较窄的手机，最容易挤爆）
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await AppSettings.load();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'CN'),
        startLocale: const Locale('zh', 'CN'),
        child: PkwdwplLiteApp(settings: settings),
      ),
    );

    // EasyLocalization 异步加载语言包，等主界面挂上
    for (int i = 0; i < 40 && find.byType(Scaffold).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(Scaffold), findsWidgets, reason: '主界面没有挂载成功');

    final BuildContext ctx = tester.element(find.byType(Scaffold).first);
    final StationStore store = Provider.of<StationStore>(ctx, listen: false);

    // 覆盖各种极端情况：长呼号、有/无航向、有/无距离、字段数异常
    store.addRawLine(sentence(
      callsign: 'BI4PGN-11', icon: '/i', time: '102339',
      latDm: '3958.55', lonDm: '11625.70',
    ));
    store.addRawLine(sentence(
      callsign: 'BG1UBU-9', icon: '/j', time: '102353', status: 'A',
      altitude: '4', course: '103', distance: '000050',
    ));
    store.addRawLine(sentence(
      callsign: 'BG1QGD-10', icon: '/&', time: '102921',
      latDm: '4000.46', lonDm: '11632.53',
    ));
    store.addRawLine(sentence(
      callsign: 'BH3BBJ-1', icon: '/r', time: '102627',
      latDm: '3907.80', lonDm: '11712.20', course: '359',
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(store.count, 4);
    final Finder tiles = find.byType(StationTile);
    expect(tiles, findsNWidgets(4));

    // ---- 约束 1：一个信标一行（行高固定，未被换行撑高）----
    for (int i = 0; i < 4; i++) {
      expect(
        tester.getSize(tiles.at(i)).height,
        rowHeight,
        reason: '第 ${i + 1} 行高度不是 $rowHeight（说明有字段换行/溢出）',
      );
    }

    // ---- 约束 2：字体统一（所有列字号 == 呼号字号，且不加粗）----
    final List<String> fields = <String>[
      '#2', // 序号
      'BG1UBU-9', // 呼号
      '--', // 方向（该行无航向时显示 --）
    ];
    final List<TextStyle> styles = <TextStyle>[];
    for (final String field in fields) {
      final Finder f = find.text(field);
      expect(f, findsWidgets, reason: '找不到字段「$field」');
      styles.add((f.evaluate().first.widget as Text).style!);
    }

    for (final TextStyle style in styles) {
      expect(style.fontSize, AppTheme.listFontSize,
          reason: '列表字段字号必须统一为 ${AppTheme.listFontSize}');
      expect(style.fontWeight, FontWeight.w400,
          reason: '呼号不得加粗（App 是记录日志用，不需要突出呼号）');
      expect(style.fontFamily, AppTheme.monoFont,
          reason: '列表统一等宽字体，保证固定列对齐');
    }

    // ---- 约束 3：切到英制后仍不换行 ----
    await Provider.of<AppSettings>(ctx, listen: false)
        .setDistanceUnit(DistanceUnit.imperial);
    await tester.pump();
    final int count = tiles.evaluate().length;
    for (int i = 0; i < count; i++) {
      expect(tester.getSize(tiles.at(i)).height, rowHeight,
          reason: '切换英制单位后第 ${i + 1} 行被撑高了');
    }
  });
}
