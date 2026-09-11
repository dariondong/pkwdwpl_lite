# PKWDWPL Lite

> 蓝牙串口（Classic Bluetooth SPP）接收 Kenwood `$PKWDWPL` NMEA 语句的 APRS 台站接收 / 台账 App。
>
> * **App 名称**：PKWDWPL Lite
> * **作者 / 开发者**：**BG7LZQ**
> * **技术接口协议提供者**：**BH7NOR**
> * **数据协议**：Kenwood `$PKWDWPL`（NMEA 0183，14 字段，`\r\n` 结尾）
> * **平台**：Android（Flutter，API 23+）
> * 包名 / applicationId：`top.theez.pkwdwpl_lite`（可按需改）

---

## 1. 已在本机验证过的内容

```bash
flutter pub get
flutter analyze     # → No issues found!
flutter test        # → 62 个测试全部通过
```

特别地：`test/real_capture_test.dart` 把 **BH7NOR 采集的 10 条真实 `$PKWDWPL` 报文**
原样入库，用来防止解析逻辑被改坏。开发过程中就是靠它定位出：

* 校验算法本身正确（7/10 通过；权威示例 `$GPGGA...*47` 也能算对）；
* 3 条不通过的是**采集手误**，其中 2 条已能证明原值是什么（见 `docs/PROTOCOL.md` 第 2 节）；
* **真实数据里字段数可以是 10 / 11 / 12 三种** → 必须容错解析，否则会白丢数据；
* 一个真 bug：`decimalToDm` 的「分」没补两位（`39.13°` 被写成 `397.80`）。

CI 上没有蓝牙硬件也能跑（演示模式用的是真实台站数据 + 真算的校验和）。

---

## 1.5 APRS 官方符号图标包（从 APRSLocus 移植）

列表/详情/地图上的台站图标**优先用 APRS 官方符号 PNG**，而不是 Material 图标：

| | |
| --- | --- |
| 来源 | **APRSLocus 项目** 的 `assets/aprs_syms/`（由它的 `tools/download_aprs_icons.py` 从 `https://aprs.tv/img/` 抓取） |
| 内容 | **3572 张 PNG**，APRS 官方 **38 个符号表** × 符号码 `0x21`~`0x7E`（完整覆盖） |
| 单张 | **24 × 24 px**（RGBA）——官方素材只有这一种尺寸，放大到 ~48px 以上会发虚 |
| 命名 | `<hex(表)><hex(码)>.png`，如 `2f6a.png` = `/j`、`2f72.png` = `/r` |
| 体积 | 实际 **2.4 MB**（会增加一点安装包体积，但比想象中小很多） |
| 许可 | 随 APRSLocus 以 **GPL-3.0** 分发 → 本仓库也是 GPL-3.0，详见 `NOTICE` |

用法（UI 里不需要关心回退逻辑）：

```dart
AprsSymbolIcon(icon: station.iconRaw, size: 28)  // 官方 PNG，缺失时自动回退 Material 图标
AprsSymbolAssets.assetPathFor('/j')              // → 'assets/aprs_syms/2f6a.png'
station.iconAsset                                // 解析结果上直接取（可能为 null）
station.hasOfficialIcon                          // 是否能用官方图标
```

离线地图的画布是同步绘制的，所以用 `AprsSymbolImageCache` 把 PNG 预解码成 `ui.Image`
（进入地图页时预热一次）；**没有图标包或解码未完成时自动退化成圆点**，不会空图。

维护：`python3 tool/update_aprs_symbols.py`（联网补齐，已验证会自动补上 APRSLocus 缺失的
`5541.png`）或 `python3 tool/update_aprs_symbols.py --from /path/to/APRSLocus`（从本地项目复制）。

### 启动图标（launcher）

启动图标也换成了 APRS 符号美术：**白底 + 品牌绿描边 + `/j` 汽车**，由
`tool/gen_launcher_icon.py` 生成 48/72/96/144/192 五档：

