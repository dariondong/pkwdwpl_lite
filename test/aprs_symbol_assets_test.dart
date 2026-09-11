import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/models/aprs_icon.dart';
import 'package:pkwdwpl_lite/models/aprs_station.dart';
import 'package:pkwdwpl_lite/models/aprs_symbol_assets.dart';

/// APRS 官方符号图标包（来自 APRSLocus 项目 `assets/aprs_syms/`）的回归测试。
///
/// 除了命名规则，这里还会**真的去磁盘上找文件**：
/// 图标包是 3571 张 PNG，一旦漏拷贝 / 改名 / 少一个符号表，光看代码是发现不了的。
void main() {
  group('文件名规则', () {
    test('表 + 码 → 两位小写十六进制 png', () {
      expect(AprsSymbolAssets.fileName('/', 'j'), '2f6a.png');
      expect(AprsSymbolAssets.fileName('/', '>'), '2f3e.png');
      expect(AprsSymbolAssets.fileName('/', '-'), '2f2d.png');
      expect(AprsSymbolAssets.fileName('\\', 'y'), '5c79.png');
      expect(AprsSymbolAssets.fileName('0', '#'), '3023.png');
      expect(AprsSymbolAssets.fileName('A', '!'), '4121.png');
    });

    test('asset 路径（与 APRSLocus 的约定一致）', () {
      expect(AprsSymbolAssets.assetPathFor('/j'), 'assets/aprs_syms/2f6a.png');
      expect(AprsSymbolAssets.assetPathFor('/>'), 'assets/aprs_syms/2f3e.png');
      expect(AprsSymbolAssets.assetPathFor('\\y'), 'assets/aprs_syms/5c79.png');
    });

    test('非法/越界输入返回 null（由调用方回退 Material 图标）', () {
      expect(AprsSymbolAssets.assetPathFor(null), isNull);
      expect(AprsSymbolAssets.assetPathFor(''), isNull);
      expect(AprsSymbolAssets.assetPathFor('/'), isNull); // 只有符号表
      expect(AprsSymbolAssets.assetPathFor('/ '), isNull); // 空格超出 0x21~0x7E
      expect(AprsSymbolAssets.assetPathFor('/\u007f'), isNull); // DEL 越界
      expect(AprsSymbolAssets.assetPathFor('!a'), isNull); // '!' 不是合法符号表
      expect(AprsSymbolAssets.assetPath('/', '\u0020'), isNull);
    });

    test('符号表范围：/ 与 \\ 以及 0-9 A-Z 共 38 个', () {
      expect(AprsSymbolAssets.isValidTable('/'), isTrue);
      expect(AprsSymbolAssets.isValidTable('\\'), isTrue);
      expect(AprsSymbolAssets.isValidTable('7'), isTrue);
      expect(AprsSymbolAssets.isValidTable('Z'), isTrue);
      expect(AprsSymbolAssets.isValidTable('a'), isFalse); // 小写不是符号表
      expect(AprsSymbolAssets.isValidTable('!'), isFalse);
    });
  });

  group('图标包落盘检查（真的读文件）', () {
    final Directory dir = Directory('assets/aprs_syms');


    test('目录存在，38 个符号表 × 符号码 0x21~0x7E 共 3572 张 PNG', () {
      expect(dir.existsSync(), isTrue, reason: '图标包目录缺失：${dir.path}');
      final List<String> pngs = _pngNames(dir);
      expect(pngs.length, 3572);

      // 文件集必须正好是「38 个表 × 94 个码」的笛卡尔积，一张不多一张不少。
      final Set<String> expected = <String>{
        for (final String table in _tables)
          for (int code = 0x21; code <= 0x7E; code++)
            '$table${code.toRadixString(16).padLeft(2, '0')}.png',
      };
      expect(expected.length, 3572);
      expect(pngs.toSet(), expected);
    });

    test('文件名全部是 4 位小写十六进制 + .png', () {
      final RegExp pattern = RegExp(r'^[0-9a-f]{4}\.png$');
      final List<String> bad = _pngNames(dir)
          .where((String name) => !pattern.hasMatch(name))
          .toList();
      expect(bad, isEmpty, reason: '命名异常：$bad');
    });

    test('目录里的 README.md 不影响解析', () {
      expect(File('${dir.path}/README.md').existsSync(), isTrue);
    });

    test('关键图标存在且是合法 PNG（magic bytes）', () {
      const List<String> keys = <String>[
        '2f6a', // /j  汽车
        '2f3e', // />  汽车
        '2f2d', // /-  房屋
        '2f72', // /r  中继
        '2f26', // /&  网关
        '2f69', // /i  网络台站
        '5c79', // \y  行人
      ];
      for (final String key in keys) {
        final File file = File('${dir.path}/$key.png');
        expect(file.existsSync(), isTrue, reason: '$key.png 缺失');
        final List<int> head = file.readAsBytesSync().sublist(0, 8);
        expect(
          head,
          <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          reason: '$key.png 不是合法 PNG',
        );
      }
    });

    test('38 个符号表齐全，每表 94 个符号全是合法 PNG', () {
      final Map<String, int> perTable = <String, int>{};
      for (final String name in _pngNames(dir)) {
        perTable.update(name.substring(0, 2), (int v) => v + 1, ifAbsent: () => 1);
      }
      expect(perTable.keys.toSet(), _tables.toSet());
      expect(perTable.length, 38);
      for (final MapEntry<String, int> entry in perTable.entries) {
        expect(entry.value, 94, reason: '符号表 ${entry.key} 的符号码不完整');
      }

      // 全量校验 PNG magic bytes（不只是关键几张）。
      final List<int> magic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      for (final String name in _pngNames(dir)) {
        final List<int> head = File('${dir.path}/$name').readAsBytesSync().sublist(0, 8);
        expect(head, magic, reason: '$name 不是合法 PNG');
      }
    });
  });

  group('与解析结果联动：10 条真实报文里的图标都要能找到 PNG', () {
    const List<String> captures = <String>[
      r'$PKWDWPL,102339,V,3958.55,N,11625.70,E,,,290625,,BI4PGN-11,/i*22',
      // 第 2 条把呼号从 BG1UB9 修正为 BG1UBU-9 后，校验和正好是报文里的 0C
      r'$PKWDWPL,102353,V,3955.09,N,11616.91,E,4,103,290625,000050,BG1UBU-9,/j*0C',
      r'$PKWDWPL,102439,V,4000.30,N,11610.16,E,,,290625,,BY1BJ-1,/r*4D',
      r'$PKWDWPL,102537,V,3958.46,N,11618.95,E,290625,,BI1AR-1,/&*1C',
      r'$PKWDWPL,102627,V,3907.80,N,11712.20,E,,,290625,,BH3BBJ-1,/r*15',
      r'$PKWDWPL,102921,V,4000.46,N,11632.53,E,,,290625,,BG1QGD-10,/r*3D',
    ];

    test('每条报文的图标字段都能解析出存在的 PNG', () {
      for (final String raw in captures) {
        final AprsStation station = AprsStationParser.parse(raw);
        expect(station.hasOfficialIcon, isTrue, reason: '${station.iconRaw} 没有官方图标');
        expect(station.iconAsset, isNotNull);
        final File file = File(station.iconAsset!);
        expect(file.existsSync(), isTrue, reason: '文件不存在：${station.iconAsset}');
      }
    });

    test('实测出现的 5 种图标映射正确', () {
      expect(AprsSymbolAssets.assetPathFor('/i'), 'assets/aprs_syms/2f69.png');
      expect(AprsSymbolAssets.assetPathFor('/j'), 'assets/aprs_syms/2f6a.png');
      expect(AprsSymbolAssets.assetPathFor('/r'), 'assets/aprs_syms/2f72.png');
      expect(AprsSymbolAssets.assetPathFor('/&'), 'assets/aprs_syms/2f26.png');
    });
  });

  group('AprsSymbolIcon 组件', () {
    testWidgets('未知图标回退到 Material 电台图标', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AprsSymbolIcon(icon: '/\u007f', size: 24),
          ),
        ),
      );
      expect(find.byIcon(Icons.radio), findsOneWidget);
    });

    testWidgets('没有图标字段时也回退', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AprsSymbolIcon(icon: null)),
        ),
      );
      expect(find.byIcon(Icons.radio), findsOneWidget);
    });

    test('assetPathOf 与 AprsSymbolAssets 一致', () {
      expect(AprsSymbolIcon.assetPathOf('/j'), AprsSymbolAssets.assetPathFor('/j'));
      expect(AprsSymbolIcon.assetPathOf(''), isNull);
    });
  });

  group('AprsIconMapper（图标包的兜底）', () {
    test('/j 与 /> → 汽车', () {
      expect(AprsIconMapper.iconFor('/j'), Icons.directions_car);
      expect(AprsIconMapper.iconFor('/>'), Icons.directions_car);
    });

    test('/- → 房屋；只有一个 "/" 也是房屋', () {
      expect(AprsIconMapper.iconFor('/-'), Icons.home);
      expect(AprsIconMapper.iconFor('/'), Icons.home);
    });

    test('未知符号 → 电台兜底', () {
      expect(AprsIconMapper.iconFor('/z'), AprsIconMapper.fallbackIcon);
      expect(AprsIconMapper.iconFor(''), AprsIconMapper.fallbackIcon);
      expect(AprsIconMapper.iconFor(null), AprsIconMapper.fallbackIcon);
    });
  });
}

/// `assets/aprs_syms/` 下的所有 PNG 文件名（不含 README.md 等非图片文件）。
List<String> _pngNames(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .map((File f) => f.uri.pathSegments.last)
    .where((String name) => name.endsWith('.png'))
    .toList()
  ..sort();

/// APRS 官方 38 个符号表的十六进制前缀。
const Set<String> _tables = <String>{
  '2f', '5c', // '/' 主表、'\' 副表
  '30', '31', '32', '33', '34', '35', '36', '37', '38', '39', // 0-9
  '41', '42', '43', '44', '45', '46', '47', '48', '49', '4a', // A-J
  '4b', '4c', '4d', '4e', '4f', '50', '51', '52', '53', '54', // K-T
  '55', '56', '57', '58', '59', '5a', // U-Z
};
