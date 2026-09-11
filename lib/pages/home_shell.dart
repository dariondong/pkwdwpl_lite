import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/aprs_ingest.dart';
import '../data/station_store.dart';
import 'about_page.dart';
import 'bluetooth_page.dart';
import 'station_list_page.dart';

/// 主框架：底部三个 tab（台站 / 连接 / 关于）。
///
/// 「台站列表」是主页面（需求里的页面 2），App 启动即停在这里；
/// 详情页从列表 push 进去（页面 3），因此不在 tab 里。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 初始化蓝牙：订阅开关状态、申请权限、拉取已配对设备。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 忽略初始化异常，错误会体现在连接页的 lastError 上。
      context.read<AprsIngest>().bootstrap();
    });
  }

  void _select(int index) {
    if (_index != index) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final int stationCount = context.select<StationStore, int>((StationStore s) => s.count);

    final List<Widget> pages = <Widget>[
      StationListPage(onOpenConnect: () => _select(1)),
      BluetoothPage(onOpenStations: () => _select(0)),
      const AboutPage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: <Widget>[
          NavigationDestination(
            icon: const Icon(Icons.radar_outlined),
            selectedIcon: Badge(
              isLabelVisible: stationCount > 0,
              label: Text('$stationCount'),
              child: const Icon(Icons.radar),
            ),
            label: context.tr('nav.stations'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bluetooth_outlined),
            selectedIcon: const Icon(Icons.bluetooth),
            label: context.tr('nav.connect'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.info_outline),
            selectedIcon: const Icon(Icons.info),
            label: context.tr('nav.about'),
          ),
        ],
      ),
    );
  }
}
