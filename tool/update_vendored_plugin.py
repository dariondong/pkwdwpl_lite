#!/usr/bin/env python3
"""重新下载 flutter_bluetooth_serial_plus 到 third_party/，并自动打上 CI 兼容补丁。

    python3 tool/update_vendored_plugin.py 0.5.6

补丁内容（与 third_party/*/README_LOCAL.md 里写的一致）：
  1. 删掉插件自带的 `buildscript { classpath 'com.android.tools.build:gradle:8.1.1' }`
     （会与宿主工程的 AGP 9.x 冲突）；
  2. compileSdk 对齐到 36、JavaVersion 对齐到 17；
  3. 精简 AndroidManifest.xml（老权限加 maxSdkVersion，删掉多余的 application/activity）。
"""
from __future__ import annotations

import io
import re
import shutil
import sys
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "third_party" / "flutter_bluetooth_serial_plus"

BUILD_GRADLE = """// ---------------------------------------------------------------------------
// 本文件由 PKWDWPL Lite 项目维护（由 tool/update_vendored_plugin.py 自动生成）。
// 见同目录 README_LOCAL.md。
// ---------------------------------------------------------------------------
group 'com.angie.flutterbluetoothserialplus'
version '1.0.0'

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'

android {
    namespace 'com.angie.flutterbluetoothserialplus'
    compileSdk 36

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk 21
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }

    lint {
        disable 'InvalidPackage'
    }
}

dependencies {
    implementation 'androidx.appcompat:appcompat:1.7.1'
    implementation 'androidx.core:core:1.16.0'
}
"""

MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- 由 PKWDWPL Lite 维护：老权限加 maxSdkVersion，去掉多余的 application/activity -->
    <uses-permission
        android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" />
    <uses-permission
        android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" />
    <uses-permission
        android:name="android.permission.ACCESS_COARSE_LOCATION"
        android:maxSdkVersion="30" />
    <uses-permission
        android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.REQUEST_DISCOVERABLE" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
</manifest>
"""


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else "0.5.6"
    url = f"https://pub.dev/api/archives/flutter_bluetooth_serial_plus-{version}.tar.gz"
    print(f"下载 {url}")

    with urllib.request.urlopen(url, timeout=120) as response:
        payload = response.read()

    keep_readme = TARGET / "README_LOCAL.md"
    readme_backup = keep_readme.read_text(encoding="utf-8") if keep_readme.exists() else None

    if TARGET.exists():
        shutil.rmtree(TARGET)
    TARGET.mkdir(parents=True)

    with tarfile.open(fileobj=io.BytesIO(payload)) as tar:
        tar.extractall(TARGET)

    # 清理不需要的文件
    for relative in ("example", "helpers", "CHANGELOG.md", "android/gradle",
                     "android/settings.gradle", "android/gradle.properties"):
        path = TARGET / relative
        if path.is_dir():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()

    (TARGET / "android" / "build.gradle").write_text(BUILD_GRADLE, encoding="utf-8")
    (TARGET / "android" / "src" / "main" / "AndroidManifest.xml").write_text(
        MANIFEST, encoding="utf-8"
    )

    pubspec = TARGET / "pubspec.yaml"
    text = pubspec.read_text(encoding="utf-8")
    text = re.sub(r"dev_dependencies:\n(\s+.*\n?)+", "", text)
    pubspec.write_text(text, encoding="utf-8")

    if readme_backup:
        keep_readme.write_text(readme_backup, encoding="utf-8")

    print(f"✅ 已更新到 {version} 并打好补丁: {TARGET}")
    print("   记得跑一遍 `flutter analyze && flutter test` 确认没坏。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
