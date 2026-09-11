import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/core/app_settings.dart';
import 'package:pkwdwpl_lite/data/aprs_bus.dart';
import 'package:pkwdwpl_lite/data/aprs_ingest.dart';
import 'package:pkwdwpl_lite/data/station_store.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/services/bluetooth_service.dart';
import 'package:pkwdwpl_lite/services/bluetooth_service_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端到端：模拟蓝牙服务 → 字节流 → 分帧 → 校验 → 解析 → 入库。
///
/// 覆盖了没有电台时最容易出错的部分（跨块分帧 + XOR 校验 + 同呼号覆盖置顶），
/// 所以 CI 上没有蓝牙硬件也能跑。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('演示数据源整条链路可用（含坏校验和被丢弃）', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await AppSettings.load();
    final StationStore store = StationStore();
    final MockBluetoothService service = MockBluetoothService(
      interval: const Duration(milliseconds: 20),
    );
    final AprsIngest ingest = AprsIngest(
      settings: settings,
      store: store,
      service: service,
    );

    expect(ingest.isDemo, isTrue);
    expect(ingest.stage, BluetoothStage.ready);

    // 顺便验证一下对外广播的 Stream（后台/其它界面就是靠它拿数据的）。
    final List<AprsStation> seen = <AprsStation>[];
    final StreamSubscription<AprsStation> subscription =
        AprsBus.stations.listen(seen.add);

    await ingest.connect(MockBluetoothService.demoPeer);
    expect(ingest.isConnected, isTrue);

    // 等几拍数据（每拍 6 个台站；每 9 拍一条坏校验和；每 13 拍一条丢逗号；每 5 拍重复上报）。
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // 演示台站用的是真实采集数据。
    expect(store.count, 6);
    expect(store.byCallsign('BG1UBU-9'), isNotNull);
    expect(store.byCallsign('BI4PGN-11'), isNotNull);
    expect(store.byCallsign('BY1BJ-1'), isNotNull);
    expect(store.byCallsign('BH3BBJ-1'), isNotNull);
    expect(store.byCallsign('BI1AR-1'), isNotNull);
    expect(store.byCallsign('BG1QGD-10'), isNotNull);

    // 坏校验和被严格模式丢弃并计数
    expect(store.stats.checksumFailed, greaterThanOrEqualTo(1));
    expect(store.stats.lines, greaterThan(store.stats.accepted));

    // 丢逗号的语句被容错解析入库，并计入「存疑」
    // （注意：同一呼号后续还会收到正常语句并覆盖，所以这里断言「流里出现过」
    //   而不是断言某呼号的最终记录仍然是异常字段数。）
    expect(store.stats.flagged, greaterThanOrEqualTo(1));
    expect(seen.any((AprsStation s) => s.fieldCountAnomaly), isTrue);
    expect(seen.any((AprsStation s) => s.parsedFieldCount == 10), isTrue);
    await subscription.cancel();

    // 接收序号：等于成功入库的语句数，且每条都 >0
    expect(store.sequence, store.stats.accepted);
    for (final AprsStation station in store.stations) {
      expect(station.receiveSeq, greaterThan(0));
    }

    // 空字段（真实报文里海拔/航向/距离为空）能正确落地
    final AprsStation? pgn = store.byCallsign('BI4PGN-11');
    expect(pgn!.distanceMeters, isNull);
    expect(pgn.statusValid, isFalse);

    // 移动台站的坐标确实在变（说明分帧/解析都在跑）。
    expect(store.byCallsign('BG1QGD-10')!.latitude, closeTo(40.00767, 0.05));

    await ingest.disconnect();
    expect(ingest.isConnected, isFalse);
    ingest.dispose();
  });

  test('打开演示模式会热替换底层蓝牙服务', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final AppSettings settings = await AppSettings.load();
    final StationStore store = StationStore();
    final _FakeService fake = _FakeService();
    final AprsIngest ingest = AprsIngest(
      settings: settings,
      store: store,
      service: fake,
    );

    expect(ingest.isDemo, isFalse);
    expect(ingest.service, same(fake));

    await ingest.setDemoMode(true);

    // 已热替换：旧服务被 dispose，换成模拟服务。
    expect(ingest.isDemo, isTrue);
    expect(ingest.service, isNot(same(fake)));
    expect(fake.disposed, isTrue);

    // 换成模拟服务后连接能成功（数据链路本身由上面的用例覆盖）。
    await ingest.connect(MockBluetoothService.demoPeer);
    expect(ingest.stage, BluetoothStage.connected);
    expect(ingest.activePeer, MockBluetoothService.demoPeer);

    await ingest.disconnect();
    expect(ingest.isConnected, isFalse);

    ingest.dispose();
  });
}

/// 假的「平台」实现，用来验证热替换逻辑（不会碰任何插件）。
class _FakeService extends BluetoothService {
  bool disposed = false;

  @override
  BluetoothStage get stage => BluetoothStage.ready;

  @override
  List<BluetoothPeer> get peers => const <BluetoothPeer>[];

  @override
  BluetoothPeer? get activePeer => null;

  @override
  String? get lastError => null;

  @override
  Future<void> refreshPeers() async {}

  @override
  Future<bool> requestEnable() async => true;

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<void> connect(BluetoothPeer peer) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(String ascii) async {}

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
