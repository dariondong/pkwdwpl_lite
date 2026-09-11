import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/core/app_theme.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/widgets/station_tile.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 压力渲染工具：在多种「屏宽 × 系统字号缩放」下渲染台站列表行，导出 PNG 供肉眼核对。
///
/// 为什么直接渲染 [StationTile] 而不是整个 App：
///   * StationTile 不依赖 easy_localization（不调 tr()），可以直接渲染；
///   * `EasyLocalization` 是单例，同一测试文件里第二次 `pumpWidget` 会挂不上树，
///     直接渲染组件就绕开了这个坑，能在一个测试里循环所有组合。
///
/// 非断言型工具，故意不叫 *_test.dart（不被 `flutter test` 默认选中）。
///
/// 运行：
///   flutter test test/tools/ui_stress_preview.dart
/// 产物：
///   build/ui_preview/stress_<宽>dp_x<缩放>.png
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

  const List<(double, double)> cases = <(double, double)>[
    (360, 1.0), // 常见 360dp 手机、默认字号
    (360, 1.5), // 系统字号 1.5x（用户反馈的场景）
    (360, 2.0), // 系统字号 2.0x（极端）
    (320, 1.0), // 小屏
  ];

  for (final (double widthDp, double scale) in cases) {
    testWidgets('stress ${widthDp}dp x$scale', (WidgetTester tester) async {
      tester.view.physicalSize = Size(widthDp * 3, 300 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final AppSettings settings = await AppSettings.load();

      final List<AprsStation> stations = <AprsStation>[
        AprsStationParser.parse(sentence(
          callsign: 'BG1UBU-9', icon: '/j', time: '102353', status: 'A',
          altitude: '4', course: '103', distance: '000050',
        )),
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

      final GlobalKey boundaryKey = GlobalKey();
      await tester.pumpWidget(
        // 用 MediaQuery 覆盖系统字号缩放，模拟用户在系统设置里放大字体
        MediaQuery(
          data: MediaQueryData(size: Size(widthDp, 300), textScaler: TextScaler.linear(scale)),
          child: ChangeNotifierProvider<AppSettings>.value(
            value: settings,
            child: RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(),
                home: Scaffold(
                  backgroundColor: Colors.white,
                  body: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      for (int i = 0; i < stations.length; i++)
                        StationTile(
                          station: stations[i],
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

      final RenderRepaintBoundary boundary =
          boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage();
        final ByteData? data =
            await image.toByteData(format: ui.ImageByteFormat.png);
        final Directory outDir = Directory('build/ui_preview');
        outDir.createSync(recursive: true);
        final File file = File(
            '${outDir.path}/stress_${widthDp.toInt()}dp_x${scale.toStringAsFixed(1)}.png');
        file.writeAsBytesSync(data!.buffer.asUint8List());
        // ignore: avoid_print
        print('已生成: ${file.absolute.path}');
      });
    });
  }
}
