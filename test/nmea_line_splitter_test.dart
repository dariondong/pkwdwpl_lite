import 'package:flutter_test/flutter_test.dart';
import 'package:pkwdwpl_lite/data/nmea_line_splitter.dart';

void main() {
  group('NmeaLineSplitter', () {
    test('一次回调里有多条语句', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter();
      final List<String> lines = splitter.addString('A1\r\nA2\r\nA3\r\n');
      expect(lines, <String>['A1', 'A2', 'A3']);
      expect(splitter.pending, '');
    });

    test('语句被切成多块（串口最常见的场景）', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter();
      expect(splitter.addString(r'$PKWD'), isEmpty);
      expect(splitter.pending, r'$PKWD');
      expect(splitter.addString('WPL,102202'), isEmpty);
      expect(splitter.addString(',A*12\r\n'), <String>[r'$PKWDWPL,102202,A*12']);
      expect(splitter.pending, '');
    });

    test('兼容仅以 \\r 或仅以 \\n 结尾', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter();
      expect(splitter.addString('X\rY\nZ'), <String>['X', 'Y']);
      expect(splitter.addString('\r'), <String>['Z']);
    });

    test('半条语句残留在缓冲区，不会丢', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter();
      splitter.addString('partial');
      expect(splitter.pending, 'partial');
      expect(splitter.addString(' done\r\n'), <String>['partial done']);
    });

    test('按字节送入（模拟蓝牙回调）', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter();
      final List<int> chunk = '\$PKWDWPL,a,*00\r\n'.codeUnits;
      expect(splitter.addBytes(chunk), <String>[r'$PKWDWPL,a,*00']);
    });

    test('缓冲区溢出时丢弃并告警，避免内存无限增长', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter(maxBufferChars: 16);
      String? warning;
      splitter.onOverflow = (String message) => warning = message;

      splitter.addString('1234567890');
      expect(splitter.pending, '1234567890');
      splitter.addString('ABCDEFGHIJ'); // 20 > 16 → 丢弃
      expect(splitter.pending, '');
      expect(warning, contains('缓冲区超过'));
    });

    test('reset 清空缓冲区', () {
      final NmeaLineSplitter splitter = NmeaLineSplitter();
      splitter.addString('abc');
      splitter.reset();
      expect(splitter.pending, '');
    });
  });
}
