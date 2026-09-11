import 'package:flutter/material.dart' show IconData;

import 'aprs_icon.dart';
import 'aprs_symbol_assets.dart';
import 'geo_math.dart';

/// NMEA 0183 校验和工具。
///
/// 规则：把 `$` 之后、`*` 之前的**每一个字符（含逗号）**做 XOR，结果取两位十六进制大写。
/// 例（业界权威示例）：`$GPGGA,123519,4807.038,N,...*47` → 0x47（本项目测试已钉死）。
///
/// ⚠️ 关于 XOR 的固有局限（用 BI7NOR 采集的真实数据验证过）：
/// XOR 与字符**顺序无关**，所以它只能发现「奇数个比特位翻转」类的错误，
/// **发现不了字符换位**（例如 `BI4PGN1-1` 和 `BI4PGN-11` 的 XOR 完全相同）。
/// 因此除了校验和，解析器还做「字段数检查 + 坐标合法性 + 呼号格式检查」三层兜底。
class NmeaChecksum {
  const NmeaChecksum._();

  /// 计算 body（不含 `$` 与 `*XX`）的 XOR 校验值。
  static int computeFrom(String body) {
    int xor = 0;
    for (final int unit in body.codeUnits) {
      xor ^= unit & 0xFF;
    }
    return xor & 0xFF;
  }

  /// 格式化为 `2E` 这样的两位大写十六进制。
  static String format(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(2, '0');

  /// 校验一整条语句，返回详细信息（便于 UI 显示「收到 X / 计算 Y」）。
  static NmeaChecksumCheck check(String sentence) {
    String s = sentence.trim();
    if (s.startsWith(r'$')) s = s.substring(1);

    final int star = s.lastIndexOf('*');
    String? claimed;
    String body = s;
    if (star >= 0) {
      claimed = s.substring(star + 1).trim();
      body = s.substring(0, star);
    }

    final int computed = computeFrom(body);
    final bool claimedLooksValid =
        claimed != null && RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(claimed);
    final int? claimedValue =
        claimedLooksValid ? int.tryParse(claimed, radix: 16) : null;

    return NmeaChecksumCheck(
      hasChecksum: claimedLooksValid,
      valid: claimedValue != null && claimedValue == computed,
      claimedHex: claimedLooksValid ? claimed.toUpperCase() : null,
      computedHex: format(computed),
      body: body,
    );
  }
}

/// [NmeaChecksum.check] 的返回值。
class NmeaChecksumCheck {
  const NmeaChecksumCheck({
    required this.hasChecksum,
    required this.valid,
    required this.claimedHex,
    required this.computedHex,
    required this.body,
  });

  /// 语句是否携带了合法的 `*XX`。
  final bool hasChecksum;

  /// 携带的校验和是否正确。
  final bool valid;

  /// 语句里收到的校验和（大写），没有则为 null。
  final String? claimedHex;

  /// 本地计算的校验和（大写）。
  final String computedHex;

  /// `$` 与 `*` 之间的内容。
  final String body;
}

/// 解析失败原因（配合 easy_localization 的 `errors.*` 文案）。
enum AprsParseErrorCode {
  emptyLine,
  noStart,
  notPkwdwpl,
  checksumMismatch,
  tooFewFields,
  badLatitude,
  badLongitude,
  noCallsign,
}

/// 解析错误对象。
class AprsParseError {
  const AprsParseError(this.code, {this.detail, this.raw = ''});

  final AprsParseErrorCode code;

  /// 附加信息，例如校验和的「收到/计算」值、非法坐标原文。
  final String? detail;

  /// 原始语句，便于日志排查。
  final String raw;

  @override
  String toString() => 'AprsParseError(${code.name}${detail == null ? '' : ': $detail'})';
}

/// 解析结果：成功时 [station] 非空，失败时 [error] 非空。
class AprsParseResult {
  const AprsParseResult.success(AprsStation this.station) : error = null;
  const AprsParseResult.failure(AprsParseError this.error) : station = null;

  final AprsStation? station;
  final AprsParseError? error;

  bool get isSuccess => station != null;
}

/// 解析异常：仅在调用 [AprsStationParser.parse]（严格模式）时抛出。
class AprsParseException implements Exception {
  const AprsParseException(this.error);

  final AprsParseError error;

  @override
  String toString() => 'AprsParseException: $error';
}

/// 详情页「字段分解」用的一行。
class AprsFieldRow {
  const AprsFieldRow(this.index, this.label, this.value, {this.note});

