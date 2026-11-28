# -*- coding: utf-8 -*-
"""Material de venda do devocional "21 dias de recomeco" da Irma Lucia (15/11/2026, ponto J decidido pela Claude.ai,
preco autorizado pelo Danilo as 15:10). Mesmas cores e letras do PDF (bordo #7A2E3A, dourado #C9A46A, Georgia + Segoe UI).

Faz, nesta pasta:
  capa-1200x1697.png            capa vertical (proporcao A5, a do PDF), com a cara da Lucia e "Personagem criado com IA"
  capa-quadrada-1080.png        imagem quadrada do produto (Hotmart)
  mockup-1-tablet-celular.png   capa no tablet + dia 1 no celular
  mockup-2-paginas-abertas.png  "Como usar" + "Dia 1" lado a lado
  mockup-3-o-que-tem-dentro.png carta da Lucia, dia 1 e a pagina de marcar os dias, em leque
  devocional-21-dias-de-recomeco-com-capa.pdf   o PDF de 14/11 com esta capa no lugar da capa so de texto
Uso: python montar_venda.py
"""
import os
import subprocess
import pymupdf
from PIL import Image, ImageDraw, ImageFilter, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
PRODUTO = os.path.dirname(AQUI)
PDF = os.path.join(PRODUTO, "devocional-21-dias-de-recomeco.pdf")
VIDEO = r"C:\BoraLocal\ConteudoIA\videos\lucia\lucia-r001.mp4"  # video aprovado; fotograma aos 11 s (sorriso, luz quente)
FONTES = r"C:\Windows\Fonts"

BORDO = (122, 46, 58)
DOURADO = (201, 164, 106)
DOURADO_ESC = (160, 122, 64)
TINTA = (43, 38, 34)
TINTA2 = (74, 66, 60)
CINZA = (138, 127, 118)
CREME = (251, 247, 241)
CREME2 = (243, 231, 214)
BRANCO = (255, 255, 255)


def f(nome, px):
    return ImageFont.truetype(os.path.join(FONTES, nome), px)


def degrade(w, h, c1, c2):
    im = Image.new("RGB", (w, h), c1)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(c1, c2)))
    return im


def centro(d, cx, y, txt, fonte, cor, espaco=0):
    if espaco:
        larg = sum(d.textlength(c, font=fonte) for c in txt) + espaco * (len(txt) - 1)
        x = cx - larg / 2
        for c in txt:
            d.text((x, y), c, font=fonte, fill=cor)
            x += d.textlength(c, font=fonte) + espaco
        return
    d.text((cx - d.textlength(txt, font=fonte) / 2, y), txt, font=fonte, fill=cor)


