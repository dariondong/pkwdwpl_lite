import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/main.dart';
import 'package:pkwdwpl_lite/pages/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App 能启动并显示主框架（台站/连接/关于）', (WidgetTester tester) async {
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

    // 注意：列表页有 10 秒周期的定时刷新，所以不能用 pumpAndSettle（永远不结束）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byIcon(Icons.radar), findsWidgets);
  });
}