  /// 1 开始的序号，与协议文档中的字段编号一致。
  final int index;
  final String label;
  final String value;

  /// 备注（比如「为空」「字段数异常」）。
  final String? note;
}

/// 一条 Kenwood `$PKWDWPL` 语句对应的 APRS 台站快照。
///
/// 字段编号（与协议文档一致）：
/// ```
///  1 $PKWDWPL      固定前缀
///  2 102339        时间 hhmmss (UTC)
///  3 V             状态 (A=有效, V=无效)
///  4 3958.55       纬度 ddmm.mm
///  5 N             纬度方向 N/S
///  6 11625.70      经度 dddmm.mm
///  7 E             经度方向 E/W
///  8 (空)           海拔（米）
///  9 (空)           方向 / 航向（度）
/// 10 290625        日期 ddmmyy
/// 11 (空)          距离（单位待定，见 AppSettings.field11Meaning）
/// 12 BI4PGN-11     呼号
/// 13 /i            APRS 图标
/// 14 *22           校验和
/// ```
///
/// 实测（BI7NOR 采集的 10 条真实语句）：第 8/9/11 字段**经常为空**，
/// 此时逗号仍然占位，所以**逗号字段数最少是 10**（`E,,<date>,,<call>,<icon>` 这种写法
/// 表示第 8/9 字段为空；标准满配是 12 个逗号字段）。
class AprsStation {
  const AprsStation({
    required this.raw,
    required this.callsign,
    required this.utcTime,
    required this.utcDate,
    required this.statusRaw,
    required this.statusValid,
    required this.latitudeRaw,
    required this.latitudeHemisphere,
    required this.longitudeRaw,
    required this.longitudeHemisphere,
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.courseDegrees,
    required this.distanceMeters,
    required this.iconRaw,
    required this.claimedChecksum,
    required this.computedChecksum,
    required this.checksumValid,
    required this.receivedAt,
    this.distanceRaw = '',
    this.receiveSeq = 0,
    this.parsedFieldCount = AprsStationParser.standardFieldCount,
    this.fieldCountAnomaly = false,
    this.callsignSuspicious = false,
    this.softError,
    this.rawFields = const <String>[],
  });

  /// 原始 NMEA 语句（不含结尾的 CR/LF）。
  final String raw;

  /// 呼号（Source Site），如 `BI4PGN-11`。
  final String callsign;

  /// 字段 2：hhmmss（UTC）。
  final String utcTime;

  /// 字段 10：ddmmyy。
  final String utcDate;

  /// 字段 3 原文。`A`=有效，`V`=无效。
  final String statusRaw;

  /// 由 [statusRaw] 推导的有效性；未知状态为 null。
  final bool? statusValid;

  /// 字段 4 原文（度分），如 `3958.55`。
  final String latitudeRaw;

  /// 字段 5：`N` / `S`。
  final String latitudeHemisphere;

  /// 字段 6 原文（度分），如 `11625.70`。
  final String longitudeRaw;

  /// 字段 7：`E` / `W`。
  final String longitudeHemisphere;

  /// 十进制纬度（39.975833…），南纬为负。
  final double latitude;

  /// 十进制经度（116.428333…），西经为负。
  final double longitude;

  /// 字段 8：海拔（米），空则为 null。
  final int? altitudeMeters;

  /// 字段 9：航向（0-359 度），空则为 null。
  final int? courseDegrees;

  /// 字段 11 的整数值。含义由 `AppSettings.field11Meaning` 决定
  /// （距离 km / 距离 m / 速度 km/h —— 不同固件解释不同，详见 docs/PROTOCOL.md）。
  final int? distanceMeters;

  /// 字段 11 原文（保留前导零，如 `000050`）。
  final String distanceRaw;

  /// 字段 13：APRS 图标，如 `/j`。
  final String iconRaw;

  /// 语句中携带的校验和（大写），可能为 null。
  final String? claimedChecksum;

  /// 本地计算出的校验和（大写）。
  final String computedChecksum;

  /// 校验和是否正确。若语句不带校验和，则为 false（UI 会提示「未携带」）。
  final bool checksumValid;

  /// 本机收到该语句的时间（本地时区）。
  final DateTime receivedAt;

  /// 接收序号（第几条成功解析并入库的语句，从 1 开始）。
  ///
  /// 列表页第一个字段就显示它，方便和串口日志逐条对齐。
  final int receiveSeq;

  /// 实际解析到的逗号字段数（不含 `$PKWDWPL` 前缀）。
  final int parsedFieldCount;

