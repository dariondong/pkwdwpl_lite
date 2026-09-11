# APRS 官方符号图标包

**来源：[APRSLocus](https://github.com/dariondong/APRSLocus) 项目的 `assets/aprs_syms/`**
（本项目作者自己的另一个项目，直接从那边复制过来，保持完全一致的命名与目录结构）。

## 内容

| 项 | 值 |
| --- | --- |
| 文件数 | **3571** 张 PNG |
| 单张尺寸 | **24 × 24 px**（RGBA，带透明通道） |
| 体积 | 约 2.4 MB |
| 覆盖 | APRS 官方 37 个符号表 × 符号码 `0x21`(`!`) ~ `0x7E`(`~`) |
| 来源 | aprs.tv 的公开 APRS 符号图（APRSLocus 的 `tools/download_aprs_icons.py` 抓取） |

符号表一共是 `/`、`\`、`0`~`9`、`A`~`Z` = 2 + 10 + 26 = 38 个前缀，
但并非每个「表 × 码」的组合都有图，所以实际文件数是 3571 而不是 38 × 94 = 3572。

## 命名规则

**`<hex(符号表)><hex(符号码)>.png`** — 两个字符各取 ASCII 的两位小写十六进制：

| APRS 图标 | 符号表 | 符号码 | 文件名 |
| --- | --- | --- | --- |
| `/j` 汽车 | `/` = `0x2F` | `j` = `0x6A` | `2f6a.png` |
| `/>` 汽车 | `/` = `0x2F` | `>` = `0x3E` | `2f3e.png` |
| `/-` 房屋 | `/` = `0x2F` | `-` = `0x2D` | `2f2d.png` |
| `/r` 中继塔 | `/` = `0x2F` | `r` = `0x72` | `2f72.png` |
| `/&` 网关 | `/` = `0x2F` | `&` = `0x26` | `2f26.png` |
| `/i` 网络台站 | `/` = `0x2F` | `i` = `0x69` | `2f69.png` |
| `\j` 副表汽车 | `\` = `0x5C` | `j` = `0x6A` | `5c6a.png` |

## 代码里怎么用

不用手拼文件名，用 `lib/models/aprs_symbol_assets.dart` 里的 API：

```dart
AprsSymbolAssets.assetPathFor('/j');     // → 'assets/aprs_syms/2f6a.png'
AprsSymbolAssets.assetPath('\\', 'j');   // → 'assets/aprs_syms/5c6a.png'
AprsSymbolAssets.hasOfficialSymbol('/j'); // → true

// 台站对象上直接取（图标字段非官方格式时为 null）
station.iconAsset;        // String?
station.hasOfficialIcon;  // bool
```

UI 里直接用 `AprsSymbolIcon`，它会**自动回退**到 Material 图标（`/j`→汽车、`/`→房屋、未知→电台）：

```dart
AprsSymbolIcon(icon: station.iconRaw, size: 28)
```

## ⚠️ 24×24 放大会糊

这是这套图标包的固有局限：**官方只有 24×24，没有 SVG、也没有更大尺寸**
（已确认 `aprs.tv/img/*.svg`、`*_32.png`、`*@2x.png` 等命名全部 404）。
所以：

* **列表页 26px / 详情页 40px / 地图 34–46px** —— 在 2x~3x 屏幕上接近或略超原始尺寸，效果可以接受；
* 再往上放大（如启动图标）就会明显发虚。

代码里的取舍：`≤ 72px` 用 `NEAREST`（保持像素锐利），`> 72px` 用 `LANCZOS`（避免马赛克块）。

## 更新图标包

```bash
python3 tool/update_aprs_symbols.py            # 只补缺失的
python3 tool/update_aprs_symbols.py --force    # 全量重下
python3 tool/update_aprs_symbols.py --from ../APRSLocus   # 直接从本地 APRSLocus 复制
```

## 许可

APRS 符号图形来自 aprs.tv 的公开素材；APRSLocus 项目以 **GPL-3.0** 分发，
所以这套文件随本仓库一起也应按 **GPL-3.0** 对待。
若你要把本项目用于闭源分发，请先换掉这套图标（或自行确认素材授权）。
详见仓库根目录 `NOTICE`。
