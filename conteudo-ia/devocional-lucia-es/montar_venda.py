# -*- coding: utf-8 -*-
"""Material de venda do devocional em ESPANHOL "21 días para volver a empezar" (Hermana Lucía), 15/11/2026.
Ordem do Danilo das 16:57 e precos autorizados as 16:59, passada pela Claude.ai as 17:00 (e2e_log 9374):
7,90 EUR para Espanha e America Latina (o espanhol e so para a Hotmart). Titulo e capa adaptados a lingua por ordem da Claude.ai das 17:05.

Copia do montar_venda.py portugues (gospel/produto/venda) com a MESMA cara: bordo #7A2E3A, dourado #C9A46A,
Georgia + Segoe UI, fotograma de 11 s do video aprovado lucia-r001 (o _lucia-r001-11s.png ja tirado na pasta venda
portuguesa). So mudam os textos (dicionario T) e, como o espanhol e mais comprido, cada titulo encolhe sozinho se nao
couber na largura (na imagem quadrada o titulo vai em 3 linhas).

Faz, nesta pasta:
  capa-1200x1697.png            capa vertical (proporcao A5), com a cara da Lucia e o selo "Personaje creado con IA"
  capa-quadrada-1080.png        imagem quadrada do produto (Hotmart)
  mockup-1-tablet-celular.png   capa no tablet + dia 1 no telefone
  mockup-2-paginas-abertas.png  "Cómo usarlo" + "Día 1" lado a lado
  mockup-3-o-que-tem-dentro.png carta da Lucia, dia 1 e a pagina de marcar os dias, em leque
  21-dias-para-volver-a-empezar-con-portada.pdf   HOTMART: o PDF espanhol com esta capa no lugar da capa so de
                                                texto + "Autora: Hermana Lucía (personaje creado con IA) –
                                                Edições Bora / © 2026 Bora"
Uso: python montar_venda.py
"""
import os
import subprocess

import pymupdf
from PIL import Image, ImageDraw, ImageFilter, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
PRODUTO = os.path.dirname(AQUI)
PDF = os.path.join(PRODUTO, "21-dias-para-volver-a-empezar.pdf")
FOTO_PT = r"C:\BoraLocal\ConteudoIA\gospel\produto\venda\_lucia-r001-11s.png"  # o mesmo fotograma da versao PT
VIDEO = r"C:\BoraLocal\ConteudoIA\videos\lucia\lucia-r001.mp4"  # video aprovado; fotograma aos 11 s
FONTES = r"C:\Windows\Fonts"

T = dict(
    kicker="DEVOCIONAL  ·  21 DÍAS",
    titulo=[("21 días para", 116), ("volver a empezar", 150)],
    sub="un devocional con la Hermana Lucía",
    linha="versículo  ·  conversación  ·  oración  ·  paso práctico",
    selo="Personaje creado con IA",
    q_kicker="DEVOCIONAL · 21 DÍAS",
    q_titulo=[("21 días para", 74), ("volver a", 92), ("empezar", 92)],
    q_sub="con la Hermana Lucía",
    q_itens=("Un versículo al día", "Una conversación de corazón", "Una oración sencilla", "Un paso práctico",
             "PDF para leer en el teléfono"),
    m1=["Léelo en el teléfono o en la tableta, o imprímelo"],
    m2=["Un poco cada día: versículo, conversación,", "oración y un paso práctico"],
    m3=["26 páginas para leer con calma"],
    m3_tags=("Carta de Lucía", "21 días", "Marca cada día"),
    meta_titulo="21 días para volver a empezar",
    pdfs=[  # (ficheiro, linha do autor na ultima pagina, autor nos metadados, palavras proibidas no PDF)
        ("21-dias-para-volver-a-empezar-con-portada.pdf",  # Hotmart (o espanhol e so para a Hotmart)
         "Autora: Hermana Lucía (personaje creado con IA) – Edições Bora\n© 2026 Bora",
         "Hermana Lucía (personaje creado con IA) – Edições Bora",
         ("Danilo", "Fulfaro", "Unipessoal")),
    ],
)

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


def caber(d, txt, nome, px, larg_max):
    """Fonte do tamanho pedido ou mais pequena, ate o texto caber em larg_max px."""
    while px > 20 and d.textlength(txt, font=f(nome, px)) > larg_max:
        px -= 2
    return f(nome, px), px


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
    if os.path.exists(FOTO_PT):
        return Image.open(FOTO_PT).convert("RGB")
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
    txt = T["selo"]
    lw = d.textlength(txt, font=fonte)
    pad_x, pad_y = round(px * 0.9), round(px * 0.45)
    d.rounded_rectangle((cx - lw / 2 - pad_x, y, cx + lw / 2 + pad_x, y + px + 2 * pad_y + 4), radius=px, fill=BORDO)
    d.text((cx - lw / 2, y + pad_y - round(px * 0.08)), txt, font=fonte, fill=BRANCO)


