#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Story 1080x1920 do Bora: ou uma foto real com pergunta por cima, ou so a
pergunta em cima de um fundo da marca (verde -> laranja). A API de stories nao
poe autocolantes, por isso a pergunta vai ESCRITA na imagem, por PIL.

Uso:
  story_pergunta.py --pergunta "O que pedes hoje na Guarda?" --logo bora_logo.png
                    [--foto cena.jpg] [--rodape "Código BEMVINDO no primeiro pedido"]
                    --saida story.jpg
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import sys as _sys
if '/opt/data/social' not in _sys.path:
    _sys.path.insert(0, '/opt/data/social')
from bora_qr import colar_qr as _colar_qr

VERDE = (22, 163, 74)
LARANJA = (249, 115, 22)
BRANCO = (255, 255, 255)
W, H = 1080, 1920
INTER = "/opt/data/social/fontes/Inter-VariableFont.ttf"
DEJAVU_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
DEJAVU = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def fonte(tam, peso="ExtraBold"):
    if os.path.isfile(INTER):
        f = ImageFont.truetype(INTER, tam)
        try:
            f.set_variation_by_name(peso)
        except Exception:                                        # noqa: BLE001
            pass
        return f
    return ImageFont.truetype(DEJAVU_B if peso != "Medium" else DEJAVU, tam)


def quebrar(draw, texto, f, largura):
    linhas, atual = [], ""
    for palavra in texto.split():
        teste = (atual + " " + palavra).strip()
        if draw.textlength(teste, font=f) <= largura or not atual:
            atual = teste
        else:
            linhas.append(atual)
            atual = palavra
    if atual:
        linhas.append(atual)
    return linhas


def fundo_marca():
    im = Image.new("RGBA", (W, H), VERDE + (255,))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        cor = tuple(int(VERDE[i] * (1 - t * 0.55) + LARANJA[i] * (t * 0.55)) for i in range(3))
        d.line([(0, y), (W, y)], fill=cor + (255,))
    # bolhas suaves para nao ficar liso
    bolhas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    db = ImageDraw.Draw(bolhas)
    for cx, cy, r, a in [(180, 420, 260, 40), (900, 300, 200, 35), (760, 1500, 320, 45), (200, 1650, 180, 30)]:
        db.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, a))
    bolhas = bolhas.filter(ImageFilter.GaussianBlur(60))
    return Image.alpha_composite(im, bolhas)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--pergunta", required=True)
    p.add_argument("--foto", default="")
    p.add_argument("--logo", required=True)
    p.add_argument("--rodape", default="Código BEMVINDO no primeiro pedido")
    p.add_argument("--origem", default="qr-story")
    p.add_argument("--saida", required=True)
    a = p.parse_args()

    # B8 (2026-11-01, stories-em-breve): ultima porta antes da montagem. A frase
    # e a foto passam pela regra unica (lojas_permitidas.py -> RPC
    # social_lojas_permitidas). Loja em breve/inativa/excluida, ou base sem
    # resposta com foto de loja: a story NAO se monta.
    import lojas_permitidas as lp
    c, m = lp.verificar_texto(a.pergunta)
    if c != lp.OK:
        print("LOJA NAO PERMITIDA na pergunta: %s" % m, file=sys.stderr)
        return 2
    if a.foto:
        ok, _com_base = lp.filtrar_fotos([a.foto])
        if not ok:
            print("LOJA NAO PERMITIDA na foto %s (dono: %s)" % (a.foto, lp.dono_da_foto(a.foto)), file=sys.stderr)
            return 2

    if a.foto and os.path.isfile(a.foto):
        im = Image.open(a.foto).convert("RGBA")
        w, h = im.size
        esc = max(W / w, H / h)
        im = im.resize((int(w * esc), int(h * esc)), Image.LANCZOS)
        im = im.crop(((im.size[0] - W) // 2, int((im.size[1] - H) * 0.4), (im.size[0] - W) // 2 + W, int((im.size[1] - H) * 0.4) + H))
        veu = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dv = ImageDraw.Draw(veu)
        for y in range(H):
            alfa = int(200 * max(0, (y - H * 0.45) / (H * 0.55)) ** 1.2) if y > H * 0.45 else (int(70 * (1 - y / (H * 0.2))) if y < H * 0.2 else 0)
            dv.line([(0, y), (W, y)], fill=(0, 0, 0, min(alfa, 200)))
        im = Image.alpha_composite(im, veu)
        com_foto = True
    else:
        im = fundo_marca()
        com_foto = False

    d = ImageDraw.Draw(im)
    margem = 84
    largura = W - 2 * margem

    # logo do Bora em cima (pastilha branca)
    lg = Image.open(a.logo).convert("RGBA")
    alt = 132
    lg = lg.resize((int(lg.size[0] * alt / lg.size[1]), alt), Image.LANCZOS)
    past = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(past).rounded_rectangle([margem - 20, 150 - 20, margem + lg.size[0] + 20, 150 + alt + 20], radius=28, fill=(255, 255, 255, 235))
    im = Image.alpha_composite(im, past)
    im.alpha_composite(lg, (margem, 150))
    d = ImageDraw.Draw(im)

    # pergunta: grande, ao centro se for fundo de marca; em baixo se houver foto
    f = fonte(112)
    linhas = quebrar(d, a.pergunta, f, largura)
    while len(linhas) > 4 and f.size > 64:
        f = fonte(f.size - 8)
        linhas = quebrar(d, a.pergunta, f, largura)
    alt_l = f.size + 16
    bloco = len(linhas) * alt_l
    y = (H // 2 - bloco // 2) if not com_foto else (H - 520 - bloco)
    for i, l in enumerate(linhas):
        yy = y + i * alt_l
        d.text((margem + 4, yy + 4), l, font=f, fill=(0, 0, 0, 150))
        d.text((margem, yy), l, font=f, fill=BRANCO)

    # selo BEMVINDO e rodape
    fs = fonte(44)
    lt = d.textlength(a.rodape, font=fs)
    ys = H - 330
    # O selo e SEMPRE laranja chapado. Quando nao havia foto saia branco, e o
    # portao do design kit reprovava a peca por "nenhum elemento laranja
    # chapado: a peca nao tem chamada" -- ou seja, nos dias sem foto o story
    # NUNCA podia sair, e ninguem tinha ligado as duas coisas. Cicatriz de
    # 2026-09-06: dois dias seguidos de story reprovado no cron.
    d.rounded_rectangle([margem, ys, margem + lt + 60, ys + 92], radius=46,
                        fill=LARANJA)
    d.text((margem + 30, ys + 22), a.rodape, font=fs, fill=BRANCO)
    fr = fonte(34, "Medium")
    d.text((margem, H - 200), "App Store · Google Play · boraguarda.com/baixar", font=fr, fill=(240, 250, 244))

    im = _colar_qr(im, a.origem) if a.origem else im
    im.convert("RGB").save(a.saida, "JPEG", quality=92, optimize=True)
    print("%s %dx%d" % (a.saida, W, H))


if __name__ == "__main__":
    sys.exit(main())