  /// 字段数不是标准的 12 —— 说明采集/转发时丢了逗号，已按容错规则解析。
  final bool fieldCountAnomaly;

  /// 呼号不符合业余无线电呼号格式（疑似抄写/传输错误）。
  final bool callsignSuspicious;

  /// 宽松模式（关闭严格校验）下仍然接收时，记录的问题说明。
  final AprsParseError? softError;

  /// 逗号分隔后的原始字段（含 `$PKWDWPL` 前缀与 `*XX`），固定 14 项，便于调试。
  final List<String> rawFields;

  /// 映射后的 Material 图标（未知图标 → Icons.radio）——**兜底用**。
  ///
  /// 正常显示请用 [AprsSymbolIcon]（优先官方图标包，失败才回退到这个）。
  IconData get icon => AprsIconMapper.iconFor(iconRaw);

  /// APRS 官方图标包的 asset 路径（如 `assets/aprs_syms/2f6a.png`）；
  /// 图标字段不是官方 2 字符写法时返回 null。
  String? get iconAsset => AprsSymbolAssets.assetPathFor(iconRaw);

  /// 是否能用官方图标包显示。
  bool get hasOfficialIcon => iconAsset != null;

  /// 图标简述。
  String get iconLabel => AprsIconMapper.labelFor(iconRaw);

  /// 符号表字符：`/`（主表）或 `\`（副表）。
  String get symbolTable => iconRaw.isEmpty ? '/' : iconRaw[0];

  /// 符号码字符。
  String get symbolCode => iconRaw.length >= 2 ? iconRaw[1] : '';

  /// 这条记录是否「有问题」：字段数异常 / 呼号可疑 / 校验和未通过。
  bool get hasWarnings =>
      fieldCountAnomaly || callsignSuspicious || !checksumValid || softError != null;

  /// 与本机参考坐标的距离（米）；未设置参考坐标时返回 null。
  double? distanceFrom(double? refLat, double? refLon) {
    if (refLat == null || refLon == null) return null;
    return GeoMath.haversineMeters(refLat, refLon, latitude, longitude);
  }

  /// 语句时间（UTC），由 [utcDate] + [utcTime] 组合；非法则返回 null。
  DateTime? get utcDateTime => AprsStationParser.combineUtc(utcDate, utcTime);

  /// 详情页的 14 字段分解。
  List<AprsFieldRow> get fieldRows {
    const List<String> labels = <String>[
      r'$PKWDWPL',
      'time hhmmss',
      'status (A/V)',
      'lat ddmm.mm',
      'lat N/S',
      'lon dddmm.mm',
      'lon E/W',
      'altitude m',
      'course deg',
      'date ddmmyy',
      'distance',
      'callsign',
      'APRS icon',
      'checksum',
    ];

    final List<String> values = rawFields.length >= 14
        ? rawFields
        : _rebuildRawFields();

    return <AprsFieldRow>[
      for (int i = 0; i < labels.length; i++)
        AprsFieldRow(
          i + 1,
          labels[i],
          values[i],
          note: values[i].isEmpty ? 'empty' : null,
        ),
    ];
  }

  List<String> _rebuildRawFields() => <String>[
        r'$PKWDWPL',
        utcTime,
        statusRaw,
        latitudeRaw,
        latitudeHemisphere,
        longitudeRaw,
        longitudeHemisphere,
        altitudeMeters?.toString() ?? '',
        courseDegrees?.toString() ?? '',
        utcDate,
        distanceRaw,
        callsign,
        iconRaw,
        claimedChecksum == null ? '' : '*$claimedChecksum',
      ];

  /// 覆盖接收时间 / 序号（同一呼号刷新时保留历史用）。
  AprsStation copyWith({DateTime? receivedAt, int? receiveSeq}) => AprsStation(
        raw: raw,
        callsign: callsign,
        utcTime: utcTime,
        utcDate: utcDate,
        statusRaw: statusRaw,
        statusValid: statusValid,
        latitudeRaw: latitudeRaw,
        latitudeHemisphere: latitudeHemisphere,
        longitudeRaw: longitudeRaw,
        longitudeHemisphere: longitudeHemisphere,
        latitude: latitude,
        longitude: longitude,
        altitudeMeters: altitudeMeters,
        courseDegrees: courseDegrees,
        distanceMeters: distanceMeters,
        distanceRaw: distanceRaw,
        iconRaw: iconRaw,
        claimedChecksum: claimedChecksum,
        computedChecksum: computedChecksum,
        checksumValid: checksumValid,
        receivedAt: receivedAt ?? this.receivedAt,
        receiveSeq: receiveSeq ?? this.receiveSeq,
        parsedFieldCount: parsedFieldCount,
        fieldCountAnomaly: fieldCountAnomaly,
        callsignSuspicious: callsignSuspicious,
        softError: softError,
        rawFields: rawFields,
      );

