#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""下载 / 同步 APRS 官方符号图标包到 assets/aprs_syms/。

移植自 APRSLocus 项目的 `tools/download_aprs_icons.py`，
命名与目录结构与那个项目**完全一致**（`<hex(表)><hex(码)>.png`），
这样两边可以共用同一套代码与资源。

用法：
    python3 tool/update_aprs_symbols.py                      # 联网补齐缺失的
    python3 tool/update_aprs_symbols.py --force              # 全量重下
    python3 tool/update_aprs_symbols.py --from ../APRSLocus  # 从本地 APRSLocus 复制

说明：官方每张图只有 24x24；不是「表 × 码」的每个组合都有图，
所以最终约 3571 张（而不是 38 × 94 = 3572）。
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import Request, urlopen

BASE = "https://aprs.tv/img"
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DST = os.path.join(ROOT, "assets", "aprs_syms")
THREADS = 16
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

# 符号表：'/'、'\'、'0'-'9'、'A'-'Z'
TABLES = [0x2F, 0x5C] + list(range(0x30, 0x3A)) + list(range(0x41, 0x5B))
# 符号码：'!' ~ '~'
CODES = list(range(0x21, 0x7F))

_lock = threading.Lock()
ok = skip = fail = 0
failures: list[str] = []


def fetch(name: str, force: bool) -> None:
    global ok, skip, fail
    path = os.path.join(DST, name)
    if os.path.exists(path) and not force:
        with _lock:
            skip += 1
        return
    try:
        req = Request(f"{BASE}/{name}", headers={"User-Agent": "Mozilla/5.0"})
        data = urlopen(req, timeout=15).read()
        if not data.startswith(PNG_MAGIC):
            with _lock:
                fail += 1
                failures.append(f"{name} (not a PNG)")
            return
        with open(path, "wb") as handle:
            handle.write(data)
        with _lock:
            ok += 1
    except Exception as exc:  # noqa: BLE001 - 逐条报告
        with _lock:
            fail += 1
            failures.append(f"{name} ({exc})")


def copy_from(source: str, force: bool) -> int:
    src = source
    if not os.path.isdir(src):
        src = os.path.join(source, "assets", "aprs_syms")
    if not os.path.isdir(src):
        print(f"找不到图标目录：{source}", file=sys.stderr)
        return 1

    os.makedirs(DST, exist_ok=True)
    copied = skipped = 0
    for name in sorted(os.listdir(src)):
        if not name.endswith(".png"):
            continue
        target = os.path.join(DST, name)
        if os.path.exists(target) and not force:
            skipped += 1
            continue
        shutil.copy2(os.path.join(src, name), target)
        copied += 1
    print(f"从 {src} 复制完成：新增/覆盖 {copied}，跳过 {skipped}")
    print(f"目标目录：{DST}")
    return report()


def report() -> int:
    total = len([f for f in os.listdir(DST) if f.endswith(".png")]) if os.path.isdir(DST) else 0
    print(f"目录内 PNG 总数：{total}")
    return 0 if total > 3000 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="下载/同步 APRS 官方符号图标包")
    parser.add_argument("--force", action="store_true", help="全量重下（不跳过已有文件）")
    parser.add_argument("--from", dest="source", help="从本地 APRSLocus 目录复制，而不是联网下载")
    args = parser.parse_args()

    if args.source:
        return copy_from(args.source, args.force)

    os.makedirs(DST, exist_ok=True)
    tasks = [f"{table:02x}{code:02x}.png" for table in TABLES for code in CODES]
    print(f"目标目录：{DST}")
    print(f"待处理 {len(tasks)} 个文件名（{len(TABLES)} 个符号表 × {len(CODES)} 个符号码）")

    with ThreadPoolExecutor(max_workers=THREADS) as executor:
        for _ in as_completed([executor.submit(fetch, t, args.force) for t in tasks]):
            pass

    print(f"done: ok={ok} skip={skip} fail={fail}")
    if failures:
        print("失败/缺失（官方素材里本来就不是每个组合都有图，属正常）：")
        for item in failures[:15]:
            print("   ", item)
        if len(failures) > 15:
            print(f"    ... 其余 {len(failures) - 15} 条省略")
    return report()


if __name__ == "__main__":
    sys.exit(main())
