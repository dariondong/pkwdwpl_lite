# R8 / ProGuard 规则（当前 release 未开启 minify，先留作备用）
#
# 若要开启 `isMinifyEnabled = true`，蓝牙插件通过 MethodChannel/EventChannel
# 反射调用的入口不能被裁掉：
-keep class com.angie.flutterbluetoothserialplus.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# 保留 shared_preferences / permission_handler 的插件入口
-keep class io.flutter.plugins.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn io.flutter.embedding.**