  /// 精简的 JSON（持久化用）。恢复时通过 [raw] 重新解析，保证与解析器一致。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'raw': raw,
        // 用微秒保存，保证 JSON 往返后 receivedAt 完全相等。
        'receivedAt': receivedAt.microsecondsSinceEpoch,
        'receiveSeq': receiveSeq,
        'callsign': callsign,
        'lat': latitude,
        'lon': longitude,
        'icon': iconRaw,
        'checksumValid': checksumValid,
      };

  factory AprsStation.fromJson(Map<String, dynamic> json) {
    final AprsParseResult result = AprsStationParser.tryParse(
      json['raw'] as String? ?? '',
      strictChecksum: false,
      receivedAt: DateTime.fromMicrosecondsSinceEpoch(
        (json['receivedAt'] as num?)?.toInt() ??
            DateTime.now().microsecondsSinceEpoch,
      ),
      receiveSeq: (json['receiveSeq'] as num?)?.toInt() ?? 0,
    );
    final AprsStation? station = result.station;
    if (station == null) {
      throw AprsParseException(
        result.error ?? const AprsParseError(AprsParseErrorCode.emptyLine),
      );
    }
    return station;
  }

  @override
  String toString() =>
      'AprsStation(#$receiveSeq $callsign, ${latitude.toStringAsFixed(5)}, '
      '${longitude.toStringAsFixed(5)}, alt=$altitudeMeters, '
      'crs=$courseDegrees, icon=$iconRaw, ok=$checksumValid)';
}

/// 逗号切分后的字段集合（内部使用）。
class _FieldSet {
  const _FieldSet({
    required this.time,
    required this.status,
    required this.lat,
    required this.latHemi,
    required this.lon,
    required this.lonHemi,
    required this.altitude,
    required this.course,
    required this.date,
    required this.distance,
    required this.callsign,
    required this.icon,
    required this.count,
    required this.anomaly,
  });

  final String time;
  final String status;
  final String lat;
  final String latHemi;
  final String lon;
  final String lonHemi;
  final String altitude;
  final String course;
  final String date;
  final String distance;
  final String callsign;
  final String icon;
  final int count;
  final bool anomaly;
}

/// `$PKWDWPL` 解析器（XOR 校验 + 度分转换 + 容错字段定位）。
class AprsStationParser {
  const AprsStationParser._();

  /// 语句固定前缀（不含 `$`）。
  static const String sentenceId = 'PKWDWPL';

  /// 协议字段总数（含前缀与校验和），详情页按这个口径展示。
  static const int fieldCount = 14;

  /// `$PKWDWPL` 之后的标准逗号字段数（时间…图标，共 12 项）。
  static const int standardFieldCount = 12;

  /// 少于这个数量就认为无法可靠定位（连呼号/图标都拿不到）。
  static const int minimumFieldCount = 8;

  /// 业余无线电呼号（宽松版）：前缀 + 区号数字 + 后缀字母 + 可选 SSID。
  ///
  /// 只用来「提示可疑」，不做丢弃依据 —— 各国呼号规则差异较大。
  static final RegExp callsignPattern =
      RegExp(r'^[A-Z0-9]{1,3}[0-9][A-Z]{1,3}(-[0-9]{1,2})?$');

  /// 解析一条语句；失败抛出 [AprsParseException]。
  static AprsStation parse(
    String line, {
    DateTime? receivedAt,
    bool strictChecksum = true,
    int receiveSeq = 0,
  }) {
    final AprsParseResult result = tryParse(
      line,
      receivedAt: receivedAt,
      strictChecksum: strictChecksum,
      receiveSeq: receiveSeq,
    );
    final AprsStation? station = result.station;
    if (station == null) {
      throw AprsParseException(result.error!);
    }
    return station;
  }

