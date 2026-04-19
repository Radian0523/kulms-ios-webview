"""Generate App Store promotional screenshots for KULMS+ WebView.

出力:
- 01_assignment_list.png  (1242 x 2688)  6.5インチ iPhone
- 02_textbooks.png        (1242 x 2688)  6.5インチ iPhone
- ipad_01_assignment.png  (2048 x 2732)  iPad

ソース画像: kulms-extension/docs/images/ の拡張機能スクリーンショット
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
import os

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
EXT_IMAGES = os.path.join(os.path.dirname(OUTPUT_DIR), "..", "kulms-extension", "docs", "images")

FONT_BOLD = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
FONT_REGULAR = "/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc"

SCREENSHOTS = [
    {
        "src": os.path.join(EXT_IMAGES, "assignments.png"),
        "title": "全科目の課題を\nひと目で確認",
        "subtitle": "緊急度別に色分け表示",
        "bg_top": (41, 98, 255),
        "bg_bottom": (88, 166, 255),
        "output": "01_assignment_list.png",
    },
    {
        "src": os.path.join(EXT_IMAGES, "textbooks.png"),
        "title": "教科書・参考書を\n自動で取得",
        "subtitle": "Amazonリンク付きですぐに購入可能",
        "bg_top": (109, 58, 230),
        "bg_bottom": (170, 120, 255),
        "output": "02_textbooks.png",
    },
]


def make_gradient(width, height, top_color, bottom_color):
    arr = np.zeros((height, width, 3), dtype=np.uint8)
    for c in range(3):
        arr[:, :, c] = np.linspace(top_color[c], bottom_color[c], height, dtype=np.uint8)[:, None]
    return Image.fromarray(arr)


def add_rounded_corners(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), img.size], radius=radius, fill=255)
    result = Image.new("RGBA", img.size, (0, 0, 0, 0))
    result.paste(img, mask=mask)
    return result


def add_shadow(img, offset=(0, 15), blur_radius=40, opacity=60):
    shadow = Image.new(
        "RGBA", (img.width + blur_radius * 2, img.height + blur_radius * 2), (0, 0, 0, 0)
    )
    inner = Image.new("RGBA", img.size, (0, 0, 0, opacity))
    if img.mode == "RGBA":
        inner.putalpha(img.split()[3].point(lambda p: min(p, opacity)))
    shadow.paste(inner, (blur_radius + offset[0], blur_radius + offset[1]))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur_radius))
    return shadow, blur_radius


# ============ iPhone 6.5" (1242x2688) ============
def gen_iphone(config):
    W, H = 1242, 2688
    bg = make_gradient(W, H, config["bg_top"], config["bg_bottom"]).convert("RGBA")
    draw = ImageDraw.Draw(bg)

    title_font = ImageFont.truetype(FONT_BOLD, 88)
    sub_font = ImageFont.truetype(FONT_REGULAR, 48)

    title_y = 180
    for line in config["title"].split("\n"):
        bbox = title_font.getbbox(line)
        lw = bbox[2] - bbox[0]
        draw.text(((W - lw) / 2, title_y), line, fill="white", font=title_font)
        title_y += 110

    subtitle_y = title_y + 30
    sub_bbox = sub_font.getbbox(config["subtitle"])
    sub_w = sub_bbox[2] - sub_bbox[0]
    draw.text(
        ((W - sub_w) / 2, subtitle_y),
        config["subtitle"],
        fill=(255, 255, 255, 200),
        font=sub_font,
    )

    ss = Image.open(config["src"]).convert("RGBA")
    target_w = int(W * 0.90)
    scale = target_w / ss.width
    target_h = int(ss.height * scale)
    ss = ss.resize((target_w, target_h), Image.LANCZOS)
    ss = add_rounded_corners(ss, 40)

    shadow, blur_r = add_shadow(ss, offset=(0, 15), blur_radius=40, opacity=60)
    ss_x = (W - target_w) // 2
    ss_y = 520
    bg.paste(shadow, (ss_x - blur_r, ss_y - blur_r), shadow)
    bg.paste(ss, (ss_x, ss_y), ss)

    out = os.path.join(OUTPUT_DIR, config["output"])
    bg.convert("RGB").save(out, "PNG", optimize=True)
    print(f"Saved: {out} ({W}x{H})")


# ============ iPad (2048x2732) ============
def gen_ipad():
    W, H = 2048, 2732
    bg = make_gradient(W, H, (41, 98, 255), (88, 166, 255)).convert("RGBA")
    draw = ImageDraw.Draw(bg)

    title_font = ImageFont.truetype(FONT_BOLD, 120)
    sub_font = ImageFont.truetype(FONT_REGULAR, 64)

    title = "全科目の課題を\nひと目で確認"
    subtitle = "緊急度別に色分け表示"

    title_y = 240
    for line in title.split("\n"):
        bbox = title_font.getbbox(line)
        lw = bbox[2] - bbox[0]
        draw.text(((W - lw) / 2, title_y), line, fill="white", font=title_font)
        title_y += 150

    subtitle_y = title_y + 40
    sub_bbox = sub_font.getbbox(subtitle)
    sub_w = sub_bbox[2] - sub_bbox[0]
    draw.text(
        ((W - sub_w) / 2, subtitle_y),
        subtitle,
        fill=(255, 255, 255, 200),
        font=sub_font,
    )

    src = os.path.join(EXT_IMAGES, "assignments.png")
    ss = Image.open(src).convert("RGBA")
    target_w = int(W * 0.88)
    scale = target_w / ss.width
    target_h = int(ss.height * scale)
    ss = ss.resize((target_w, target_h), Image.LANCZOS)
    ss = add_rounded_corners(ss, 50)

    shadow, blur_r = add_shadow(ss, offset=(0, 20), blur_radius=50, opacity=60)
    ss_x = (W - target_w) // 2
    ss_y = 700
    bg.paste(shadow, (ss_x - blur_r, ss_y - blur_r), shadow)
    bg.paste(ss, (ss_x, ss_y), ss)

    out = os.path.join(OUTPUT_DIR, "ipad_01_assignment.png")
    bg.convert("RGB").save(out, "PNG", optimize=True)
    print(f"Saved: {out} ({W}x{H})")


if __name__ == "__main__":
    for config in SCREENSHOTS:
        gen_iphone(config)
    gen_ipad()
    print("Done!")
