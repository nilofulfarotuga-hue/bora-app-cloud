# -*- coding: utf-8 -*-
"""Ladrilho da categoria Sobremesas — mesmo estilo flat/kawaii do cat_festas.png.
Desenhado a codigo (sem modelo generativo) para ficar determinista e no repo."""
from PIL import Image, ImageDraw

S, SS = 1024, 4
W = S * SS
img = Image.new("RGB", (W, W))
d = ImageDraw.Draw(img)

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

# ── fundo pastel lilas (mesma familia de cor do card, como no cat_festas) ──
for y in range(W):
    d.line([(0, y), (W, y)], fill=lerp((0xEC,0xDC,0xFB), (0xDC,0xC5,0xF7), y / W))

# ── card squircle com gradiente roxo-acai (AppColors.tileSobremesas) ──
M, R = int(W * 0.085), int(W * 0.20)
card = Image.new("RGB", (W - 2*M, W - 2*M))
cd = ImageDraw.Draw(card)
cw, ch = card.size
for y in range(ch):
    cd.line([(0, y), (cw, y)], fill=lerp((0x6D,0x28,0xD9), (0xA7,0x8B,0xFA), (y/ch)*0.85))
mask = Image.new("L", card.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, cw-1, ch-1], radius=R, fill=255)
img.paste(card, (M, M), mask)

# ── geometria: BOWL_TOP e a linha do bordo; a taca e a metade de BAIXO de uma
#    elipse centrada EXACTAMENTE em BOWL_TOP, para o bordo coincidir com o acai.
cx = W // 2
BOWL_W = int(W * 0.44)
BOWL_TOP = int(W * 0.455)
BOWL_H = int(W * 0.225)
rim_l, rim_r = cx - BOWL_W // 2, cx + BOWL_W // 2
rim_ry = int(W * 0.050)

# ── sombra suave por baixo da taca ──
base = img.convert("RGBA")
sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse(
    [cx - int(BOWL_W*0.60), BOWL_TOP + BOWL_H - int(W*0.030),
     cx + int(BOWL_W*0.60), BOWL_TOP + BOWL_H + int(W*0.035)],
    fill=(0x4C, 0x1D, 0x95, 80))
img = Image.alpha_composite(base, sh).convert("RGB")
d = ImageDraw.Draw(img)

# ── colher, ATRAS do acai ──
SPOON = (0xF5, 0xF3, 0xFF)
sx0 = cx + int(BOWL_W * 0.33)
d.rounded_rectangle([sx0 - int(W*0.013), BOWL_TOP - int(W*0.175),
                     sx0 + int(W*0.013), BOWL_TOP + int(W*0.010)],
                    radius=int(W*0.013), fill=SPOON)
d.ellipse([sx0 - int(W*0.034), BOWL_TOP - int(W*0.228),
           sx0 + int(W*0.034), BOWL_TOP - int(W*0.152)], fill=SPOON)

# ── acai: elipse roxa escura no bordo ──
ACAI, ACAI_HI = (0x4C, 0x1D, 0x95), (0x7C, 0x3A, 0xED)
d.ellipse([rim_l, BOWL_TOP - rim_ry, rim_r, BOWL_TOP + rim_ry], fill=ACAI)
d.ellipse([cx - int(BOWL_W*0.31), BOWL_TOP - int(rim_ry*0.60),
           cx - int(BOWL_W*0.08), BOWL_TOP + int(rim_ry*0.08)], fill=ACAI_HI)

# ── toppings ──
STRAW, STRAW_HI = (0xE1,0x1D,0x48), (0xFB,0x71,0x85)
BANANA, BANANA_HI = (0xFA,0xCC,0x15), (0xFE,0xF0,0x8A)
GRANOLA = (0xB4, 0x7C, 0x3F)
rr = int(W * 0.040)

def morango(mx, my, r):
    d.ellipse([mx-r, my-r, mx+r, my+int(r*1.20)], fill=STRAW)
    d.ellipse([mx-int(r*0.40), my-int(r*0.52), mx+int(r*0.02), my-int(r*0.04)], fill=STRAW_HI)

def banana(bx, by, r):
    d.ellipse([bx-r, by-int(r*0.78), bx+r, by+int(r*0.78)], fill=BANANA)
    d.ellipse([bx-int(r*0.42), by-int(r*0.34), bx+int(r*0.42), by+int(r*0.34)], fill=BANANA_HI)

for gx, gy, gr in [(-0.44,0.010,0.30), (-0.20,-0.026,0.26), (0.05,0.018,0.24),
                   (0.26,0.020,0.28), (0.43,-0.012,0.25)]:
    g = int(rr * gr)
    d.ellipse([cx+int(BOWL_W*gx)-g, BOWL_TOP+int(W*gy)-g,
               cx+int(BOWL_W*gx)+g, BOWL_TOP+int(W*gy)+g], fill=GRANOLA)
morango(cx - int(BOWL_W*0.30), BOWL_TOP - int(W*0.016), rr)
morango(cx + int(BOWL_W*0.14), BOWL_TOP - int(W*0.022), int(rr*0.90))
banana(cx - int(BOWL_W*0.05), BOWL_TOP + int(W*0.004), int(rr*0.84))
banana(cx + int(BOWL_W*0.33), BOWL_TOP - int(W*0.002), int(rr*0.78))

# ── taca branca: metade de BAIXO de uma elipse centrada em BOWL_TOP ──
BOWL = (0xFD, 0xF9, 0xFF)
bbox = [rim_l, BOWL_TOP - BOWL_H, rim_r, BOWL_TOP + BOWL_H]
d.pieslice(bbox, start=0, end=180, fill=BOWL)
d.ellipse([cx - int(BOWL_W*0.34), BOWL_TOP + int(W*0.038),
           cx - int(BOWL_W*0.22), BOWL_TOP + int(W*0.092)], fill=(0xFF,0xFF,0xFF))

# ── carinha kawaii, na taca branca ──
EYE, BLUSH = (0x3B, 0x24, 0x4A), (0xF9, 0xA8, 0xD4)
ey = BOWL_TOP + int(W * 0.078)
er = int(W * 0.0165)
for sx in (-1, 1):
    d.ellipse([cx + sx*int(W*0.055) - er, ey - er,
               cx + sx*int(W*0.055) + er, ey + er], fill=EYE)
    d.ellipse([cx + sx*int(W*0.098) - int(W*0.024), ey + int(W*0.014),
               cx + sx*int(W*0.098) + int(W*0.024), ey + int(W*0.046)], fill=BLUSH)
d.arc([cx - int(W*0.034), ey + int(W*0.004), cx + int(W*0.034), ey + int(W*0.056)],
      start=15, end=165, fill=EYE, width=int(W*0.010))

img.resize((S, S), Image.LANCZOS).save("assets/categories/cat_sobremesas.png", optimize=True)
print("gravado assets/categories/cat_sobremesas.png")
