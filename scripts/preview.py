#!/usr/bin/env python3
"""
生成 fcitx5 候选窗的主题预览图。

按 fcitx5 classicui 的实际布局规则渲染：面板背景（九宫格拉伸）、
候选词、序号标签、注释文本、选中候选的高亮底色。

用法：
    python3 scripts/preview.py [--theme wechat|wechat-dark] [-o 输出路径]
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 微信官方配色
WECHAT_GREEN = (7, 193, 96)


def parse_theme(theme_dir):
    """
    从 theme.conf 读取我们关心的键。

    theme.conf 是 ini 风格但**扁平**（没有分段），所有键都在顶层，
    因此这里按「最后一个出现的同名键」覆盖的规则解析。
    """
    conf = {}
    path = os.path.join(theme_dir, "theme.conf")
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("["):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    return conf


def parse_margins(theme_dir, section):
    """从 theme.conf 的 [Section] 中读取 Left/Right/Top/Bottom。"""
    path = os.path.join(theme_dir, "theme.conf")
    result = {"Left": 0, "Right": 0, "Top": 0, "Bottom": 0}
    in_section = False
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("["):
                in_section = (line == f"[{section}]")
                continue
            if not in_section or not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                if k.strip() in result:
                    try:
                        result[k.strip()] = int(v.strip())
                    except ValueError:
                        pass
    return result


def hex_to_rgb(s, default=(0, 0, 0)):
    s = (s or "").strip()
    if not s.startswith("#"):
        return default
    s = s[1:]
    if len(s) == 8:          # AARRGGBB
        s = s[2:] + s[:2] if False else s[2:]
    if len(s) == 6:
        return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))
    return default


def find_font(*candidates):
    """在系统里找一个可用的中文字体文件。"""
    for name in candidates:
        try:
            out = subprocess.run(["fc-match", "-f", "%{file}", name],
                                 capture_output=True, text=True, timeout=15).stdout.strip()
            if out and os.path.exists(out):
                return out
        except Exception:
            continue
    return None


def render_svg(svg_path, width, height):
    """用 rsvg-convert 把 SVG 渲染成 RGBA 图像。"""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        out = tmp.name
    try:
        subprocess.run(
            ["rsvg-convert", "-w", str(width), "-h", str(height),
             "-o", out, svg_path],
            check=True, capture_output=True, timeout=30)
        return Image.open(out).convert("RGBA")
    finally:
        if os.path.exists(out):
            os.unlink(out)


def nine_slice(base, margin, target_w, target_h):
    """
    模拟 fcitx5 的九宫格拉伸：
    四角保持原样，四条边拉伸，中间区域平铺拉伸。

    切片规则与 fcitx5 一致（见 fcitx5 src/ui/classic/theme.cpp createImage）：
        sourceX = {0, marginLeft, width - marginRight, width}
        sourceY = {0, marginTop,  height - marginBottom,  height}
    """
    m = margin
    src = base
    sw, sh = src.size
    tw, th = target_w, target_h
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    resample = Image.Resampling.LANCZOS

    # 四角
    canvas.alpha_composite(src.crop((0, 0, m, m)), (0, 0))
    canvas.alpha_composite(src.crop((sw - m, 0, sw, m)), (tw - m, 0))
    canvas.alpha_composite(src.crop((0, sh - m, m, sh)), (0, th - m))
    canvas.alpha_composite(src.crop((sw - m, sh - m, sw, sh)), (tw - m, th - m))

    # 上边 / 下边：水平拉伸
    if sw > 2 * m:
        top = src.crop((m, 0, sw - m, m)).resize((max(tw - 2 * m, 1), m), resample)
        canvas.alpha_composite(top, (m, 0))
        bottom = src.crop((m, sh - m, sw - m, sh)).resize((max(tw - 2 * m, 1), m), resample)
        canvas.alpha_composite(bottom, (m, th - m))

    # 左边 / 右边：垂直拉伸
    if sh > 2 * m:
        left = src.crop((0, m, m, sh - m)).resize((m, max(th - 2 * m, 1)), resample)
        canvas.alpha_composite(left, (0, m))
        right = src.crop((sw - m, m, sw, sh - m)).resize((m, max(th - 2 * m, 1)), resample)
        canvas.alpha_composite(right, (tw - m, m))

    # 中间：拉伸
    if tw > 2 * m and th > 2 * m:
        mid = src.crop((m, m, sw - m, sh - m)).resize((tw - 2 * m, th - 2 * m), resample)
        canvas.alpha_composite(mid, (m, m))
    return canvas


def build_preview(theme_name, out_path):
    theme_dir = os.path.join(REPO, "themes", theme_name)
    conf = parse_theme(theme_dir)

    normal = hex_to_rgb(conf.get("NormalColor", "#353535"))
    label_color = hex_to_rgb(conf.get("CandidateLabelColor", "#888888"))
    comment_color = hex_to_rgb(conf.get("CandidateCommentColor", "#888888"))
    hl_text = hex_to_rgb(conf.get("HighlightCandidateColor", "#FFFFFF"))
    hl_label = hex_to_rgb(conf.get("HighlightCandidateLabelColor", "#FFFFFF"))
    hl_comment = hex_to_rgb(conf.get("HighlightCandidateCommentColor", "#D9F2E4"))

    # 面板与高亮的九宫格边界（与真实渲染一致）
    bg_margin = parse_margins(theme_dir, "InputPanel/Background/Margin")
    hl_margin = parse_margins(theme_dir, "InputPanel/Highlight/Margin")

    font_path = find_font("Noto Sans CJK SC", "Noto Sans CJK", "WenQuanYi Zen Hei")
    if not font_path:
        print("找不到中文字体，无法生成预览", file=sys.stderr)
        return False
    emoji_path = find_font("Noto Color Emoji", "Noto Emoji")

    cand_font = ImageFont.truetype(font_path, 26)
    label_font = ImageFont.truetype(font_path, 15)
    comment_font = ImageFont.truetype(font_path, 14)

    # emoji 字体：位图 CBDT 字体（如 Noto Color Emoji）PIL 无法渲染，
    # 加载失败时回退到中文字体（预览中 emoji 会显示为占位符，
    # 但不影响主题本身的验证）。
    emoji_font = cand_font
    if emoji_path:
        try:
            ImageFont.truetype(emoji_path, 26)
            emoji_font = ImageFont.truetype(emoji_path, 26)
        except OSError:
            pass

    # 候选数据（取自 rime_ice 实际候选）。
    # 注：真实环境由 fcitx5 用 Noto Color Emoji 渲染 emoji；
    # 预览环境无矢量 emoji 字体，故不放入 emoji 候选以免出现方框。
    candidates = [
        ("你好", "ni hao"),
        ("拟好", "ni hao"),
        ("你", "ni"),
        ("尼", "ni"),
        ("拟", "ni"),
    ]

    pad = 26                      # 面板外留白（模拟阴影区）
    text_h = 34                   # 候选行高
    hl_h = 30                     # 高亮块高
    sep = 16                      # 候选之间的间距
    label_w = 20                  # 序号宽度

    def is_emoji(text):
        return bool(text) and all(ord(c) > 0x2500 for c in text)

    def measure(text, comment):
        f = emoji_font if is_emoji(text) else cand_font
        w = f.getlength(text)
        if comment:
            w += comment_font.getlength(comment) + 8
        return int(w) + label_w + 8

    widths = [measure(t, c) for t, c in candidates]
    panel_w = int(sum(widths)) + sep * (len(candidates) - 1) + 28
    panel_h = text_h + 20

    img_w = panel_w + pad * 2
    img_h = panel_h + pad * 2
    canvas = Image.new("RGBA", (img_w, img_h), (0, 0, 0, 0))

    # 面板背景：九宫格 SVG（按 theme.conf 的 margin 切片）
    panel_svg = os.path.join(theme_dir, "panel.svg")
    if os.path.exists(panel_svg):
        base = render_svg(panel_svg, 56, 56)
        m = bg_margin["Left"]
        bg = nine_slice(base, m, panel_w, panel_h)
    else:
        bg = Image.new("RGBA", (panel_w, panel_h), (255, 255, 255, 255))
    canvas.alpha_composite(bg, (pad, pad))

    draw = ImageDraw.Draw(canvas)

    # 选中高亮块（第一个候选），按 highlight.svg 的真实尺寸与 margin 渲染
    hl_svg = os.path.join(theme_dir, "highlight.svg")
    x = pad + 14
    y = pad + 10
    first_text, first_comment = candidates[0]
    first_w = measure(first_text, first_comment)
    if os.path.exists(hl_svg):
        hbase = render_svg(hl_svg, 32, 32)
        m = hl_margin["Left"]
        hl = nine_slice(hbase, m, first_w + 6, hl_h)
        canvas.alpha_composite(hl, (x - 6, y - 2))

    # 逐个绘制候选
    for i, (text, comment) in enumerate(candidates):
        selected = (i == 0)
        tc = hl_text if selected else normal
        lc = hl_label if selected else label_color
        cc = hl_comment if selected else comment_color
        cf = emoji_font if is_emoji(text) else cand_font

        # 序号
        draw.text((x, y + 8), str(i + 1), font=label_font, fill=lc)
        tx = x + label_w

        # 候选词
        draw.text((tx, y), text, font=cf, fill=tc)
        tw = cf.getlength(text)
        if comment:
            draw.text((tx + tw + 8, y + 10), comment, font=comment_font, fill=cc)
        x += widths[i] + sep

    canvas.save(out_path)
    print(f"已生成预览：{out_path}")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", default="wechat", choices=["wechat", "wechat-dark"])
    ap.add_argument("-o", "--output", default=None)
    args = ap.parse_args()

    out = args.output or os.path.join(REPO, "docs", f"preview-{args.theme}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if build_preview(args.theme, out):
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
