import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_info.dart';
import 'core/app_settings.dart';
import 'core/app_theme.dart';
import 'data/aprs_ingest.dart';
import 'data/station_store.dart';
import 'pages/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置（严格校验 / 演示模式 / 本机参考坐标）先加载好，避免启动时闪一下。
  final AppSettings settings = await AppSettings.load();

  runApp(
    EasyLocalization(
      // 默认中文；saveLocale: true 会把用户选择写进 SharedPreferences。
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh', 'CN'),
      startLocale: const Locale('zh', 'CN'),
      saveLocale: true,
      child: PkwdwplLiteApp(settings: settings),
    ),
  );
}

class PkwdwplLiteApp extends StatelessWidget {
  const PkwdwplLiteApp({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [

        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<StationStore>(
          create: (_) => StationStore(),
        ),
        // AprsIngest 依赖前两个：settings 变化（比如切演示模式）时热替换蓝牙服务。
        ChangeNotifierProxyProvider2<AppSettings, StationStore, AprsIngest>(
          create: (BuildContext ctx) => AprsIngest(
            settings: ctx.read<AppSettings>(),
            store: ctx.read<StationStore>(),
          ),
          update: (
            BuildContext ctx,
            AppSettings settings,
            StationStore store,
            AprsIngest? previous,
          ) =>
              (previous ??
                AprsIngest(settings: settings, store: store))
                ..syncWithSettings(),
        ),
      ],
      child: MaterialApp(
        title: AppInfo.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        onGenerateTitle: (BuildContext ctx) => ctx.tr('app.title'),
        home: const HomeShell(),
      ),
    );
  }

}
