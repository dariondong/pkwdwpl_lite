import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/main.dart';
import 'package:pkwdwpl_lite/pages/station_list_page.dart';
import 'package:pkwdwpl_lite/widgets/station_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主界面改版后的冒烟测试：启动即列表页，**没有底部导航**，
/// 菜单全部收进右上角「三个点」。
///
/// ⚠️ 所有断言写在同一个 testWidgets 里：`EasyLocalization` 是单例，
///    同一文件里第二次 `pumpWidget` 会挂不上树（现象：找不到 Scaffold 且无报错）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('启动进入台站列表；无底部导航；菜单收进右上角三个点', (WidgetTester tester) async {
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

    // 等语言包加载、主界面挂上（注意：列表页有 10 秒周期定时刷新，
    // 所以不能用 pumpAndSettle —— 永远不会结束）。
    for (int i = 0; i < 40 && find.byType(Scaffold).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 主页面就是台站列表
    expect(find.byType(StationListPage), findsOneWidget);

    // 需求：不要底部切换图标
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);

    // 需求：菜单藏进右上角「三个点」
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // 空列表时还没有任何列表项
    expect(find.byType(StationTile), findsNothing);

    // 点开菜单，应有：连接 / 离线地图 / 距离单位 / 语言 / 关于
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 400));

    // 注意：「连接」会同时出现在菜单项与空列表的引导按钮上，所以用 findsWidgets
    expect(find.text('连接'), findsWidgets, reason: '菜单缺少「连接」');
    expect(find.text('离线地图'), findsOneWidget, reason: '菜单缺少「离线地图」');
    expect(find.text('关于'), findsOneWidget, reason: '菜单缺少「关于」');
    expect(find.textContaining('距离单位'), findsOneWidget, reason: '菜单缺少「距离单位」');
    expect(find.textContaining('语言'), findsOneWidget, reason: '菜单缺少「语言」');
  });
}