def capa(W=1200, H=1697):
    pag = degrade(W, H, CREME, CREME2).convert("RGBA")
    d = ImageDraw.Draw(pag)
    cx = W / 2
    centro(d, cx, 78, T["kicker"], f("seguisb.ttf", 30), DOURADO_ESC, espaco=3)
    for (txt, px), y in zip(T["titulo"], (128, 250)):  # as mesmas alturas da capa portuguesa
        fonte, px2 = caber(d, txt, "georgiab.ttf", px, W - 120)
        centro(d, cx, y + (px - px2) * 0.6, txt, fonte, BORDO)
    fonte, _ = caber(d, T["sub"], "georgiai.ttf", 50, W - 120)
    centro(d, cx, 432, T["sub"], fonte, TINTA2)
    aw, ah, b = 860, 940, 7
    arco = arco_com_foto(recorte(foto_lucia(), aw / ah, 110), aw, ah, b)
    sombra = Image.new("RGBA", (arco.width + 80, arco.height + 80), (0, 0, 0, 0))
    sombra.paste(Image.new("RGBA", arco.size, (90, 50, 30, 90)), (40, 52), mascara_arco(*arco.size))
    sombra = sombra.filter(ImageFilter.GaussianBlur(22))
    x, y = round(cx - arco.width / 2), 530
    pag.alpha_composite(sombra, (x - 40, y - 40))
    pag.alpha_composite(arco, (x, y))
    yb = y + arco.height + 26
    fonte, _ = caber(d, T["linha"], "segoeui.ttf", 31, W - 120)
    centro(d, cx, yb, T["linha"], fonte, CINZA)
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
    x, larg = 560, S - 560 - 36
    d.text((x, 200), T["q_kicker"], font=caber(d, T["q_kicker"], "seguisb.ttf", 25, larg)[0], fill=DOURADO_ESC)
    y = 245  # as linhas do titulo descem como na portuguesa (245, 325); o resto vem logo a seguir
    for i, (txt, px) in enumerate(T["q_titulo"]):
        fonte, px2 = caber(d, txt, "georgiab.ttf", px, larg)
        d.text((x, y + (px - px2) * 0.6), txt, font=fonte, fill=BORDO)
        ultimo = px
        if i < len(T["q_titulo"]) - 1:
            y += round(px * 1.08)
    y += round(ultimo * 1.3)
    d.text((x, y), T["q_sub"], font=caber(d, T["q_sub"], "georgiai.ttf", 42, larg)[0], fill=TINTA2)
    yy = y + 100
    for linha in T["q_itens"]:
        d.ellipse((x, yy + 13, x + 12, yy + 25), fill=DOURADO)
        d.text((x + 26, yy), linha, font=caber(d, linha, "segoeui.ttf", 31, larg - 26)[0], fill=TINTA)
        yy += 52
    if yy > 915:
        print("AVISO: a lista da imagem quadrada chega a", yy, "px e encosta no selo (920)")
    selo_ia(d, 540, 920, 30)
    return pag.convert("RGB")


_DOC = {}


def pagina(n, zoom=3.0):
    if "d" not in _DOC:
        _DOC["d"] = pymupdf.open(PDF)
    pix = _DOC["d"][n - 1].get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
    return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)


