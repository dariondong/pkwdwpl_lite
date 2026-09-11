#!/usr/bin/env python3
"""校验 pubspec.yaml 的 version 与 lib/core/app_info.dart 是否一致。

发版前跑一次（CI 里也会跑），避免出现「APK 里显示的版本号和 pubspec 不一致」。

    python3 tool/sync_version.py            # 只校验
    python3 tool/sync_version.py 1.0.1      # 校验并把两边都改成 1.0.1(+N)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
APP_INFO = ROOT / "lib" / "core" / "app_info.dart"


def read_pubspec_version() -> tuple[str, str]:
    text = PUBSPEC.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", text, re.M)
    if not match:
        raise SystemExit("pubspec.yaml 里没有找到 `version: X.Y.Z+N`")
    return match.group(1), match.group(2)


def read_app_info_version() -> tuple[str, str]:
    text = APP_INFO.read_text(encoding="utf-8")
    version = re.search(r"appVersion\s*=\s*'([^']+)'", text)
    build = re.search(r"buildNumber\s*=\s*'([^']*)'", text)
    if not version or not build:
        raise SystemExit("lib/core/app_info.dart 里没有找到 appVersion / buildNumber")
    return version.group(1), build.group(1)


def write_versions(version: str, build: str) -> None:
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    pubspec = re.sub(
        r"^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+\s*$",
        f"version: {version}+{build}",
        pubspec,
        flags=re.M,
    )
    PUBSPEC.write_text(pubspec, encoding="utf-8")

    info = APP_INFO.read_text(encoding="utf-8")
    info = re.sub(r"appVersion\s*=\s*'[^']+'", f"appVersion = '{version}'", info)
    info = re.sub(r"buildNumber\s*=\s*'[^']*'", f"buildNumber = '{build}'", info)
    APP_INFO.write_text(info, encoding="utf-8")


def main() -> int:
    pubspec_version, pubspec_build = read_pubspec_version()
    app_version, app_build = read_app_info_version()

    if len(sys.argv) > 1:
        target = sys.argv[1].lstrip("v")
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", target):
            raise SystemExit(f"版本号格式不对: {target}（应为 X.Y.Z）")
        build = sys.argv[2] if len(sys.argv) > 2 else pubspec_build
        write_versions(target, build)
        print(f"已同步: pubspec.yaml 与 app_info.dart → {target}+{build}")
        return 0

    ok = (pubspec_version, pubspec_build) == (app_version, app_build)
    print(f"pubspec.yaml      : {pubspec_version}+{pubspec_build}")
    print(f"app_info.dart     : {app_version}+{app_build}")
    if not ok:
        print("❌ 两边版本号不一致，跑 `python3 tool/sync_version.py <版本号>` 修正")
        return 1
    print("✅ 一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
