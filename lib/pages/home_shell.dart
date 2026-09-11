import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/aprs_ingest.dart';
import 'station_list_page.dart';

/// 主框架。
///
/// **没有底部导航**（按需求隐藏菜单）：启动即进台站列表，
/// 其余页面（连接 / 离线地图 / 关于 / 单位 / 语言 / 清空）
/// 全部收在右上角的「三个点」里。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
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

  @override
  Widget build(BuildContext context) => const StationListPage();
}