  /// 解析一条语句；失败返回 [AprsParseResult.failure]。
  ///
  /// [strictChecksum] 为 true 时，校验和不符的语句直接丢弃（需求 3 的默认行为）；
  /// 为 false 时仍然解析，但在 [AprsStation.softError] 里标注问题。
  static AprsParseResult tryParse(
    String line, {
    DateTime? receivedAt,
    bool strictChecksum = true,
    int receiveSeq = 0,
  }) {
    final String raw = _stripLineEnding(line);
    if (raw.isEmpty) {
      return const AprsParseResult.failure(
        AprsParseError(AprsParseErrorCode.emptyLine),
      );
    }
    if (!raw.startsWith(r'$')) {
      return AprsParseResult.failure(
        AprsParseError(AprsParseErrorCode.noStart, raw: raw),
      );
    }
    if (!raw.toUpperCase().startsWith(r'$' + sentenceId)) {
      return AprsParseResult.failure(
        AprsParseError(AprsParseErrorCode.notPkwdwpl, raw: raw),
      );
    }

    // ---- 校验和 ----------------------------------------------------------
    final NmeaChecksumCheck checksum = NmeaChecksum.check(raw);
    AprsParseError? softError;
    if (!checksum.valid) {
      final AprsParseError error = AprsParseError(
        AprsParseErrorCode.checksumMismatch,
        detail: checksum.hasChecksum
            ? '${checksum.claimedHex} != ${checksum.computedHex}'
            : 'missing',
        raw: raw,
      );
      if (strictChecksum) {
        return AprsParseResult.failure(error);
      }
      softError = error;
    }

    // ---- 字段拆分与容错定位 ----------------------------------------------
    // checksum.body = "PKWDWPL,102339,V,3958.55,..." （不含 $ 与 *XX）
    final String payload = checksum.body.substring(sentenceId.length);
    final List<String> fields = payload.split(',');
    // payload 以 ',' 开头 → 去掉第一个空元素。
    if (fields.isNotEmpty && fields.first.isEmpty) {
      fields.removeAt(0);
    }
    if (fields.length < minimumFieldCount) {
      return AprsParseResult.failure(
        AprsParseError(
          AprsParseErrorCode.tooFewFields,
          detail: '${fields.length}',
          raw: raw,
        ),
      );
    }

    final _FieldSet set = _locateFields(fields);

    if (set.callsign.isEmpty) {
      return AprsParseResult.failure(
        AprsParseError(AprsParseErrorCode.noCallsign, raw: raw),
      );
    }

    // ---- 度分 → 十进制 ---------------------------------------------------
    final double? latitude =
        GeoMath.dmToDecimal(set.lat, hemisphere: set.latHemi);
    if (latitude == null || latitude.abs() > 90) {
      return AprsParseResult.failure(
        AprsParseError(
          AprsParseErrorCode.badLatitude,
          detail: set.lat,
          raw: raw,
        ),
      );
    }
    final double? longitude =
        GeoMath.dmToDecimal(set.lon, hemisphere: set.lonHemi);
    if (longitude == null || longitude.abs() > 180) {
      return AprsParseResult.failure(
        AprsParseError(
          AprsParseErrorCode.badLongitude,
          detail: set.lon,
          raw: raw,
        ),
      );
    }

    final String callsign = set.callsign.toUpperCase();
    final String checksumField =
        checksum.hasChecksum ? '*${checksum.claimedHex}' : '';

    final AprsStation station = AprsStation(
      raw: raw,
      callsign: callsign,
      utcTime: set.time,
      utcDate: set.date,
      statusRaw: set.status,
      statusValid: set.status == 'A'
          ? true
          : set.status == 'V'
              ? false
              : null,
      latitudeRaw: set.lat,
      latitudeHemisphere: set.latHemi,
      longitudeRaw: set.lon,
      longitudeHemisphere: set.lonHemi,
      latitude: latitude,
      longitude: longitude,
      altitudeMeters: int.tryParse(set.altitude),
      courseDegrees: int.tryParse(set.course),
      distanceMeters: int.tryParse(set.distance),
      distanceRaw: set.distance,
      iconRaw: set.icon,
      claimedChecksum: checksum.claimedHex,
      computedChecksum: checksum.computedHex,
      checksumValid: checksum.valid,
      receivedAt: receivedAt ?? DateTime.now(),
      receiveSeq: receiveSeq,
      parsedFieldCount: set.count,
      fieldCountAnomaly: set.anomaly,
      callsignSuspicious: !callsignPattern.hasMatch(callsign),
      softError: softError,
      // 固定 14 项，序号与协议文档一致。
      rawFields: <String>[
        r'$' + sentenceId,
        set.time,
        set.status,
        set.lat,
        set.latHemi,
        set.lon,
        set.lonHemi,
        set.altitude,
        set.course,
        set.date,
        set.distance,
        callsign,
        set.icon,
        checksumField,
      ],
    );

    return AprsParseResult.success(station);
  }

