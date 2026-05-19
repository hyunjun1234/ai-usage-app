#!/usr/bin/env python3
"""Renders menu.png — an illustration of AI Usage's right-click menu (README)."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 2  # render at 2x for crispness

def px(v): return int(round(v * S))

MENU_W, RADIUS, INSET = 236, 7, 16
ROW_H, SEP_H, PAD_V, MARGIN = 26, 11, 5, 28

ITEMS = [
    ("사용량 보기", False),
    ("지금 새로고침", False),
    ("Claude.ai 로그인", False),
    (None, False),
    ("메뉴 막대 표시", True),
    ("표시할 도구", True),
    ("갱신 주기", True),
    ("로그인 시 자동 실행", False),
    (None, False),
    ("AI Usage 정보", False),
    ("종료", False),
]

menu_h = PAD_V * 2 + sum(SEP_H if t is None else ROW_H for t, _ in ITEMS)
CW, CH = MENU_W + MARGIN * 2, menu_h + MARGIN * 2

font = None
for path, idx in [("/System/Library/Fonts/AppleSDGothicNeo.ttc", 3),
                   ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 0),
                   ("/System/Library/Fonts/Helvetica.ttc", 0)]:
    try:
        font = ImageFont.truetype(path, px(13), index=idx)
        break
    except Exception:
        continue
if font is None:
    font = ImageFont.load_default()

img = Image.new("RGBA", (px(CW), px(CH)), (0, 0, 0, 0))
mx0, my0 = px(MARGIN), px(MARGIN)
mx1, my1 = mx0 + px(MENU_W), my0 + px(menu_h)

# soft drop shadow
shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    [mx0, my0 + px(5), mx1, my1 + px(5)], radius=px(RADIUS), fill=(0, 0, 0, 130))
img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(px(9))))

d = ImageDraw.Draw(img)
d.rounded_rectangle([mx0, my0, mx1, my1], radius=px(RADIUS),
                    fill=(48, 48, 50, 255), outline=(82, 82, 86, 255), width=1)

y = my0 + px(PAD_V)
for text, has_sub in ITEMS:
    if text is None:
        ly = y + px(SEP_H) // 2
        d.line([mx0 + px(9), ly, mx1 - px(9), ly], fill=(80, 80, 84, 255), width=1)
        y += px(SEP_H)
        continue
    bbox = d.textbbox((0, 0), text, font=font)
    ty = y + (px(ROW_H) - (bbox[3] - bbox[1])) // 2 - bbox[1]
    d.text((mx0 + px(INSET), ty), text, font=font, fill=(238, 238, 240, 255))
    if has_sub:
        cx, cyc, s = mx1 - px(15), y + px(ROW_H) // 2, px(3.2)
        d.polygon([(cx, cyc - s), (cx + s, cyc), (cx, cyc + s)], fill=(155, 155, 160, 255))
    y += px(ROW_H)

img.save("menu.png")
print("menu.png", img.size)