```bash
python3 tool/gen_launcher_icon.py                       # 默认：白底 + 绿环 + /j 汽车
python3 tool/gen_launcher_icon.py --symbol 2f72        # 换成 /r 中继塔
python3 tool/gen_launcher_icon.py --bg green --no-ring # 换成绿底
```

**为什么不直接用绿底？** `/j` 汽车、`/#` 中继这些 APRS 符号本身就是**绿色**的，
放在品牌绿（`#2E7D32`）上对比度极低、远看糊成一团（已做多方案对照验证）。
白底 + 绿描边既保证符号清楚，又保留品牌色。

测试：`test/aprs_symbol_assets_test.dart` 会**真的去磁盘上校验**——3572 个文件、
命名全为 `[0-9a-f]{4}.png`、38 个符号表齐全、关键图标 PNG magic bytes 正确，
以及「10 条真实报文的图标都能在包里找到文件」。

---

## 2. 界面与交互（按需求定制）

底部三个 tab：**台站（主页）· 连接 · 关于**；详情页与离线地图从列表进入。

### 台站列表（主页）

每一行的格式就是需求里要的那份：

```
 #序号 | 图标 | 呼号 | 方向 | 距离(KM/MI) | 接收时间
  #12  |  🚗  | BG1UBU-9  |  ↑83°  | 52.0 km · 10:23:53
```

* **接收序号**：第几条成功解析的语句（和串口日志逐条对齐用）；
* **图标**：APRS 官方符号 PNG（来自图标包，见 1.5 节），缺失时回退 Material 图标；
* **方向**：按航向旋转的箭头 + 度数（无航向显示 `--`）；
* **距离**：AppBar 右上角一个 **KM ⇄ MI** 按钮实时切换；
  若设置了本机参考坐标，距离用 Haversine 实算并加 `*` 标注，否则显示报文第 11 字段；
* **接收时间**：`HH:mm:ss`（本地时区）；
* **单击 → 详情页**；**双击 → 离线地图并把该台站居中**（需求原文：double-tap 跳转并居中）；
* 顶部统计条：台站数 / 有效 / 校验失败 / 格式错误 / 存疑，以及筛选（全部 · 仅有效 · 仅存疑）。

### 台站详情（台账）

呼号、APRS 图标、状态、十进制经纬度、海拔、方向、距离（含来源标注）、
字段 11 原值 + 当前解释、日期时间（UTC 原文 + 本地时间）、
**字段数**、校验和（收到 vs 计算）、呼号格式检查、
**14 字段逐项分解**（空字段显示「␀（空）」）、底部原始 NMEA 语句（可复制）。
有问题的数据会在顶部弹出「数据质量提示」条。

### 离线地图（双击进入）

* **完全离线、不需要 GPS、不联网**；
* 底图三种来源，按优先级：
  1. 设置里指定的本地图片绝对路径（`Image.file`）；
  2. App 内置的 `assets/map/offline_map.png`（放进去即生效）；
  3. 都没有 → 程序绘制**经纬网格 + 比例尺 + 全部台站点位**（开箱即用）；
* 经纬范围：设置里可手填锁定，否则按「全部台站 + 本机参考坐标」自动生成；
* 进入时把目标台站**居中**（`InteractiveViewer` 的变换矩阵直接算到视口中心），
  可缩放/拖动，点击任意点位即切换居中目标，右上角可重置视图。

### 省电设计（需求：不要打开手机 GPS）

* **不申请定位权限、不开 GPS**；
* 距离优先用「本机参考坐标」（用户手填，或由你现有的定位模块调用
  `AppSettings.setReferencePosition(lat, lon)` 写入），没有就退回报文里的字段 11；
* 台站坐标全部来自蓝牙报文，不需要任何系统定位服务。

---

## 3. 目录结构

