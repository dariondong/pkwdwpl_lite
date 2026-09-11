import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/data/station_store.dart';
import 'package:pkwdwpl_lite/main.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把主界面真实渲染成 PNG，用于**人工核对界面改版效果**。
///
/// 它不是断言型测试，而是一个开发辅助工具，所以**故意不叫 `*_test.dart`** ——
/// 否则会被 `flutter test` 默认选中并跑在 CI 里。原因有二：
///   1. 测试环境没有中文字体，渲染出来全是方块，看截图才有意义；
///   2. 导出 PNG 需要在 `tester.runAsync` 里做，混在普通断言测试里容易在退出时
///      报 `Bad state: Cannot close sink while adding stream`，把 CI 拖红。
///
/// 运行（需要显式指定路径）：
///   flutter test test/tools/ui_preview.dart
/// 产物：
///   build/ui_preview/list_page.png
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final GlobalKey boundaryKey = GlobalKey();

  /// 用真实校验和拼一条语句，灌进 store。
  String sentence({
    required String callsign,
    required String icon,
    required String time,
    required String status,
    required String latDm,
    required String lonDm,
    String altitude = '',
    String course = '',
    String distance = '',
    String date = '110926',
  }) {
    final String body = <String>[
      'PKWDWPL',
      time,
      status,
      latDm,
      'N',
      lonDm,
      'E',
      altitude,
      course,
      date,
      distance,
      callsign,
      icon,
    ].join(',');
    return r'$' '$body*${NmeaChecksum.format(NmeaChecksum.computeFrom(body))}';
  }

  testWidgets('渲染主界面预览图', (WidgetTester tester) async {
    // 手机尺寸（逻辑像素 360 x 640）
    tester.view.physicalSize = const Size(1080, 1280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await AppSettings.load();

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: EasyLocalization(
          supportedLocales: const <Locale>[
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          path: 'assets/translations',
          fallbackLocale: const Locale('zh', 'CN'),
          startLocale: const Locale('zh', 'CN'),
          child: PkwdwplLiteApp(settings: settings),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 灌入数据（真实采集过的台站，含一条空字段、一条字段数异常）
    final BuildContext ctx = tester.element(find.byType(Scaffold).first);
    final StationStore store = Provider.of<StationStore>(ctx, listen: false);

    store.addRawLine(sentence(
      callsign: 'BG1UBU-9', icon: '/j', time: '102353', status: 'A',
      latDm: '3955.09', lonDm: '11616.91',
      altitude: '4', course: '103', distance: '000050',
    ));
    store.addRawLine(sentence(
      callsign: 'BI4PGN-11', icon: '/i', time: '102339', status: 'V',
      latDm: '3958.55', lonDm: '11625.70',
    ));
    store.addRawLine(sentence(
      callsign: 'BY1BJ-1', icon: '/r', time: '102439', status: 'V',
      latDm: '4000.30', lonDm: '11610.16',
    ));
    store.addRawLine(sentence(
      callsign: 'BH3BBJ-1', icon: '/r', time: '102627', status: 'V',
      latDm: '3907.80', lonDm: '11712.20',
    ));
    store.addRawLine(sentence(
      callsign: 'BG1QGD-10', icon: '/&', time: '102921', status: 'V',
      latDm: '4000.46', lonDm: '11632.53',
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 导出 PNG。toImage / toByteData 是真正的异步 I/O，必须放在 runAsync 里，
    // 否则会在测试退出阶段抛 "Cannot close sink while adding stream"。
    final RenderRepaintBoundary boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;

    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      final Directory outDir = Directory('build/ui_preview');
      outDir.createSync(recursive: true);
      final File file = File('${outDir.path}/list_page.png');
      file.writeAsBytesSync(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('预览图已生成: ${file.absolute.path}');
    });
  });

  // 说明：关于页没有放预览图。
  //   它的内容（作者 BG7LZQ / 协议 BH7NOR / 支持 BA3RZL / 推荐 APRSLocus 三个链接）
  //   已由 test/about_page_test.dart 用断言覆盖，比截图更可靠。
  //   这里只保留「列表页」的预览 —— 当初就是靠它渲染出时间列/方向列被竖向折行、
  //   破坏了「一行一信标」的问题，是唯一真正需要肉眼核对布局的页面。
}
