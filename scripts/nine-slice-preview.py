#!/usr/bin/env python3
"""
九宫格（nine-slice）渲染对比工具。

按 fcitx5 classicui 的真实切片规则渲染 SVG 背景图，并与"朴素拉伸"
的结果并排对比 —— 这样圆角被拉伸变形的问题一眼可见。

fcitx5 的切片规则（见 src/ui/classic/theme.cpp createImage）：
    sourceX = {0, marginLeft, width - marginRight, width}
    sourceY = {0, marginTop,  height - marginBottom,  height}
四角保持原样，四边与中心区域拉伸填充。

用法：
    scripts/nine-slice-preview.py --svg themes/wechat/panel.svg \\
        --margin 14 --width 420 --height 68 --out /tmp/panel-preview.png

    # 左右上下分别指定不同 margin
    scripts/nine-slice-preview.py --svg panel.svg --margin 14 \\
        --margin-top 4 --margin-bottom 4 --width 420 --height 68 --out out.png

依赖：Pillow、rsvg-convert（apt install librsvg2-bin）
"""

import argparse
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("需要 Pillow：python3 -m pip install pillow", file=sys.stderr)
    sys.exit(1)


def render_svg(svg_path, width, height):
    """用 rsvg-convert 把 SVG 渲染成 RGBA 图像。"""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        out = tmp.name
    try:
        subprocess.run(
            ["rsvg-convert", "-w", str(width), "-h", str(height), "-o", out, svg_path],
            check=True, capture_output=True, timeout=30)
        return Image.open(out).convert("RGBA")
    finally:
        if os.path.exists(out):
            os.unlink(out)


def nine_slice(src, margin, target_w, target_h):
    """模拟 fcitx5 的九宫格拉伸。

    margin 可以是 int（四边相同）或 (left, top, right, bottom) 元组。
    """
    if isinstance(margin, int):
        ml = mt = mr = mb = margin
    else:
        ml, mt, mr, mb = margin

    sw, sh = src.size
    tw, th = target_w, target_h
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    resample = Image.Resampling.LANCZOS

    # 四角（保持原样）
    canvas.alpha_composite(src.crop((0, 0, ml, mt)), (0, 0))
    canvas.alpha_composite(src.crop((sw - mr, 0, sw, mt)), (tw - mr, 0))
    canvas.alpha_composite(src.crop((0, sh - mb, ml, sh)), (0, th - mb))
    canvas.alpha_composite(src.crop((sw - mr, sh - mb, sw, sh)), (tw - mr, th - mb))

    # 上边 / 下边：水平拉伸
    if sw > ml + mr:
        top = src.crop((ml, 0, sw - mr, mt)).resize((max(tw - ml - mr, 1), mt), resample)
        canvas.alpha_composite(top, (ml, 0))
        bottom = src.crop((ml, sh - mb, sw - mr, sh)).resize(
            (max(tw - ml - mr, 1), mb), resample)
        canvas.alpha_composite(bottom, (ml, th - mb))

    # 左边 / 右边：垂直拉伸
    if sh > mt + mb:
        left = src.crop((0, mt, ml, sh - mb)).resize((ml, max(th - mt - mb, 1)), resample)
        canvas.alpha_composite(left, (0, mt))
        right = src.crop((sw - mr, mt, sw, sh - mb)).resize(
            (mr, max(th - mt - mb, 1)), resample)
        canvas.alpha_composite(right, (tw - mr, mt))

    # 中心：拉伸
    if tw > ml + mr and th > mt + mb:
        mid = src.crop((ml, mt, sw - mr, sh - mb)).resize(
            (tw - ml - mr, th - mt - mb), resample)
        canvas.alpha_composite(mid, (ml, mt))

    return canvas


def naive_stretch(src, target_w, target_h):
    """朴素拉伸：整张图直接缩放到目标尺寸（圆角会变形）。"""
    return src.resize((target_w, target_h), Image.Resampling.LANCZOS)


def main():
    ap = argparse.ArgumentParser(description="九宫格渲染对比")
    ap.add_argument("--svg", required=True, help="SVG 文件路径")
    ap.add_argument("--margin", type=int, default=0, help="四边相同的九宫格边界")
    ap.add_argument("--margin-left", type=int)
    ap.add_argument("--margin-top", type=int)
    ap.add_argument("--margin-right", type=int)
    ap.add_argument("--margin-bottom", type=int)
    ap.add_argument("--width", type=int, default=420, help="目标宽度")
    ap.add_argument("--height", type=int, default=68, help="目标高度")
    ap.add_argument("--out", required=True, help="输出 PNG 路径")
    ap.add_argument("--no-compare", action="store_true",
                    help="只输出九宫格结果，不做对比")
    args = ap.parse_args()

    if not os.path.exists(args.svg):
        print(f"文件不存在：{args.svg}", file=sys.stderr)
        return 1

    margin = (
        args.margin_left if args.margin_left is not None else args.margin,
        args.margin_top if args.margin_top is not None else args.margin,
        args.margin_right if args.margin_right is not None else args.margin,
        args.margin_bottom if args.margin_bottom is not None else args.margin,
    )

    # 用 SVG 的固有尺寸作为源图尺寸
    probe = render_svg(args.svg, 512, 512)
    src_size = _svg_intrinsic_size(args.svg) or probe.size

    base = render_svg(args.svg, src_size[0], src_size[1])
    sliced = nine_slice(base, margin, args.width, args.height)

    if args.no_compare:
        sliced.save(args.out)
        print(f"已生成：{args.out}")
        return 0

    stretched = naive_stretch(base, args.width, args.height)

    gap = 24
    label_h = 28
    canvas = Image.new("RGBA",
                       (args.width * 2 + gap, args.height + label_h),
                       (245, 245, 245, 255))
    # 棋盘格背景，便于看清透明区域
    checker = Image.new("RGBA", (args.width, args.height), (255, 255, 255, 255))
    d = ImageDraw.Draw(checker)
    for y in range(0, args.height, 12):
        for x in range(0, args.width, 12):
            if ((x // 12) + (y // 12)) % 2 == 0:
                d.rectangle([x, y, x + 11, y + 11], fill=(228, 228, 228, 255))

    canvas.alpha_composite(checker, (0, label_h))
    canvas.alpha_composite(checker, (args.width + gap, label_h))
    canvas.alpha_composite(stretched, (0, label_h))
    canvas.alpha_composite(sliced, (args.width + gap, label_h))

    draw = ImageDraw.Draw(canvas)
    draw.text((6, 8), "naive stretch (corners distorted)", fill=(180, 30, 30, 255))
    draw.text((args.width + gap + 6, 8), "nine-slice (correct)",
              fill=(20, 120, 60, 255))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    canvas.save(args.out)
    print(f"已生成对比图：{args.out}")
    print(f"  左 = 朴素拉伸，右 = 九宫格（margin={margin}）")
    return 0


def _svg_intrinsic_size(svg_path):
    """从 SVG 的 width/height 属性读出固有尺寸。"""
    import re
    try:
        with open(svg_path, encoding="utf-8") as f:
            head = f.read(2000)
    except OSError:
        return None
    m = re.search(r'<svg[^>]*\bwidth="(\d+(?:\.\d+)?)"[^>]*\bheight="(\d+(?:\.\d+)?)"', head)
    if not m:
        m = re.search(r'<svg[^>]*\bheight="(\d+(?:\.\d+)?)"[^>]*\bwidth="(\d+(?:\.\d+)?)"', head)
    if m:
        return (int(float(m.group(1))), int(float(m.group(2))))
    return None


if __name__ == "__main__":
    sys.exit(main())