  /// 把逗号字段定位到协议语义上。
  ///
  /// * 12 个及以上：按位置取（标准情形）；
  /// * 8~11 个：**左锚定**前 6 个定位字段、**右锚定**呼号与图标，
  ///   中间段用「6 位 ddmmyy」正则找出日期，其余按相邻位置尽力填充，
  ///   并标记 [AprsStation.fieldCountAnomaly]。
  ///
  /// 依据：实测日志里字段数异常都是「采集/转发时丢了一个逗号」，
  /// 坐标与呼号本身仍然有效，丢掉整条太浪费。
  static _FieldSet _locateFields(List<String> fields) {
    String at(int i) => (i >= 0 && i < fields.length) ? fields[i].trim() : '';
    final int n = fields.length;

    if (n >= standardFieldCount) {
      return _FieldSet(
        time: at(0),
        status: at(1).toUpperCase(),
        lat: at(2),
        latHemi: at(3).toUpperCase(),
        lon: at(4),
        lonHemi: at(5).toUpperCase(),
        altitude: at(6),
        course: at(7),
        date: at(8),
        distance: at(9),
        callsign: at(10),
        icon: at(11),
        count: n,
        anomaly: n != standardFieldCount,
      );
    }

    final String time = at(0);
    final String status = at(1).toUpperCase();
    final String lat = at(2);
    final String latHemi = at(3).toUpperCase();
    final String lon = at(4);
    final String lonHemi = at(5).toUpperCase();
    final String callsign = at(n - 2);
    final String icon = at(n - 1);

    final List<String> middle = <String>[
      for (int i = 6; i <= n - 3; i++) at(i),
    ];

    String altitude = '';
    String course = '';
    String date = '';
    String distance = '';

    int dateIndex = middle.indexWhere(_looksLikeDate);
    final bool dateFound = dateIndex >= 0;
    if (!dateFound) dateIndex = middle.length;

    // 日期左边（越靠右越可能是航向，再往左是海拔）
    final List<String> left = middle.sublist(0, dateIndex);
    if (left.isNotEmpty) course = left.last;
    if (left.length >= 2) altitude = left[left.length - 2];

    // 日期右边（第一位是距离）
    if (dateFound) {
      date = middle[dateIndex];
      final List<String> right = middle.sublist(dateIndex + 1);
      if (right.isNotEmpty) distance = right.first;
    } else if (middle.isNotEmpty) {
      // 完全找不到日期：把最后一段当日期候选，保证 UI 不会全空。
      date = middle.last;
    }

    return _FieldSet(
      time: time,
      status: status,
      lat: lat,
      latHemi: latHemi,
      lon: lon,
      lonHemi: lonHemi,
      altitude: altitude,
      course: course,
      date: date,
      distance: distance,
      callsign: callsign,
      icon: icon,
      count: n,
      anomaly: true,
    );
  }

  /// `290625` 这样的 6 位日期（含合法性检查，避免把 `000050` 当日期）。
  static bool _looksLikeDate(String value) {
    if (value.length != 6) return false;
    if (!RegExp(r'^[0-9]{6}$').hasMatch(value)) return false;
    final int day = int.parse(value.substring(0, 2));
    final int month = int.parse(value.substring(2, 4));
    return day >= 1 && day <= 31 && month >= 1 && month <= 12;
  }

  /// `ddmmyy` + `hhmmss` → UTC [DateTime]；非法返回 null。
  static DateTime? combineUtc(String date, String time) {
    if (date.length != 6 || time.length != 6) return null;
    final int? day = int.tryParse(date.substring(0, 2));
    final int? month = int.tryParse(date.substring(2, 4));
    final int? year = int.tryParse(date.substring(4, 6));
    final int? hour = int.tryParse(time.substring(0, 2));
    final int? minute = int.tryParse(time.substring(2, 4));
    final int? second = int.tryParse(time.substring(4, 6));
    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;
    try {
      return DateTime.utc(2000 + year, month, day, hour, minute, second);
    } on ArgumentError {
      return null;
    }
  }

  static String _stripLineEnding(String line) {
    String s = line;
    while (s.endsWith('\n') || s.endsWith('\r')) {
      s = s.substring(0, s.length - 1);
    }
    return s.trim();
  }
}