def com_sombra(fundo, im, xy, raio=0, desvio=(0, 18), blur=24, alpha=80):
    sh = Image.new("RGBA", (im.width + 4 * blur, im.height + 4 * blur), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((2 * blur, 2 * blur, 2 * blur + im.width, 2 * blur + im.height), radius=raio,
                                         fill=(60, 35, 20, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    fundo.alpha_composite(sh, (xy[0] - 2 * blur + desvio[0], xy[1] - 2 * blur + desvio[1]))
    fundo.alpha_composite(im.convert("RGBA"), xy)


def aparelho(ecra, w, h, moldura, raio):
    """Tablet/telefone desenhado: moldura escura arredondada com o ecra dentro (o ecra e cortado a medida)."""
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
        centro(d, W / 2, y, ln, caber(d, ln, "georgiai.ttf", px, W - 80)[0], BORDO)
        y += round(px * 1.3)


def mockup1(capa_img):
    W = 1200
    pag = degrade(W, W, (246, 238, 227), (235, 217, 194)).convert("RGBA")
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, T["m1"])
    tablet = aparelho(capa_img, 620, 860, 26, 46)
    com_sombra(pag, tablet, (120, 210), raio=46)
    cel = aparelho(pagina(4), 330, 660, 16, 44)
    com_sombra(pag, cel, (730, 430), raio=44)
    return pag.convert("RGB")


def mockup2():
    W = 1200
    pag = degrade(W, W, (246, 238, 227), (235, 217, 194)).convert("RGBA")
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, T["m2"])
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
    legenda_topo(d, W, 70, T["m3"])
    pw = 400
    itens = [(2, -9, 190), (4, 0, 400), (25, 9, 610)]
    for n, ang, x in itens:
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
    caixas = []
    for (n, ang, x), rot in zip(itens, T["m3_tags"]):
        lw = d.textlength(rot, font=fonte)
        cx = x + 200 + (0 if ang == 0 else (-20 if ang < 0 else 20))
        caixas.append((cx - lw / 2 - 22, cx + lw / 2 + 22))
        d.rounded_rectangle((cx - lw / 2 - 22, yy, cx + lw / 2 + 22, yy + 54), radius=27, fill=BORDO)
        d.text((cx - lw / 2, yy + 9), rot, font=fonte, fill=BRANCO)
    folgas = [round(caixas[i + 1][0] - caixas[i][1]) for i in range(len(caixas) - 1)]
    print("mockup 3: folga entre etiquetas (px):", folgas, "(negativo = sobrepostas)")
    return pag.convert("RGB")


def pdf_com_capa(capa_img, nome, autor, meta_autor, proibidas):
    orig = pymupdf.open(PDF)
    novo = pymupdf.open()
    r = orig[0].rect
    p = novo.new_page(width=r.width, height=r.height)
    tmp = os.path.join(AQUI, "_capa-pdf.jpg")
    capa_img.save(tmp, quality=92)
    p.insert_image(r, filename=tmp, keep_proportion=False)
    novo.insert_pdf(orig, from_page=1, to_page=orig.page_count - 1)
    # autor na ultima pagina (a Hotmart pede o nome do autor numa pagina), sem o nome do Danilo nem da empresa
    ult = novo[novo.page_count - 1]
    caixa = pymupdf.Rect(40, 490, r.width - 40, 528)
    ocupado = [round(b[3]) for b in ult.get_text("blocks") if b[1] < caixa.y1 and b[3] > caixa.y0]
    sobra = ult.insert_textbox(caixa, autor, fontsize=8.5, fontname="segoeui",
                               fontfile=os.path.join(FONTES, "segoeui.ttf"),
                               color=tuple(c / 255 for c in CINZA), align=1)
    print(nome, "| linha do autor: sobra", round(sobra, 1), "pt (negativo = nao coube) | texto da pagina na mesma faixa:",
          ocupado or "nenhum")
    novo.set_metadata({"title": T["meta_titulo"], "author": meta_autor})
    dst = os.path.join(AQUI, nome)
    novo.subset_fonts()  # a letra do autor entra so com os caracteres usados (sem isto o PDF dobra de tamanho)
    novo.save(dst, deflate=True, garbage=3)
    os.remove(tmp)
    # prova: le o PDF gravado e procura as palavras proibidas no texto e nos metadados
    lido = pymupdf.open(dst)
    tudo = " ".join(pg.get_text() for pg in lido) + " " + " ".join(str(v) for v in lido.metadata.values())
    # o Segoe UI recortado devolve ( ) - como ﴾ ﴿ ‐ ao extrair o texto (tambem no PDF portugues);
    # a vista sao parenteses e hifen normais
    ultima = lido[-1].get_text().replace("﴾", "(").replace("﴿", ")").replace("‐", "-")
    print(nome, "| paginas:", lido.page_count, "| autor lido na ultima pagina:",
          " / ".join(x for x in autor.split("\n") if x in ultima) or "NAO ENCONTRADO",
          "| palavras proibidas encontradas:", [w for w in proibidas if w.lower() in tudo.lower()] or "nenhuma")
    return dst, lido.page_count


def main():
    c = capa()
    c.save(os.path.join(AQUI, "capa-1200x1697.png"))
    quadrada().save(os.path.join(AQUI, "capa-quadrada-1080.png"))
    mockup1(c).save(os.path.join(AQUI, "mockup-1-tablet-celular.png"))
    mockup2().save(os.path.join(AQUI, "mockup-2-paginas-abertas.png"))
    mockup3().save(os.path.join(AQUI, "mockup-3-o-que-tem-dentro.png"))
    for nome, autor, meta_autor, proibidas in T["pdfs"]:
        pdf_com_capa(c, nome, autor, meta_autor, proibidas)
    for nome in sorted(os.listdir(AQUI)):
        if nome.endswith((".png", ".pdf")) and not nome.startswith("_"):
            print(nome, os.path.getsize(os.path.join(AQUI, nome)) // 1024, "KB")


if __name__ == "__main__":
    main()
