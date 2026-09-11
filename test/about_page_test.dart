import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_info.dart';
import 'package:pkwdwpl_lite/pages/about_page.dart';

/// 关于页的内容要求（需求 1 + 后续追加）：
///   * App 名称 / 版本
///   * 作者 **BG7LZQ**
///   * 技术接口协议提供者 **BH7NOR**
///   * 支持 **BA3RZL**
///   * **推荐作者的另一款作品 APRSLocus**（官网 / 下载 / 源码 三个可点链接）
///
/// ⚠️ 全部断言写在同一个 testWidgets 里 —— `EasyLocalization` 是单例，
///    同一文件里第二次 `pumpWidget` 会挂不上 widget 树。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('关于页：作者/协议/支持者/推荐 APRSLocus 都在', (WidgetTester tester) async {
    // 视口故意设得很高（逻辑 360 x 2400），让整个关于页一次全部可见。
    // 这样就不用 dragUntilVisible —— ListView 是懒构建的，
    // 屏幕外的卡片根本还没 build，滚动查找会很坑。
    tester.view.physicalSize = const Size(1080, 7200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('zh', 'CN'),
        startLocale: const Locale('zh', 'CN'),
        // 必须像真实 App 那样把 easy_localization 的 delegates 装到 MaterialApp 上，
        // 否则 context.tr 会抛 LocalizationNotFoundException。
        child: Builder(
          builder: (BuildContext context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const AboutPage(),
          ),
        ),
      ),
    );
    for (int i = 0; i < 40 && find.byType(AboutPage).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AboutPage), findsOneWidget);

    // ① 作者 / 协议提供者（需求 1）
    expect(find.text('BG7LZQ'), findsOneWidget, reason: '缺少作者 BG7LZQ');
    expect(find.text('BH7NOR'), findsOneWidget, reason: '缺少协议提供者 BH7NOR');

    // ② 支持：BA3RZL
    expect(find.text('BA3RZL'), findsOneWidget, reason: '缺少支持者 BA3RZL');
    expect(find.textContaining('支持'), findsWidgets, reason: '缺少「支持」标签');

    // ③ App 名称与版本
    expect(find.text(AppInfo.appName), findsWidgets);
    expect(find.text(AppInfo.versionLabel), findsOneWidget);

    // ④ 推荐 APRSLocus（滚到底部才可见）
    // 卡片里 App 名与副标题在同一个 Text 中（"APRSLocus · APRS 定位追踪与地图"），
    // 所以用 textContaining 而不是 text。
    // （「APRSLocus」在卡片标题与 GitHub 链接中都会出现，故用 findsWidgets）

    expect(find.textContaining(AppInfo.relatedAppName), findsWidgets,
        reason: '缺少推荐的 APRSLocus');

    // 三个链接（显示时会去掉 https:// 前缀）
    String shown(String url) => url.replaceFirst(RegExp(r'^https?://'), '');
    expect(find.text(shown(AppInfo.relatedAppWebsite)), findsOneWidget,
        reason: '缺少官网链接');
    expect(find.text(shown(AppInfo.relatedAppReleases)), findsOneWidget,
        reason: '缺少下载链接');
    expect(find.text(shown(AppInfo.relatedAppRepository)), findsOneWidget,
        reason: '缺少源码链接');
  });
}