def mascara_arco(w, h):
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.ellipse((0, 0, w, w), fill=255)
    d.rectangle((0, w // 2, w, h), fill=255)
    return m


def foto_lucia():
    dst = os.path.join(AQUI, "_lucia-r001-11s.png")
    if not os.path.exists(dst):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", "11.0", "-i", VIDEO, "-frames:v", "1", dst], check=True)
    return Image.open(dst).convert("RGB")


def recorte(im, aspeto, y0):
    """Corta a largura toda do fotograma com a proporcao pedida, a comecar em y0."""
    w = im.width
    h = round(w / aspeto)
    y0 = max(0, min(y0, im.height - h))
    return im.crop((0, y0, w, y0 + h))


def arco_com_foto(foto, w, h, borda):
    ft = foto.resize((w, h), Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 70, 2))
    caixa = Image.new("RGBA", (w + 2 * borda, h + 2 * borda), (0, 0, 0, 0))
    ouro = Image.new("RGBA", caixa.size, DOURADO + (255,))
    caixa.paste(ouro, (0, 0), mascara_arco(*caixa.size))
    caixa.paste(ft, (borda, borda), mascara_arco(w, h))
    return caixa


def selo_ia(d, cx, y, px):
    fonte = f("seguisb.ttf", px)
    txt = "Personagem criado com IA"
    lw = d.textlength(txt, font=fonte)
    pad_x, pad_y = round(px * 0.9), round(px * 0.45)
    d.rounded_rectangle((cx - lw / 2 - pad_x, y, cx + lw / 2 + pad_x, y + px + 2 * pad_y + 4), radius=px, fill=BORDO)
    d.text((cx - lw / 2, y + pad_y - round(px * 0.08)), txt, font=fonte, fill=BRANCO)


def capa(W=1200, H=1697):
    pag = degrade(W, H, CREME, CREME2).convert("RGBA")
    d = ImageDraw.Draw(pag)
    cx = W / 2
    centro(d, cx, 78, "DEVOCIONAL  ·  21 DIAS", f("seguisb.ttf", 30), DOURADO_ESC, espaco=3)
    centro(d, cx, 128, "21 dias de", f("georgiab.ttf", 116), BORDO)
    centro(d, cx, 250, "recomeço", f("georgiab.ttf", 150), BORDO)
    centro(d, cx, 432, "um devocional com a Irmã Lúcia", f("georgiai.ttf", 50), TINTA2)
    aw, ah, b = 860, 940, 7
    arco = arco_com_foto(recorte(foto_lucia(), aw / ah, 110), aw, ah, b)
    sombra = Image.new("RGBA", (arco.width + 80, arco.height + 80), (0, 0, 0, 0))
    sombra.paste(Image.new("RGBA", arco.size, (90, 50, 30, 90)), (40, 52), mascara_arco(*arco.size))
    sombra = sombra.filter(ImageFilter.GaussianBlur(22))
    x, y = round(cx - arco.width / 2), 530
    pag.alpha_composite(sombra, (x - 40, y - 40))
    pag.alpha_composite(arco, (x, y))
    yb = y + arco.height + 26
    centro(d, cx, yb, "versículo  ·  conversa  ·  oração  ·  passo prático", f("segoeui.ttf", 31), CINZA)
    selo_ia(d, cx, yb + 62, 32)
    return pag.convert("RGB")


def quadrada():
    S = 1080
    pag = degrade(S, S, CREME, CREME2).convert("RGBA")
    d = ImageDraw.Draw(pag)
    aw, ah, b = 430, 640, 6
    arco = arco_com_foto(recorte(foto_lucia(), aw / ah, 90), aw, ah, b)
    sombra = Image.new("RGBA", (arco.width + 60, arco.height + 60), (0, 0, 0, 0))
    sombra.paste(Image.new("RGBA", arco.size, (90, 50, 30, 90)), (30, 40), mascara_arco(*arco.size))
    pag.alpha_composite(sombra.filter(ImageFilter.GaussianBlur(18)), (40, 150))
    pag.alpha_composite(arco, (70, 180))
    x = 560
    d.text((x, 200), "DEVOCIONAL · 21 DIAS", font=f("seguisb.ttf", 25), fill=DOURADO_ESC)
    d.text((x, 245), "21 dias de", font=f("georgiab.ttf", 74), fill=BORDO)
    d.text((x, 325), "recomeço", font=f("georgiab.ttf", 92), fill=BORDO)
    d.text((x, 445), "com a Irmã Lúcia", font=f("georgiai.ttf", 42), fill=TINTA2)
    yy = 545
    for linha in ("Um versículo por dia", "Uma conversa de coração", "Uma oração simples", "Um passo prático",
                  "PDF para ler no celular"):
        d.ellipse((x, yy + 13, x + 12, yy + 25), fill=DOURADO)
        d.text((x + 26, yy), linha, font=f("segoeui.ttf", 31), fill=TINTA)
        yy += 52
    selo_ia(d, 540, 920, 30)
    return pag.convert("RGB")


def pagina(n, zoom=3.0):
    doc = pymupdf.open(PDF)
    pix = doc[n - 1].get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
    return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def com_sombra(fundo, im, xy, raio=0, desvio=(0, 18), blur=24, alpha=80):
    sh = Image.new("RGBA", (im.width + 4 * blur, im.height + 4 * blur), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((2 * blur, 2 * blur, 2 * blur + im.width, 2 * blur + im.height), radius=raio,
                                         fill=(60, 35, 20, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    fundo.alpha_composite(sh, (xy[0] - 2 * blur + desvio[0], xy[1] - 2 * blur + desvio[1]))
    fundo.alpha_composite(im.convert("RGBA"), xy)


def aparelho(ecra, w, h, moldura, raio):
    """Tablet/celular desenhado: moldura escura arredondada com o ecra dentro (o ecra e cortado a medida)."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=raio, fill=(28, 26, 26, 255))
    ew, eh = w - 2 * moldura, h - 2 * moldura
    k = ew / ecra.width  # a pagina cabe na largura do ecra (nada cortado dos lados); o que sobra em baixo fica creme
    e = ecra.resize((ew, round(ecra.height * k)), Image.LANCZOS)
    fundo = Image.new("RGB", (ew, eh), CREME)
    fundo.paste(e.crop((0, 0, ew, min(eh, e.height))), (0, 0))
    e = fundo
    m = Image.new("L", (ew, eh), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, ew - 1, eh - 1), radius=max(6, raio - moldura), fill=255)
    im.paste(e, (moldura, moldura), m)
    return im


def legenda_topo(d, W, y, linhas, px=44):
    for ln in linhas:
        centro(d, W / 2, y, ln, f("georgiai.ttf", px), BORDO)
        y += round(px * 1.3)


def mockup1(capa_img):
    W = 1200
    pag = degrade(W, W, (246, 238, 227), (235, 217, 194)).convert("RGBA")
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, ["Leia no celular, no tablet ou imprima"])
    tablet = aparelho(capa_img, 620, 860, 26, 46)
    com_sombra(pag, tablet, (120, 210), raio=46)
    cel = aparelho(pagina(4), 330, 660, 16, 44)
    com_sombra(pag, cel, (730, 430), raio=44)
    return pag.convert("RGB")


def mockup2():
    W = 1200
    pag = degrade(W, W, (246, 238, 227), (235, 217, 194)).convert("RGBA")
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, ["Um pouco por dia: versículo, conversa,", "oração e um passo prático"])
    esq, dir_ = pagina(3), pagina(4)
    pw = 520
    ph = round(esq.height * pw / esq.width)
    livro = Image.new("RGBA", (2 * pw, ph), (0, 0, 0, 0))
    livro.paste(esq.resize((pw, ph), Image.LANCZOS), (0, 0))
    livro.paste(dir_.resize((pw, ph), Image.LANCZOS), (pw, 0))
    dob = Image.new("RGBA", (80, ph), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dob)
    for i in range(80):
        a = round(70 * (1 - abs(i - 40) / 40) ** 2)
        dd.line([(i, 0), (i, ph)], fill=(70, 45, 30, a))
    livro.alpha_composite(dob, (pw - 40, 0))
    com_sombra(pag, livro, ((W - 2 * pw) // 2, 245), raio=4)
    return pag.convert("RGB")


def mockup3():
    W = 1200
    pag = degrade(W, W, (246, 238, 227), (235, 217, 194)).convert("RGBA")
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, ["26 páginas para ler devagar"])
    pw = 400
    itens = [(2, -9, 190, "A carta da Lúcia"), (4, 0, 400, "21 dias"), (25, 9, 610, "Marque cada dia")]
    for n, ang, x, rot in itens:
        p = pagina(n)
        ph = round(p.height * pw / p.width)
        p = p.resize((pw, ph), Image.LANCZOS).convert("RGBA")
        sh = Image.new("RGBA", (pw + 80, ph + 80), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rectangle((40, 40, 40 + pw, 40 + ph), fill=(60, 35, 20, 85))
        sh = sh.filter(ImageFilter.GaussianBlur(20)).rotate(ang, expand=True, resample=Image.BICUBIC)
        pr = p.rotate(ang, expand=True, resample=Image.BICUBIC)
        y = 230 + (0 if ang == 0 else 40)
        pag.alpha_composite(sh, (x - 40 + 10, y - 40 + 22))
        pag.alpha_composite(pr, (x, y))
    yy = 1035
    fonte = f("seguisb.ttf", 30)
    for n, ang, x, rot in itens:
        lw = d.textlength(rot, font=fonte)
        cx = x + 200 + (0 if ang == 0 else (-20 if ang < 0 else 20))
        d.rounded_rectangle((cx - lw / 2 - 22, yy, cx + lw / 2 + 22, yy + 54), radius=27, fill=BORDO)
        d.text((cx - lw / 2, yy + 9), rot, font=fonte, fill=BRANCO)
    return pag.convert("RGB")


def pdf_com_capa(capa_img):
    orig = pymupdf.open(PDF)
    novo = pymupdf.open()
    r = orig[0].rect
    p = novo.new_page(width=r.width, height=r.height)
    tmp = os.path.join(AQUI, "_capa-pdf.jpg")
    capa_img.save(tmp, quality=92)
    p.insert_image(r, filename=tmp, keep_proportion=False)
    novo.insert_pdf(orig, from_page=1, to_page=orig.page_count - 1)
    novo.set_metadata({"title": "21 dias de recomeço", "author": "Irmã Lúcia (personagem criada com IA)"})
    dst = os.path.join(AQUI, "devocional-21-dias-de-recomeco-com-capa.pdf")
    novo.save(dst, deflate=True, garbage=3)
    os.remove(tmp)
    return dst, novo.page_count


def main():
    c = capa()
    c.save(os.path.join(AQUI, "capa-1200x1697.png"))
    quadrada().save(os.path.join(AQUI, "capa-quadrada-1080.png"))
    mockup1(c).save(os.path.join(AQUI, "mockup-1-tablet-celular.png"))
    mockup2().save(os.path.join(AQUI, "mockup-2-paginas-abertas.png"))
    mockup3().save(os.path.join(AQUI, "mockup-3-o-que-tem-dentro.png"))
    dst, n = pdf_com_capa(c)
    for nome in sorted(os.listdir(AQUI)):
        if nome.endswith((".png", ".pdf")) and not nome.startswith("_"):
            print(nome, os.path.getsize(os.path.join(AQUI, nome)) // 1024, "KB")
    print("pdf com capa:", n, "paginas")


if __name__ == "__main__":
    main()
