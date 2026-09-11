# flutter_bluetooth_serial_plus (本地内置副本 / vendored)

- 来源：pub.dev `flutter_bluetooth_serial_plus` **0.5.6**（2026-08-07 发布）
- 上游：https://github.com/angelicadelacruzgonzalez/flutter_bluetooth_serial_plus
- 许可：MIT（见同目录 `LICENSE`）

## 为什么要内置而不是直接依赖 pub.dev？

1. 经典蓝牙 SPP 的 Flutter 插件生态目前只有这一支在维护；它的 `android/build.gradle`
   里写死了 `buildscript { classpath 'com.android.tools.build:gradle:8.1.1' }`，
   与新版 Flutter 模板使用的 AGP 9.x 同时存在时会触发 Gradle 插件版本冲突，
   CI（GitHub Actions，无 Android Studio）上排查成本很高。
2. 内置后可以把它 `compileSdk` / `JavaVersion` 与宿主工程对齐，编译结果可复现，
   不会因为 pub.dev 上游发新版而突然破坏 CI。
3. 只改了 `android/build.gradle`（删除自带 AGP classpath、对齐 compileSdk/Java 17），
   Dart API 与 Java 实现与原版 100% 一致，所以 `lib/` 里照常
   `import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';`。

## 想改回 pub.dev 官方版本？

```yaml
# pubspec.yaml
dependencies:
  # flutter_bluetooth_serial_plus:
  #   path: third_party/flutter_bluetooth_serial_plus
  flutter_bluetooth_serial_plus: ^0.5.6
```

若那时 CI 报 AGP 冲突，可在 `android/build.gradle.kts` 里加：

```kotlin
subprojects {
    buildscript {
        configurations.all { resolutionStrategy { force("com.android.tools.build:gradle:9.1.0") } }
    }
}
```

或直接切回本内置目录（推荐）。

## 升级到上游新版本

```bash
python3 tool/update_vendored_plugin.py 0.5.7   # 重新下载 + 自动打补丁
```
