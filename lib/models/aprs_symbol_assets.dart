/// APRS 官方符号（PNG 图标包）解析。
///
/// 图标包来源：**APRSLocus 项目**（`assets/aprs_syms/`），
/// 由 `tool/download_aprs_icons.py` 从 `https://aprs.tv/img/<hex>.png` 抓取，
/// 覆盖 APRS 官方 **37 个符号表 × 符号码 0x21~0x7E**，共 3571 张 PNG。
///
/// 文件命名：`<hex(符号表)><hex(符号码)>.png`（两位小写十六进制），例如：
///
/// | 图标 | 符号表 | 符号码 | 文件名 |
/// | --- | --- | --- | --- |
/// | `/j` | `/` = 0x2F | `j` = 0x6A | `2f6a.png` |
/// | `/>` | `/` = 0x2F | `>` = 0x3E | `2f3e.png` |
/// | `/-` | `/` = 0x2F | `-` = 0x2D | `2f2d.png` |
/// | `/r` | `/` = 0x2F | `r` = 0x72 | `2f72.png` |
/// | `\y` | `\` = 0x5C | `y` = 0x79 | `5c79.png` |
///
/// 超出官方范围（或用 1 个字符表示图标）时返回 `null`，
/// 调用方应回退到 [AprsIconMapper] 的 Material 图标。
class AprsSymbolAssets {
  const AprsSymbolAssets._();

  /// 图标包所在目录（与 pubspec.yaml 的 assets 声明保持一致）。
  static const String assetDir = 'assets/aprs_syms';

  /// 官方符号表字符的 ASCII 码：`/`、`\`、`0`-`9`、`A`-`Z`。
  static const int primaryTableCode = 0x2F; // '/'
  static const int alternateTableCode = 0x5C; // '\\'

  /// 符号码最小/最大值（'!' ~ '~'）。
  static const int minSymbolCode = 0x21;
  static const int maxSymbolCode = 0x7E;

  /// 符号表字符是否在官方范围内。
  static bool isValidTable(String table) {
    if (table.length != 1) return false;
    final int t = table.codeUnitAt(0);
    return t == primaryTableCode ||
        t == alternateTableCode ||
        (t >= 0x30 && t <= 0x39) || // 0-9
        (t >= 0x41 && t <= 0x5A); // A-Z
  }

  /// 符号码是否在官方范围内。
  static bool isValidSymbolCode(String code) {
    if (code.length != 1) return false;
    final int c = code.codeUnitAt(0);
    return c >= minSymbolCode && c <= maxSymbolCode;
  }

  /// `<hex><hex>.png` 文件名。
  static String fileName(String table, String code) {
    final int t = table.codeUnitAt(0);
    final int c = code.codeUnitAt(0);
    return '${t.toRadixString(16).padLeft(2, '0')}'
        '${c.toRadixString(16).padLeft(2, '0')}.png';
  }

  /// `$PKWDWPL` 第 13 字段（如 `/j`）→ asset 路径；不可用返回 `null`。
  static String? assetPathFor(String? rawIcon) {
    if (rawIcon == null || rawIcon.length < 2) return null;
    final String table = rawIcon[0];
    final String code = rawIcon[1];
    if (!isValidTable(table) || !isValidSymbolCode(code)) return null;
    return '$assetDir/${fileName(table, code)}';
  }

  /// 分别给符号表与符号码，取 asset 路径；不可用返回 `null`。
  static String? assetPath(String table, String code) {
    if (!isValidTable(table) || !isValidSymbolCode(code)) return null;
    return '$assetDir/${fileName(table, code)}';
  }

  /// 图标是否取自官方图标包（否则会走 Material 兜底图标）。
  static bool hasOfficialSymbol(String? rawIcon) => assetPathFor(rawIcon) != null;

  /// 常用符号的 asset 路径，供 UI/测试引用。
  static String? get house => assetPath('/', '-');
  static String? get car => assetPath('/', '>');
  static String? get jeep => assetPath('/', 'j');
  static String? get repeater => assetPath('/', 'r');
  static String? get gateway => assetPath('/', '&');
  static String? get tcpip => assetPath('/', 'i');
  static String? get digipeater => assetPath('/', '#');
  static String? get weather => assetPath('/', '_');
  static String? get aircraft => assetPath('/', '^');
  static String? get ship => assetPath('/', 's');
  static String? get truck => assetPath('/', 'k');
  static String? get bicycle => assetPath('/', 'b');
}
