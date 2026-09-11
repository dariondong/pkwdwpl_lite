#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 Android 启动图标（launcher），美术来自 APRS 官方符号图标包。

图标包是 24x24 的 PNG（见 assets/aprs_syms/README），这里放大后贴在圆角底色上。

用法：
    python3 tool/gen_launcher_icon.py                     # 默认：白底 + 绿环 + /j 汽车
    python3 tool/gen_launcher_icon.py --bg green          # 换成绿底（符号是绿色时对比度会变差）
    python3 tool/gen_launcher_icon.py --symbol 2f72       # 换成 /r 中继塔
    python3 tool/gen_launcher_icon.py --preview out.png   # 顺便导出一张多尺寸对照图

为什么默认是「白底 + 绿环」而不是绿底：
    APRS 符号本身带颜色，/j 汽车、/# 中继都是**绿色**，放在绿底（0x2E7D32）上
    对比度极低、远看糊成一团（实测放大到 192px 依然糊）。白底 + 品牌绿描边
    既保证符号清晰，又保留品牌色。

需要 Pillow：pip install pillow
"""
from __future__ import annotations

import argparse
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print("需要 Pillow：pip install pillow", file=sys.stderr)
    sys.exit(1)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SYMS = os.path.join(ROOT, "assets", "aprs_syms")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# name → (目标像素, 文件名)
MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

BRAND_GREEN = (0x2E, 0x7D, 0x32)
WHITE = (255, 255, 255)
LIGHT = (0xF2, 0xF4, 0xF5)


def build_icon(symbol_hex: str, size: int, bg: tuple[int, int, int],
               ring: tuple[int, int, int] | None, inner_ratio: float) -> Image.Image:
    """画一个 size×size 的图标：圆角底色 + 居中的 APRS 符号。"""
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tile)

    radius = int(size * 0.22)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=bg + (255,))
    if ring is not None:
        width = max(1, int(size * 0.045))
        draw.rounded_rectangle(
            [width // 2, width // 2, size - 1 - width // 2, size - 1 - width // 2],
            radius=radius,
            outline=ring + (255,),
            width=width,
        )

    source = Image.open(os.path.join(SYMS, f"{symbol_hex}.png")).convert("RGBA")
    inner = int(size * inner_ratio)
    # LANCZOS：24x24 放大到 192 会糊，但它比 NEAREST 的像素块更耐看；
    # 小尺寸下两者差别不大，所以在 48/72 用 NEAREST 保持锐利。
    resample = Image.NEAREST if size <= 72 else Image.LANCZOS
    upscaled = source.resize((inner, inner), resample)
    tile.alpha_composite(upscaled, ((size - inner) // 2, (size - inner) // 2))
    return tile


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 APRS 符号风格的启动图标")
    parser.add_argument("--symbol", default="2f6a", help="图标包文件名（不含 .png），默认 2f6a = /j 汽车")
    parser.add_argument("--bg", default="white", choices=["white", "green", "light"],
                        help="底色：white(默认)/green/light")
    parser.add_argument("--no-ring", action="store_true", help="不要描边")
    parser.add_argument("--inner", type=float, default=0.82, help="符号占比，默认 0.82")
    parser.add_argument("--preview", help="额外导出一张多尺寸对照图到该路径")
    args = parser.parse_args()

    if not os.path.exists(os.path.join(SYMS, f"{args.symbol}.png")):
        print(f"找不到符号：{SYMS}/{args.symbol}.png", file=sys.stderr)
        return 1

    bg = {"white": WHITE, "green": BRAND_GREEN, "light": LIGHT}[args.bg]
    ring = None
    if not args.no_ring:
        ring = BRAND_GREEN if args.bg == "white" else None

    for folder, size in MIPMAPS.items():
        target_dir = os.path.join(RES, folder)
        os.makedirs(target_dir, exist_ok=True)
        out = os.path.join(target_dir, "ic_launcher.png")
        build_icon(args.symbol, size, bg, ring, args.inner).save(out)
        print(f"  {folder:16s} {size:3d}px  → {os.path.relpath(out, ROOT)}")

    if args.preview:
        sizes = [192, 144, 96, 72, 48, 36]
        cw = sum(sizes) + 32 * (len(sizes) + 1)
        canvas = Image.new("RGB", (cw, 220), (250, 250, 250))
        x = 32
        for s in sizes:
            canvas.paste(build_icon(args.symbol, s, bg, ring, args.inner).convert("RGB"), (x, 16))
            x += s + 32
        canvas.save(args.preview)
        print(f"  预览 → {args.preview}")

    print(f"完成：符号 {args.symbol}，底色 {args.bg}，描边 {'无' if ring is None else '有'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