```
pkwdwpl_lite/
├── android/                        # Kotlin DSL，AGP 9.1 / Gradle 9.3.1
│   ├── app/build.gradle.kts        # ★ 签名（key.properties 优先，环境变量/debug 兜底）
│   ├── app/src/main/AndroidManifest.xml   # ★ 蓝牙权限 / 后台保活权限
│   ├── gradle.properties           # 调小 JVM 内存，避免 CI OOM
│   └── key.properties.example
├── assets/
│   ├── translations/{zh-CN,en-US}.json    # ★ 多语言（默认中文）
│   └── map/README.txt              # 离线地图底图目录（放 offline_map.png 即生效）
├── lib/
│   ├── core/
│   │   ├── app_info.dart           # ★ 版本 / 作者 BG7LZQ / 协议 BH7NOR
│   │   ├── app_settings.dart       # 严格校验、演示模式、单位、字段11语义、地图
│   │   ├── formats.dart            # 距离（含单位与来源）/方向/时间格式化
│   │   └── l10n.dart               # 中英切换 + 错误文案
│   ├── models/
│   │   ├── aprs_station.dart       # ★ 14 字段解析 + XOR 校验 + 容错定位
│   │   ├── aprs_icon.dart          # ★ APRS 图标 → Material Icon
│   │   ├── geo_math.dart           # 度分换算 + Haversine + 单位格式化
│   │   └── map_bounds.dart         # 经纬范围 / 投影 / 自动范围
│   ├── data/
│   │   ├── nmea_line_splitter.dart # ★ 跨块分帧
│   │   ├── station_store.dart      # ★ 呼号为 Key、覆盖置顶、序号、筛选、统计
│   │   ├── aprs_ingest.dart        # ★ 字节流 → 分帧 → 解析 → 入库
│   │   └── aprs_bus.dart           # ★ 广播 Stream（给后台/其它界面）
│   ├── services/
│   │   ├── bluetooth_service.dart        # 抽象层（状态 + 设备 + 字节流）
│   │   ├── bluetooth_service_io.dart     # Android 实现（经典蓝牙 SPP）
│   │   ├── bluetooth_service_mock.dart   # 演示数据源（真实台站数据）
│   │   └── bluetooth_service_factory.dart
│   ├── pages/
│   │   ├── home_shell.dart         # 底部 tab
│   │   ├── bluetooth_page.dart     # 页面 1：蓝牙连接页 + 设置
│   │   ├── station_list_page.dart  # 页面 2：台站列表（主页面）
│   │   ├── station_detail_page.dart# 页面 3：台站详情（台账）
│   │   ├── offline_map_page.dart   # 页面 5：离线地图（双击进入，居中对齐）
│   │   └── about_page.dart         # 页面 4：关于
│   └── main.dart
├── test/                           # 62 个测试（含真实报文回归）
├── third_party/flutter_bluetooth_serial_plus/   # ★ 内置蓝牙插件（已打 CI 兼容补丁）
├── tool/{gen_keystore.py, set_github_secrets.py, sync_version.py, update_vendored_plugin.py}
├── tool/{gen_launcher_icon.py, update_aprs_symbols.py}
├── docs/PROTOCOL.md                # ★ 协议 + 真实报文复算 + 字段数/字段11 结论
├── docs/BACKGROUND_BRIDGE.md       # ★ 与你的后台保活架构对接方案
└── .github/workflows/{ci,release}.yml
```

---

## 4. 本地怎么跑

```bash
flutter --version           # 建议 3.47.3（CI 锁定同版本）
flutter pub get
flutter run                 # 真机；打开「演示模式」不用电台也能看界面
flutter test
flutter build apk --release # 没配置签名会自动回退 debug 签名，先跑通流程
```

**演示模式**用的是真实采集的 6 个台站（`BG1UBU-9`、`BI4PGN-11`、`BY1BJ-1`、
`BH3BBJ-1`、`BI1AR-1`、`BG1QGD-10`），并且每 9 拍混一条**坏校验和**、
每 13 拍混一条**丢逗号的 10 字段**语句、每 5 拍**重复上报**一个台站 ——
用来验证「严格模式丢弃 / 容错解析 / 覆盖置顶 / 存疑标记」这些容易回归的地方。

---

## 5. ⚠️ 关于校验和：算法没问题，原始示例和 10 条真机数据里有 3 条手误

需求文档给的示例：

