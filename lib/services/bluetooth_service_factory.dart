import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bluetooth_service.dart';
import 'bluetooth_service_io.dart';
import 'bluetooth_service_mock.dart';

/// 建立蓝牙服务实例。
///
/// * Android → [PlatformBluetoothService]（经典蓝牙 SPP）
/// * 其它平台（桌面/Web，方便调试 UI）→ [MockBluetoothService]
///
/// `forceMock: true` 用于「演示模式」开关。
BluetoothService createBluetoothService({bool forceMock = false}) {
  if (forceMock || kIsWeb) return MockBluetoothService();
  if (!Platform.isAndroid) return MockBluetoothService();
  return PlatformBluetoothService();
}
