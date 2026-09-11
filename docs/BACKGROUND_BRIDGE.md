# 与「后台保活架构」对接指南

前提：你现有的项目已经有一套后台保活/前台服务架构。
下面的方案不需要你改架构，只要把三件事接上：**谁持有蓝牙**、**数据往哪送**、**UI 怎么拿**。

---

## 0. 一句话版本

* 蓝牙必须由**主 Isolate**（有 FlutterEngine 的那个）持有 —— 插件走 MethodChannel/EventChannel。
* 你的后台服务只需要保证「主 Isolate 里那个 `AprsIngest`（或你自己的等价物）活着」，
  收到的数据会自动进入 `StationStore` 并通过 `AprsBus` 广播出去。
* UI 侧：`context.watch<StationStore>()` 拿列表，`context.watch<AprsIngest>()` 拿连接状态。

---

## 1. 数据流的三个出口

```text
BluetoothService.bytes ──► NmeaLineSplitter ──► StationStore.addRawLine()
   (原始字节流)                (按行分帧)              │
                                                      ├─► ChangeNotifier  → Provider → UI
                                                      └─► AprsBus.stations → 任意订阅者
```

三种接入姿势，按侵入性从小到大：

### 姿势 A：直接用现成的（推荐，零改造）

```dart
// 你的保活服务里，只要保证 AprsIngest 实例不被回收：
final ingest = context.read<AprsIngest>();
await ingest.bootstrap();          // 订阅蓝牙开关 / 申请权限 / 拉取已配对设备
await ingest.connect(peer);        // 连接电台

// 断线自动重连（比如 5 秒后重试）：
ingest.service.bytes.listen(
  null,
  onDone: () => Timer(const Duration(seconds: 5), () => ingest.connect(peer)),
);
```

### 姿势 B：只借它的解析能力（你的架构持有蓝牙）

```dart
// 你在自己的后台服务里收字节：
final splitter = NmeaLineSplitter();
void onBytes(Uint8List chunk) {
  for (final line in splitter.addBytes(chunk)) {
    store.addRawLine(line, strictChecksum: settings.strictChecksum);
  }
}
```

### 姿势 C：连 store 都不要（纯函数复用）

```dart
final result = AprsStationParser.tryParse(line);   // 纯 Dart，无副作用
if (result.isSuccess) myRepository.save(result.station!);
```

---

## 2. 跨 Isolate / 后台线程

经典蓝牙插件依赖 FlutterEngine，**不能**在纯 Dart 后台 Isolate 里调用
（会抛 `MissingPluginException`）。所以：

| 场景 | 建议做法 |
| --- | --- |
| 前台服务（Android Service）里跑 Flutter | 用 `FlutterEngine` + 该 Engine 上注册的插件收发蓝牙；此时那个 Engine 的 Isolate 就是「主 Isolate」 |
| 已有独立后台 Isolate 做解析/落盘 | 主 Isolate 收到数据后，用 `SendPort` / 你现有的通道把**已经分帧好的字符串**发过去解析 |
| 只想让 UI 拿到数据 | 用 `AprsBus.stations`（`StreamController.broadcast`），主 Isolate 内跨页面零成本 |

如果要跨 Isolate 传对象，别传 `AprsStation`（有 `IconData`），传 `station.toJson()`
（已经是纯 `Map<String, dynamic>`，可 `jsonEncode`）+ 在另一侧 `AprsStation.fromJson()`。

---

## 3. 生命周期建议

```text
App 启动
  └─ AppSettings.load()            设置先就绪（严格校验/演示模式/参考坐标）
  └─ HomeShell.initState()
        └─ AprsIngest.bootstrap()  ← 权限 + 已配对设备
               └─ 用户点连接 → BluetoothService.connect()
                      └─ bytes 流 → StationStore（UI 自动刷新）

App 退到后台（有保活）
  └─ 保持 AprsIngest / StationStore 实例存活即可
     （它们没有依赖 Widget 生命周期；Widget 树重建不影响收数据）

App 被杀
  └─ 由你现有的保活方案决定是否重启前台服务；重启后：
        - 台站台账是内存态（如需保留，见 README「后续可做」用 toJson 落盘）
        - 蓝牙需要重新 connect()
```

---

## 4. 断线/异常的处理面

* `BluetoothService.lastError`：原始错误串（界面直接显示在「最近错误」卡片）。
* `BluetoothService.stage`：`unavailable / off / unauthorized / ready / connecting / connected`，
  界面文案在 `assets/translations/*.json` 的 `connect.state.*`。
* `bytes` 流的 `onDone`/`onError`：远端断开或读取失败时触发，
  适合挂上你现有的重连策略（指数退避等）。
* 解析层的错误**不会**中断链路：`StationStore.addRawLine` 只是计数 + 打印告警，
  统计结果反映在列表页顶部（有效 / 校验失败 / 格式错误）。

---

## 5. 想替换掉我写的服务实现

`BluetoothService` 是抽象类，最小实现只要这些：

```dart
class MyBluetoothService extends BluetoothService {
  @override BluetoothStage get stage => ...;
  @override List<BluetoothPeer> get peers => ...;
  @override BluetoothPeer? get activePeer => ...;
  @override String? get lastError => ...;
  @override Future<void> refreshPeers() async {...}
  @override Future<bool> requestEnable() async {...}
  @override Future<bool> ensurePermissions() async {...}
  @override Future<void> connect(BluetoothPeer peer) async {...}
  @override Future<void> disconnect() async {...}
  @override Future<void> send(String ascii) async {...}
  // 收到数据时调用 emitBytes(Uint8List/List<int>) 即可
}
```

然后注入：

```dart
AprsIngest(settings: settings, store: store, service: MyBluetoothService());
```

测试里就是这么干的（见 `test/aprs_ingest_test.dart` 的 `_FakeService`），
所以你也可以在 CI 上用一个假实现跑通整条链路，不需要硬件。

---

## 6. 演示模式（强烈建议保留）

连接页的「演示模式」把底层服务换成 `MockBluetoothService`：
它按真实格式拼语句（校验和真算），每 3 秒推 3 个台站，
每 9 拍混一条坏校验和语句。用途：

* CI 出的 APK 发给别人（或你自己）先看界面效果；
* 改 UI 时不用开着电台；
* 验证「校验失败计数」「覆盖置顶」「相对时间刷新」这些容易回归的地方。

集成到你项目里时，只要保留 `createBluetoothService({bool forceMock})` 这个工厂即可。