```
$PKWDWPL,102202,M,3954.98,N,11616.63,E,7,83,290625,000052,BG1UBU-9,/j*35
```

按 NMEA 0183 计算应为 **`2E`**，不是 `35`。
而 BH7NOR 采集的 10 条真机数据里，**7 条校验和完全吻合**（说明算法与设备一致），
3 条不吻合的全部是**采集手误**：

| 报文 | 说明 | 证据 |
| --- | --- | --- |
| `...BG1UB9,/j*0C` | 呼号抄漏 | 改成 `BG1UBU-9` 后计算值正好 **0C** |
| `...E,,290625,,BY1BJ-1,/r*4E` | 漏了一个逗号 | 补成 `E,,,290625` 后正好 **4E** |
| `...BI4PGN1-1,/i*24` | 单字符被替换（差 0x03） | 无法反推原值 → 标记「需复核」 |

所以**默认严格模式**（校验不符即丢弃 + 控制台 `[PKWDWPL] ⚠ 丢弃语句 (...)`）是对的；
连接页可以临时关掉，关掉后这类记录仍会入库但会标红「校验不符」。
另外要记住 **XOR 查不出字符换位**（`BI4PGN1-1` 与 `BI4PGN-11` 的 XOR 相同），
所以解析器额外做了「字段数 / 坐标合法性 / 呼号格式」三层兜底检查。

细节与复算表格见 **`docs/PROTOCOL.md`**。

---

## 6. 数据流与架构（怎么接到你现有的保活架构里）

```text
BluetoothService.bytes          原始字节（Uint8List 流，主 Isolate）
        │
        ▼
NmeaLineSplitter                跨块分帧 → 完整语句（兼容 \r\n、\n、\r）
        │
        ▼
StationStore.addRawLine()       XOR 校验 → 容错字段定位 → AprsStation
        │                        呼号为 Key 写入 Map（同呼号覆盖并置顶）
        ├──────────────► AprsBus.stations （广播 Stream<AprsStation>）
        └──────────────► ChangeNotifier  → UI（Provider 自动刷新）
```

* **主 Isolate 持有蓝牙连接**：`AprsIngest` 就是那个持有者，
  UI 只 `context.watch` 状态，不碰蓝牙细节；
* **不需要 UI 也能收数据**：在你的后台服务里直接
  `StationStore.addRawLine(line)`，或监听 `AprsBus.rawLines`；
* **完全不想用我的类**：`AprsStationParser.tryParse(line)` 是纯函数，
  引 `models/` 两个文件就能复用解析与图标映射。

对接细节（前台服务、Isolate、断线重连、替换服务实现）见 **`docs/BACKGROUND_BRIDGE.md`**。

---

## 7. 蓝牙库选型与 Java 17 / Gradle 8+ 兼容方案（重点）

`flutter_bluetooth_serial`（2021 年最后一版 0.4.0）在新工具链下有两类问题：
缺 `namespace`（AGP 7.3+ 报错）、用了 `jcenter()`/`compileSdkVersion 30` 等老写法。

本项目把在维护的 fork `flutter_bluetooth_serial_plus 0.5.6` **内置到 `third_party/`**
并打上三个补丁（见该目录 `README_LOCAL.md`）：

| 补丁 | 原因 |
| --- | --- |
| 删除插件自带的 `buildscript { classpath 'com.android.tools.build:gradle:8.1.1' }` | 与宿主工程的 **AGP 9.1.0** 冲突，CI 上极难排查 |
| `compileSdk 36` + `JavaVersion.VERSION_17` | 与 Flutter 3.47 模板、JDK 17 对齐 |
| 精简 `AndroidManifest.xml` | 上游把 `FlutterPlugin` 写成 `<activity>`，合并时会注入 `largeHeap` 与 `Theme.AppCompat.NoActionBar`，污染宿主主题 |

`pubspec.yaml` 用 `path:` 引用，编译结果可复现，上游发新版也不会突然把 CI 弄挂。
Dart API 与上游 100% 一致；想换回 pub.dev 官方包改一行注释即可。

