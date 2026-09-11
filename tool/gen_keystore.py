#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 / 打印 Android 签名 keystore（无需安装 JDK，用 Python 直接产出 PKCS12）。

为什么要这个脚本而不是 keytool：
    keytool 需要完整 JDK（约 185 MB），而 Android Gradle Plugin 与 apksigner
    都同时支持 **PKCS12** 格式，Python 的 cryptography 库可以直接产出，
    在没有 JDK 的机器上（比如 CI 容器、或者只想快速配一次签名）更省事。
    当然，你习惯用 keytool 也完全可以，见下方注释里的等价命令。

用法：
    # 生成新 keystore（会打印密码与 base64，请立刻抄下来）
    python3 tool/gen_keystore.py --out android/keystore/release.keystore

    # 只把已有的 keystore 转成 base64（配 Secret 用）
    python3 tool/gen_keystore.py --base64-only android/keystore/release.keystore

等价的 keytool 命令（如果你更信任 JDK）：
    keytool -genkeypair -v -keystore release.keystore -storetype PKCS12 \\
      -keyalg RSA -keysize 2048 -validity 10000 -alias pkwdwpl \\
      -storepass '<密码>' -keypass '<密码>' \\
      -dname "CN=BG7LZQ, OU=Amateur Radio, O=PKWDWPL Lite, C=CN"

配 GitHub Secrets（本脚本会打印可直接粘贴的值）：
    ANDROID_KEYSTORE_BASE64      ← base64 后的 keystore（整行）
    ANDROID_KEYSTORE_PASSWORD    ← 上一步的密码
"""
from __future__ import annotations

import argparse
import base64
import os
import secrets
import string
import sys

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives.serialization import pkcs12
    from cryptography.x509.oid import NameOID
except ImportError:  # pragma: no cover
    print("需要 cryptography：pip install cryptography", file=sys.stderr)
    sys.exit(1)
import datetime


def random_password(length: int = 32) -> str:
    """生成只含字母数字的强密码（避免 shell / YAML / Gradle 转义问题）。"""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def to_base64(path: str) -> str:
    with open(path, "rb") as handle:
        return base64.b64encode(handle.read()).decode("ascii")


def generate(out_path: str, password: str, alias: str, common_name: str,
             organization: str, validity_days: int, key_size: int) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)

    key = rsa.generate_private_key(public_exponent=65537, key_size=key_size)
    name = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "Amateur Radio"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, organization),
        x509.NameAttribute(NameOID.COUNTRY_NAME, "CN"),
    ])

    now = datetime.datetime.now(datetime.timezone.utc)
    certificate = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)  # 自签名
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=validity_days))
        .add_extension(
            x509.BasicConstraints(ca=False, path_length=None), critical=True
        )
        .sign(key, hashes.SHA256())
    )

    blob = pkcs12.serialize_key_and_certificates(
        name=alias.encode("utf-8"),
        key=key,
        cert=certificate,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(password.encode("utf-8")),
    )

    with open(out_path, "wb") as handle:
        handle.write(blob)

    print(f"✅ 已生成 keystore：{out_path}")
    print(f"   格式 PKCS12 / RSA {key_size} / 有效期 {validity_days} 天 / 别名 {alias}")
    print(f"   文件大小 {len(blob)} bytes")


def main() -> int:
    parser = argparse.ArgumentParser(description="生成或转换 Android 签名 keystore")
    parser.add_argument("--out", default="android/keystore/release.keystore",
                        help="输出路径（默认 android/keystore/release.keystore）")
    parser.add_argument("--alias", default="pkwdwpl", help="key 别名，默认 pkwdwpl")
    parser.add_argument("--password", help="指定密码；不填则随机生成一个 32 位强密码")
    parser.add_argument("--cn", default="BG7LZQ", help="证书 CN，默认 BG7LZQ")
    parser.add_argument("--org", default="PKWDWPL Lite", help="证书 O")
    parser.add_argument("--validity-days", type=int, default=10000,
                        help="有效期天数，默认 10000（约 27 年；Google Play 要求至少到 2033）")
    parser.add_argument("--key-size", type=int, default=2048, help="RSA 位数，默认 2048")
    parser.add_argument("--base64-only", metavar="KEYSTORE",
                        help="不生成，只把已有 keystore 转成 base64")
    parser.add_argument("--quiet", action="store_true", help="不打印密码与 base64")
    args = parser.parse_args()

    if args.base64_only:
        if not os.path.exists(args.base64_only):
            print(f"找不到文件：{args.base64_only}", file=sys.stderr)
            return 1
        value = to_base64(args.base64_only)
        print(f"# {args.base64_only}  →  {len(value)} 字符")
        print(value)
        return 0

    if os.path.exists(args.out):
        print(f"⚠️  {args.out} 已存在。签名密钥一旦更换，已发布用户将无法覆盖安装升级！")
        print("   确要重建，请先备份旧文件并手动删除它。")
        return 1

    password = args.password or random_password()
    generate(args.out, password, args.alias, args.cn, args.org,
             args.validity_days, args.key_size)

    if not args.quiet:
        value = to_base64(args.out)
        line = "=" * 74
        print()
        print(line)
        print("  请立刻抄下这些信息（GitHub 不会再次显示 Secret 的值）")
        print(line)
        print(f"  别名 KEY_ALIAS                : {args.alias}")
        print(f"  密码 ANDROID_KEYSTORE_PASSWORD: {password}")
        print(f"  keystore 文件                  : {os.path.abspath(args.out)}")
        print()
        print(f"  ANDROID_KEYSTORE_BASE64（{len(value)} 字符）:")
        print(value)
        print(line)
        print("  ⚠️ keystore 与密码一旦丢失，将无法再发布可覆盖安装的升级包。")
        print("    请把本文件 + 密码存到密码管理器 / 私有网盘，不要提交到 git。")
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
