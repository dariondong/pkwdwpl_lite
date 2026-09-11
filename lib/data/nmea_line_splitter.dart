import 'dart:convert';

import 'package:flutter/foundation.dart';

/// NMEA 语句分帧器。
///
/// 串口/蓝牙的数据是按「块」到达的，一条语句可能被切成多次回调，也可能一次回调里
/// 挤着好几条语句，所以必须自己缓存 + 分帧。
///
/// 需求约定每行以 `\r\n` 结尾；这里同时兼容 `\n`、`\r` 单独结尾（部分固件如此），
/// 并在缓冲区异常增长（比如线序错、收到二进制噪声）时丢弃，避免内存被吃光。
class NmeaLineSplitter {
  NmeaLineSplitter({this.maxBufferChars = 8192});

  /// 缓冲区上限：超过就整体丢弃并回调 [onOverflow]。
  final int maxBufferChars;

  /// 溢出时的告警回调（默认打印到控制台）。
  void Function(String message)? onOverflow;

  String _buffer = '';

  /// 当前缓冲区里还没凑成完整语句的内容（调试用）。
  String get pending => _buffer;

  /// 送入一块新数据，返回其中所有**完整**的语句行（不含 CR/LF）。
  List<String> addBytes(List<int> chunk) {
    if (chunk.isEmpty) return const <String>[];
    // NMEA 全是 ASCII；allowMalformed 保证脏字节不会抛异常。
    return addString(utf8.decode(chunk, allowMalformed: true));
  }

  /// 送入一段文本，返回其中所有完整的语句行。
  List<String> addString(String chunk) {
    if (chunk.isEmpty) return const <String>[];
    _buffer += chunk;

    final List<String> lines = <String>[];
    int start = 0;
    for (int i = 0; i < _buffer.length; i++) {
      final int c = _buffer.codeUnitAt(i);
      if (c == 0x0A /* \n */ || c == 0x0D /* \r */) {
        if (i > start) {
          lines.add(_buffer.substring(start, i));
        }
        start = i + 1;
      }
    }

    _buffer = start >= _buffer.length ? '' : _buffer.substring(start);

    if (_buffer.length > maxBufferChars) {
      final String dropped = _buffer;
      _buffer = '';
      final String message =
          '[PKWDWPL] 接收缓冲区超过 $maxBufferChars 字符，已丢弃 ${dropped.length} 字符'
          '（前 60 字符: ${dropped.substring(0, dropped.length < 60 ? dropped.length : 60)}）';
      if (onOverflow != null) {
        onOverflow!(message);
      } else {
        debugPrint(message);
      }
    }

    return lines;
  }

  /// 主动清空缓冲（断开连接时调用）。
  void reset() => _buffer = '';
}