---

## 8. Android 配置要点

* SDK 版本（`android/app/build.gradle.kts`）：

  ```kotlin
  compileSdk = flutter.compileSdkVersion   // Flutter 3.47 = 36
  minSdk     = flutter.minSdkVersion
  targetSdk  = flutter.targetSdkVersion    // Flutter 3.47 = 36
  ```

  满足「至少 API 34」的要求，并且用 `check()` 把这条钉死：
  一旦将来 Flutter 把默认值降到 34 以下，配置阶段会立刻报错，而不是静默失守。

  > ⚠️ **踩坑记录（2026-09-11）**：这三个值**必须写成 `flutter.xxxVersion` 这种扩展形式**，
  > 不要写成字面量。写成 `compileSdk = 36` 时，AGP 9.1 在**配置阶段**直接报
  > `Android Gradle Plugin: project ':app' does not specify compileSdk`，
  > 构建失败，而且日志里没有任何前置错误提示，极难定位。
  > 另外 Flutter 工具链每次构建前都会自动「迁移」这个文件（例如把
  > `minSdk = 23` 改写成 `minSdk = flutter.minSdkVersion`，日志里会打印
  > `Upgrading build.gradle.kts`），所以**不要依赖字面量**。
  > CI（`.github/workflows/ci.yml`）里已加了一个失败时 dump 该文件内容的步骤，
  > 方便下次直接看到「迁移之后」的实情。
* 权限：
  * API ≤ 30：`BLUETOOTH` / `BLUETOOTH_ADMIN` / `ACCESS_FINE_LOCATION`（带 `maxSdkVersion="30"`）
  * API ≥ 31：`BLUETOOTH_SCAN`（`neverForLocation`）/ `BLUETOOTH_CONNECT`
  * 后台保活预留：`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_CONNECTED_DEVICE`、
    `POST_NOTIFICATIONS`、`WAKE_LOCK`（本 App 自己不起前台服务，留给你现有的架构）
* 运行时权限在连接页自动申请（`permission_handler`）。

---

## 9. CI/CD：GitHub Actions + 签名

| 文件 | 触发 | 干什么 |
| --- | --- | --- |
| `.github/workflows/ci.yml` | push `main`/`dev/**`/`release/**`、PR、手动 | `sync_version.py` → `flutter analyze` → `flutter test` → `flutter build apk --debug` + artifact |
| `.github/workflows/release.yml` | tag `v*`、手动 | 从 Secrets 恢复 keystore → 校验版本一致 → analyze/test → `flutter build apk --release` → `apksigner verify` 验签 → artifact + GitHub Release |

两者都：`ubuntu-latest` + `actions/setup-java@v4`（**Temurin 17**）+
`subosito/flutter-action@v2`（**锁定 3.47.3**、缓存 SDK）+ 缓存 `~/.gradle/{caches,wrapper}`。
gradle wrapper 用 `-bin.zip`，JVM 堆降到 4G（模板默认 8G 在 4 核 16G runner 上容易 OOM）。

> 若 runner 报「AGP 9.x 需要更高 JDK」，把两个 workflow 里的 `java-version: '17'`
> 改成 `'21'` 即可，`build.gradle.kts` 不用动。

### 签名配置（必须做，否则打 tag 会失败）

项目采用与 **APRSLocus 相同的一套约定**（Secrets 名字、目录、key.properties 格式都一致），
两边操作习惯通用：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的 base64（一整行） |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码（store 与 key 用同一个） |
| `ANDROID_KEY_ALIAS` | 可选，别名，默认 `pkwdwpl` |

#### ① 生成 keystore（二选一）

```bash
# 方式 A：不需要 JDK（推荐，已实测可用）
python3 tool/gen_keystore.py --out android/keystore/release.keystore
#  -- 输出会直接把密码 / 别名 / base64 全部打印出来，抄下来

# 方式 B：用 JDK 的 keytool
keytool -genkeypair -v -keystore android/keystore/release.keystore -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias pkwdwpl \
  -storepass '你的密码' -keypass '你的密码' \
  -dname "CN=BG7LZQ, OU=Amateur Radio, O=PKWDWPL Lite, C=CN"
```

