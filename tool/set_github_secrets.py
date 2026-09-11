#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把签名 keystore 配置到 GitHub 仓库的 Actions Secrets（无需 gh CLI）。

用法：
    # 需要 GitHub Token：环境变量 GITHUB_TOKEN，或 ~/.git-credentials（git 存的凭据）
    python3 tool/set_github_secrets.py --repo dariondong/pkwdwpl_lite \\
        --keystore android/keystore/release.keystore --password '<密码>'

会写入两个 Secret（与 APRSLocus 项目命名保持一致，方便沿用同一套习惯）：
    ANDROID_KEYSTORE_BASE64      keystore 的 base64
    ANDROID_KEYSTORE_PASSWORD    上面那个密码

原理：GitHub 要求用仓库公钥做 libsodium sealed box 加密后再提交，
      这里用 PyNaCl 实现（pip install pynacl）。
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.request

try:
    from nacl import encoding, public
except ImportError:  # pragma: no cover
    print("需要 PyNaCl：pip install pynacl", file=sys.stderr)
    sys.exit(1)

API = "https://api.github.com"


def read_token(explicit: str | None) -> str:
    if explicit:
        return explicit
    env = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if env:
        return env
    # 退而从 git 的凭据存储里取（https://user:TOKEN@github.com）
    cred = os.path.expanduser("~/.git-credentials")
    if os.path.exists(cred):
        with open(cred, encoding="utf-8") as handle:
            for line in handle:
                match = re.match(r"https://[^:]+:([^@]+)@github\.com", line.strip())
                if match:
                    return match.group(1)
    raise SystemExit("找不到 GitHub Token：请设置 GITHUB_TOKEN 或配置 ~/.git-credentials")


def request(token: str, method: str, url: str, payload: dict | None = None) -> dict:
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"token {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "pkwdwpl-lite-secrets")
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as response:
        body = response.read().decode("utf-8")
        return json.loads(body) if body else {}


def encrypt(public_key: str, value: str) -> str:
    """用仓库公钥做 sealed box 加密，返回 base64。"""
    pk = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
    sealed = public.SealedBox(pk).encrypt(value.encode("utf-8"))
    return base64.b64encode(sealed).decode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="配置 GitHub Actions Secrets")
    parser.add_argument("--repo", required=True, help="owner/repo")
    parser.add_argument("--keystore", required=True, help="keystore 文件路径")
    parser.add_argument("--password", required=True, help="keystore 密码")
    parser.add_argument("--name-base64", default="ANDROID_KEYSTORE_BASE64")
    parser.add_argument("--name-password", default="ANDROID_KEYSTORE_PASSWORD")
    parser.add_argument("--token", help="GitHub Token（默认从环境变量/git 凭据读取）")
    args = parser.parse_args()

    if not os.path.exists(args.keystore):
        print(f"找不到 keystore：{args.keystore}", file=sys.stderr)
        return 1

    token = read_token(args.token)
    with open(args.keystore, "rb") as handle:
        keystore_b64 = base64.b64encode(handle.read()).decode("ascii")

    key_info = request(token, "GET", f"{API}/repos/{args.repo}/actions/secrets/public-key")
    key_id = key_info["key_id"]
    public_key = key_info["key"]
    print(f"仓库公钥 key_id = {key_id}")

    for name, value in (
        (args.name_base64, keystore_b64),
        (args.name_password, args.password),
    ):
        request(token, "PUT", f"{API}/repos/{args.repo}/actions/secrets/{name}", {
            "encrypted_value": encrypt(public_key, value),
            "key_id": key_id,
        })
        print(f"  ✅ 已写入 Secret：{name}（{len(value)} 字符）")

    listing = request(token, "GET", f"{API}/repos/{args.repo}/actions/secrets")
    print(f"\n当前仓库共 {listing.get('total_count', 0)} 个 Secret：")
    for item in listing.get("secrets", []):
        print(f"   - {item['name']}  (更新于 {item.get('updated_at')})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