只要已有的 keystore 转 base64：

```bash
python3 tool/gen_keystore.py --base64-only android/keystore/release.keystore
```

#### ② 写入 Secrets（二选一）

```bash
# 方式 A：自动写入（需要 token 具备 Secrets: Read and write 权限）
python3 tool/set_github_secrets.py --repo dariondong/pkwdwpl_lite \
  --keystore android/keystore/release.keystore --password '<密码>'

# 方式 B：网页手动添加
# 仓库 → Settings → Secrets and variables → Actions → New repository secret
```

> 细粒度 PAT（fine-grained）默认**没有** Secrets 写权限，会被拒绝：
> `Resource not accessible by personal access token`。
> 此时用方式 B 手动添加，或给 token 勾上 **Secrets: Read and write**。

#### ③ CI 里如何恢复签名

```yaml
- name: Restore keystore from Secrets
  env:
    ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
    ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
  run: |
    mkdir -p android/keystore
    echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/keystore/release.keystore
    printf 'storePassword=%s\nkeyPassword=%s\nkeyAlias=%s\nstoreFile=keystore/release.keystore\n' \
      "$ANDROID_KEYSTORE_PASSWORD" "$ANDROID_KEYSTORE_PASSWORD" "${ANDROID_KEY_ALIAS:-pkwdwpl}" \
      > android/key.properties
```

`build.gradle.kts` 的优先级：**`android/key.properties` → 环境变量 → debug 签名兜底**。
注意 `key.properties` 里的 `storeFile` 是**相对 `android/`** 的（用 `rootProject.file()` 解析），
与 APRSLocus 写法一致。

> **为什么 release 工作流在缺 Secret 时直接报错而不是回退 debug 签名？**
> tag 产出的包会直接发给用户；debug 签名的包装不上后续正式版，宁可不发。
> （APRSLocus 的做法是静默回退 debug，这里刻意改成硬失败。）

#### ④ 本地打包

```bash
cp android/key.properties.example android/key.properties   # 填密码
flutter build apk --release
```

### 发版节奏（建议）

```text
1. python3 tool/sync_version.py 1.0.1     # 同步 pubspec 与 app_info.dart
2. 推 main，等 CI Test Build 全绿
3. git tag v1.0.1 && git push origin v1.0.1   # → 自动出正式包
```

---

## 10. `.gitignore` 检查清单

- [x] `android/local.properties`
- [x] `android/key.properties`、`android/keystore/`、`**/*.jks`、`**/*.keystore`、`*.base64`
- [x] `.dart_tool/`、`.flutter-plugins`、`.flutter-plugins-dependencies`、`build/`
- [x] `third_party/*/build/`
- [x] `.idea/`、`*.iml`、`.vscode/`
- [x] `*.zip`

---

## 11. 已知限制 / 后续可做

* **字段 11 语义待标定**（距离 km / 距离 m / 速度 km/h 三者皆有可能）：
  已做成设置项 + 详情页显示原值，标定方法见 `docs/PROTOCOL.md` 第 5 节。
* **状态位 `V` 的真实含义**：真实数据 10/10 都是 V，本项目照常入库并加角标，
  默认筛选是「全部」（否则默认视图会是空的）。
* 离线地图目前是「图片/网格 + 等距圆柱投影」。如果你有 **mbtiles / 瓦片包**，
  可以换成 `flutter_map` + `file://` 瓦片源（需要新依赖 + CI 验证）；
  当前实现的好处是零新依赖、完全离线、不需要 GPS。
* 台站台账目前只在内存里；要落盘可用 `AprsStation.toJson()` 写
  SharedPreferences / sqflite（注意 `receivedAt` 用的是微秒）。
* 没有做蓝牙**主动扫描**（只列已配对设备，因为需求如此）；
  要加的话 `FlutterBluetoothSerial.instance.startDiscovery()`，
  `BluetoothService` 抽象层已留好位置。
