# -*- coding: utf-8 -*-
"""Pecas comuns do material de venda dos cadernos (15/11/2026, ajudante de produtos).
Copia generalizada de gospel/produto/venda/montar_venda.py (o modelo aprovado da Irma Lucia):
capa vertical na proporcao da pagina do PDF, imagem quadrada 1080, 3 mockups, PDF com a capa nova
+ linha do autor (subset_fonts), impressao HTML -> PDF pelo Edge headless e verificacao de paginas cortadas.
Cada produto tem o seu montar_venda.py, que define as cores, os textos e as paginas novas.
Nada aqui fala com a Hotmart nem publica nada."""
import json
import os
import re
import subprocess

import pymupdf
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTES = r"C:\Windows\Fonts"
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
BRANCO = (255, 255, 255)


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def f(nome, px):
    return ImageFont.truetype(os.path.join(FONTES, nome), round(px))


def degrade(w, h, c1, c2):
    im = Image.new("RGB", (w, h), c1)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(c1, c2)))
    return im


def larg(d, txt, fonte, espaco=0):
    if espaco:
        return sum(d.textlength(c, font=fonte) for c in txt) + espaco * (len(txt) - 1)
    return d.textlength(txt, font=fonte)


def cabe(d, txt, nome, px, maxw, espaco=0):
    """Maior fonte <= px em que o texto cabe em maxw."""
    while px > 10 and larg(d, txt, f(nome, px), espaco) > maxw:
        px -= 2
    return f(nome, px)


def centro(d, cx, y, txt, fonte, cor, espaco=0):
    if espaco:
        x = cx - larg(d, txt, fonte, espaco) / 2
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


def fotograma(video, t, dst):
    """Fotograma do video ORIGINAL (sem legendas) no instante t; guardado em dst para se ver qual foi."""
    if not os.path.exists(dst):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{t:.2f}", "-i", video, "-frames:v", "1", dst],
                       check=True)
    return Image.open(dst).convert("RGB")


def recorte(im, x0, y0, w, aspeto):
    """Recorte de largura w a comecar em (x0, y0), com a proporcao pedida (largura/altura)."""
    h = round(w / aspeto)
    x0 = max(0, min(x0, im.width - w))
    y0 = max(0, min(y0, im.height - h))
    return im.crop((x0, y0, x0 + w, y0 + h))


def arco_com_foto(foto, w, h, borda, cor_borda):
    ft = foto.resize((w, h), Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 70, 2))
    caixa = Image.new("RGBA", (w + 2 * borda, h + 2 * borda), (0, 0, 0, 0))
    caixa.paste(Image.new("RGBA", caixa.size, cor_borda + (255,)), (0, 0), mascara_arco(*caixa.size))
    caixa.paste(ft, (borda, borda), mascara_arco(w, h))
    return caixa


def selo_ia(d, cx, y, px, cor_fundo):
    fonte = f("seguisb.ttf", px)
    txt = "Personagem criado com IA"
    lw = d.textlength(txt, font=fonte)
    pad_x, pad_y = round(px * 0.9), round(px * 0.45)
    d.rounded_rectangle((cx - lw / 2 - pad_x, y, cx + lw / 2 + pad_x, y + px + 2 * pad_y + 4), radius=px,
                        fill=cor_fundo)
    d.text((cx - lw / 2, y + pad_y - round(px * 0.08)), txt, font=fonte, fill=BRANCO)
    return y + px + 2 * pad_y + 4


def sombra_arco(pag, arco, x, y, desvio, blur, cor=(60, 40, 30, 90)):
    sh = Image.new("RGBA", (arco.width + 2 * desvio, arco.height + 2 * desvio), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", arco.size, cor), (desvio, desvio + 12), mascara_arco(*arco.size))
    pag.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)), (x - desvio, y - desvio))


def capa(c, foto):
    """Capa vertical 1200 x (proporcao da pagina do PDF)."""
    W, H = 1200, c["capa_h"]
    pag = degrade(W, H, c["fundo"], c["fundo2"]).convert("RGBA")
    d = ImageDraw.Draw(pag)
    cx = W / 2
    centro(d, cx, 78, c["kicker"], cabe(d, c["kicker"], "seguisb.ttf", 30, 1060, 3), c["cor2_txt"], espaco=3)
    y = 128
    for txt, px in c["titulo"]:
        fonte = cabe(d, txt, "georgiab.ttf", px, 1080)
        centro(d, cx, y, txt, fonte, c["cor"])
        y += round(fonte.size * 1.06)
    y += 14
    fs = cabe(d, c["subtitulo"], "georgiai.ttf", 50, 1060)
    centro(d, cx, y, c["subtitulo"], fs, c["tinta2"])
    y += round(fs.size * 1.25) + 30
    aw, ah, b = c["arco"]
    x0, y0, w = c["recorte_capa"]
    arco = arco_com_foto(recorte(foto, x0, y0, w, aw / ah), aw, ah, b, c["cor2"])
    x = round(cx - arco.width / 2)
    sombra_arco(pag, arco, x, y, 40, 22)
    pag.alpha_composite(arco, (x, y))
    yb = y + arco.height + 26
    fl = cabe(d, c["linha_capa"], "segoeui.ttf", 31, 1060)
    centro(d, cx, yb, c["linha_capa"], fl, c["cinza"])
    fim = selo_ia(d, cx, yb + 62, 32, c["cor"])
    assert fim < H - 30, f"capa: o selo sai da pagina ({fim} > {H - 30})"
    return pag.convert("RGB")


def quadrada(c, foto):
    S = 1080
    pag = degrade(S, S, c["fundo"], c["fundo2"]).convert("RGBA")
    d = ImageDraw.Draw(pag)
    aw, ah, b = 430, 640, 6
    x0, y0, w = c["recorte_quadrada"]
    arco = arco_com_foto(recorte(foto, x0, y0, w, aw / ah), aw, ah, b, c["cor2"])
    sombra_arco(pag, arco, 70, 180, 30, 18)
    pag.alpha_composite(arco, (70, 180))
    x, maxw = 560, S - 560 - 36
    d.text((x, 200), c["kicker_q"], font=cabe(d, c["kicker_q"], "seguisb.ttf", 25, maxw), fill=c["cor2_txt"])
    y = 245
    for txt, px in c["titulo_q"]:
        fonte = cabe(d, txt, "georgiab.ttf", px, maxw)
        d.text((x, y), txt, font=fonte, fill=c["cor"])
        y += round(fonte.size * 1.08)
    y += 12
    fs = cabe(d, c["com_q"], "georgiai.ttf", 42, maxw)
    d.text((x, y), c["com_q"], font=fs, fill=c["tinta2"])
    yy = y + 90
    fb = min((cabe(d, ln, "segoeui.ttf", 31, maxw - 26).size for ln in c["itens_q"]))
    for linha in c["itens_q"]:
        d.ellipse((x, yy + 13, x + 12, yy + 25), fill=c["cor2"])
        d.text((x + 26, yy), linha, font=f("segoeui.ttf", fb), fill=c["tinta"])
        yy += 52
    assert yy < 900, f"quadrada: os itens descem demais ({yy})"
    selo_ia(d, 540, 920, 30, c["cor"])
    return pag.convert("RGB")


def pagina(pdf, n, zoom=3.0):
    doc = pymupdf.open(pdf)
    pix = doc[n - 1].get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=False)
    im = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    doc.close()
    return im


def com_sombra(fundo, im, xy, raio=0, desvio=(0, 18), blur=24, alpha=80):
    sh = Image.new("RGBA", (im.width + 4 * blur, im.height + 4 * blur), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((2 * blur, 2 * blur, 2 * blur + im.width, 2 * blur + im.height),
                                         radius=raio, fill=(50, 40, 30, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    fundo.alpha_composite(sh, (xy[0] - 2 * blur + desvio[0], xy[1] - 2 * blur + desvio[1]))
    fundo.alpha_composite(im.convert("RGBA"), xy)


def aparelho(ecra, w, h, moldura, raio, cor_fundo):
    """Tablet/celular desenhado: moldura escura arredondada com a pagina dentro (cabe na largura do ecra)."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=raio, fill=(28, 26, 26, 255))
    ew, eh = w - 2 * moldura, h - 2 * moldura
    k = ew / ecra.width
    e = ecra.resize((ew, round(ecra.height * k)), Image.LANCZOS)
    fundo = Image.new("RGB", (ew, eh), cor_fundo)
    fundo.paste(e.crop((0, 0, ew, min(eh, e.height))), (0, 0))
    m = Image.new("L", (ew, eh), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, ew - 1, eh - 1), radius=max(6, raio - moldura), fill=255)
    im.paste(fundo, (moldura, moldura), m)
    return im


def legenda_topo(d, W, y, linhas, cor, px=44):
    for ln in linhas:
        centro(d, W / 2, y, ln, cabe(d, ln, "georgiai.ttf", px, W - 80), cor)
        y += round(px * 1.3)


def fundo_mockup(c, W=1200):
    return degrade(W, W, c["mock1"], c["mock2"]).convert("RGBA")


def mockup1(c, capa_img, pdf, n_pagina):
    W = 1200
    pag = fundo_mockup(c)
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, c["legenda1"], c["cor"])
    tablet = aparelho(capa_img, 620, 860, 26, 46, c["fundo"])
    com_sombra(pag, tablet, (120, 210), raio=46)
    cel = aparelho(pagina(pdf, n_pagina), 330, 660, 16, 44, c["fundo"])
    com_sombra(pag, cel, (730, 430), raio=44)
    return pag.convert("RGB")


def mockup2(c, pdf, na, nb):
    W = 1200
    pag = fundo_mockup(c)
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, c["legenda2"], c["cor"])
    esq, dir_ = pagina(pdf, na), pagina(pdf, nb)
    pw = 520
    ph = round(esq.height * pw / esq.width)
    livro = Image.new("RGBA", (2 * pw, ph), (0, 0, 0, 0))
    livro.paste(esq.resize((pw, ph), Image.LANCZOS), (0, 0))
    livro.paste(dir_.resize((pw, ph), Image.LANCZOS), (pw, 0))
    dob = Image.new("RGBA", (80, ph), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dob)
    for i in range(80):
        dd.line([(i, 0), (i, ph)], fill=(70, 45, 30, round(70 * (1 - abs(i - 40) / 40) ** 2)))
    livro.alpha_composite(dob, (pw - 40, 0))
    y = 70 + round(44 * 1.3) * len(c["legenda2"]) + 60
    com_sombra(pag, livro, ((W - 2 * pw) // 2, y), raio=4)
    assert y + ph < W - 20, "mockup2: as paginas saem da imagem"
    return pag.convert("RGB")


def mockup3(c, pdf, itens):
    """itens: [(n_pagina, angulo, x, rotulo), ...] - tres paginas em leque com um rotulo por baixo."""
    W = 1200
    pag = fundo_mockup(c)
    d = ImageDraw.Draw(pag)
    legenda_topo(d, W, 70, c["legenda3"], c["cor"])
    pw = 400
    for n, ang, x, _ in itens:
        p = pagina(pdf, n)
        ph = round(p.height * pw / p.width)
        p = p.resize((pw, ph), Image.LANCZOS).convert("RGBA")
        sh = Image.new("RGBA", (pw + 80, ph + 80), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rectangle((40, 40, 40 + pw, 40 + ph), fill=(50, 40, 30, 85))
        sh = sh.filter(ImageFilter.GaussianBlur(20)).rotate(ang, expand=True, resample=Image.BICUBIC)
        pr = p.rotate(ang, expand=True, resample=Image.BICUBIC)
        y = 230 + (0 if ang == 0 else 40)
        pag.alpha_composite(sh, (x - 40 + 10, y - 40 + 22))
        pag.alpha_composite(pr, (x, y))
    # rotulos: mesma letra nos tres; os de fora afastam-se e a letra desce ate haver folga entre eles (juiz 15/11:
    # "Entradas e saidas" encostava em "Contas fixas")
    yy = 1035
    centros = [x + 200 + (0 if ang == 0 else (-20 if ang < 0 else 20)) for _, ang, x, _ in itens]
    centros[0] -= 30
    centros[-1] += 30
    px = 30
    while True:
        fonte = f("seguisb.ttf", px)
        caixas = [(cx - d.textlength(rot, font=fonte) / 2 - 22, cx + d.textlength(rot, font=fonte) / 2 + 22)
                  for cx, (_, _, _, rot) in zip(centros, itens)]
        folga = min(b[0] - a[1] for a, b in zip(caixas, caixas[1:]))
        if (folga >= 18 and caixas[0][0] >= 20 and caixas[-1][1] <= W - 20) or px <= 20:
            break
        px -= 1
    assert folga >= 18, f"mockup3: rotulos encostados (folga {folga:.0f}px)"
    for (x0, x1), cx, (_, _, _, rot) in zip(caixas, centros, itens):
        d.rounded_rectangle((x0, yy, x1, yy + 54), radius=27, fill=c["cor"])
        d.text((cx - d.textlength(rot, font=fonte) / 2, yy + 27 - px * 0.62), rot, font=fonte, fill=BRANCO)
    return pag.convert("RGB")


# ---------------------------------------------------------------- PDF

def imprimir(html, pdf, perfil):
    """HTML -> PDF pelo Edge headless (como o _trabalho/build_pdf.py), num perfil a parte para nao tocar no Edge do PC."""
    if os.path.exists(pdf):
        os.remove(pdf)
    url = "file:///" + os.path.abspath(html).replace("\\", "/")
    r = subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", "--no-first-run",
                        "--disable-extensions", f"--user-data-dir={perfil}", f"--print-to-pdf={os.path.abspath(pdf)}",
                        url], capture_output=True, text=True, timeout=240)
    if not os.path.exists(pdf):
        raise SystemExit(f"ERRO: PDF nao criado ({r.returncode}) {r.stderr[-400:]}")
    return pdf


def paginas_cortadas(html, perfil):
    """Abre uma copia do HTML no Edge com um script no fim que mede cada .page (scrollHeight - clientHeight).
    Devolve {'total': n, 'cortadas': [[pagina, px], ...]}. Lista vazia = nada cortado."""
    s = open(html, encoding="utf-8").read()
    js = ("<script>(function(){var ps=[].slice.call(document.querySelectorAll('.page'));"
          "var r=ps.map(function(p,i){var lim=p.getBoundingClientRect().bottom;var maior=0;"
          "[].slice.call(p.querySelectorAll('*')).forEach(function(e){var b=e.getBoundingClientRect();"
          "var dentro=e.parentElement&&e.parentElement.closest('.linhas');"
          "if(b.height>0&&b.bottom>maior&&!e.closest('.rodape')&&!dentro)maior=b.bottom;});"
          "return [i+1,p.scrollHeight-p.clientHeight,Math.round(maior-lim)];})"
          ".filter(function(x){return x[1]>1||x[2]>1;});"
          "var pre=document.createElement('pre');pre.id='verifica';pre.textContent=JSON.stringify({total:ps.length,cortadas:r});"
          "document.body.appendChild(pre);})();</script>")
    tmp = html[:-5] + "-verifica.html"
    open(tmp, "w", encoding="utf-8").write(s.replace("</body>", js + "</body>"))
    url = "file:///" + os.path.abspath(tmp).replace("\\", "/")
    r = subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--no-first-run", "--disable-extensions",
                        f"--user-data-dir={perfil}", "--dump-dom", url], capture_output=True, text=True,
                       encoding="utf-8", timeout=240)
    os.remove(tmp)
    m = re.search(r'<pre id="verifica">(.*?)</pre>', r.stdout, re.S)
    if not m:
        raise SystemExit("ERRO: a verificacao de paginas cortadas nao devolveu resultado")
    return json.loads(m.group(1))


def inserir_antes_da_ultima(html_txt, novas, css_extra):
    """Mete as secoes novas antes da ultima pagina (a do 'Ate breve') e o CSS novo no fim do <style>."""
    i = html_txt.rfind('<section class="page')
    assert i > 0 and "Até breve" in html_txt[i:], "nao encontrei a ultima pagina (Ate breve)"
    html_txt = html_txt[:i] + novas + html_txt[i:]
    return html_txt.replace("</style>", css_extra + "\n</style>", 1)


def area_livre(pag, rect):
    """True se o retangulo nao toca em texto nem em desenho da pagina."""
    for b in pag.get_text("blocks"):
        if pymupdf.Rect(b[:4]).intersects(rect):
            return False
    for dr in pag.get_drawings():
        r = dr["rect"]
        if r.intersects(rect) and not (r.width > pag.rect.width * 0.9 and r.height > pag.rect.height * 0.9):
            return False
    return True


def parenteses_certos(doc, pag):
    """A Segoe UI liga o glifo do parentese tambem a U+FD3E/U+FD3F, e o mapa de texto do PDF ficava com esses
    (ao copiar ou ler o texto saia '﴾personagem criada com IA﴿'). Volta a pôr '(' e ')' no mapa da letra do autor."""
    import re
    for fx in pag.get_fonts():
        if fx[4] != "segoeui":
            continue
        k = doc.xref_get_key(fx[0], "ToUnicode")
        if k[0] != "xref":
            continue
        tu = int(k[1].split()[0])
        s = doc.xref_stream(tu)
        s = re.sub(rb"<fd3e>", b"<0028>", s, flags=re.I)
        s = re.sub(rb"<fd3f>", b"<0029>", s, flags=re.I)
        doc.update_stream(tu, s)


def pdf_final(pdf_base, capa_img, dst, titulo, autor, linha_autor, pag_autor, cor_txt, tmpdir):
    """PDF a vender: capa nova (imagem) no lugar da capa so de texto + linha do autor na pagina pag_autor
    (1 = primeira), no espaco livre por cima da linha final da IA. Devolve (paginas, retangulo usado)."""
    orig = pymupdf.open(pdf_base)
    novo = pymupdf.open()
    r = orig[0].rect
    p = novo.new_page(width=r.width, height=r.height)
    tmp = os.path.join(tmpdir, "_capa-pdf.jpg")
    capa_img.save(tmp, quality=92)
    p.insert_image(r, filename=tmp, keep_proportion=False)
    novo.insert_pdf(orig, from_page=1, to_page=orig.page_count - 1)
    orig.close()
    ult = novo[pag_autor - 1]
    # a linha final da IA ("... criada com inteligencia artificial. Material de uso pessoal.") marca o fundo do texto
    ia = [b for b in ult.get_text("blocks") if "inteligência artificial" in b[4]]
    assert ia, "nao encontrei a linha da IA na pagina do autor"
    topo_ia = min(b[1] for b in ia)
    rect = pymupdf.Rect(40, topo_ia - 14 - 26, r.width - 40, topo_ia - 14)
    assert area_livre(ult, rect), f"a linha do autor ia ficar por cima de texto ou desenho: {rect}"
    sobra = ult.insert_textbox(rect, linha_autor, fontsize=8.5, fontname="segoeui",
                               fontfile=os.path.join(FONTES, "segoeui.ttf"), color=tuple(v / 255 for v in cor_txt),
                               align=1)
    assert sobra >= 0, "a linha do autor nao coube na caixa"
    novo.set_metadata({"title": titulo, "author": autor, "creator": "Edições Bora", "producer": "Edições Bora"})
    novo.subset_fonts()  # a letra do autor entra so com os caracteres usados
    parenteses_certos(novo, novo[pag_autor - 1])
    novo.save(dst, deflate=True, garbage=3)
    n = novo.page_count
    novo.close()
    os.remove(tmp)
    # prova: le o texto de volta
    chk = pymupdf.open(dst)
    txt = chk[pag_autor - 1].get_text()
    for ln in linha_autor.split("\n"):
        assert ln in txt, f"linha do autor nao lida de volta: {ln!r}"
    chk.close()
    return n, rect


def folha(imgs, dst, alt=520, cols=4, legenda=None):
    """Folha de revisao reduzida (para o juiz ver tudo de uma vez)."""
    ims = []
    for im in imgs:
        im = im if isinstance(im, Image.Image) else Image.open(im).convert("RGB")
        k = alt / im.height
        ims.append(im.resize((round(im.width * k), alt), Image.LANCZOS))
    linhas = [ims[i:i + cols] for i in range(0, len(ims), cols)]
    W = max(sum(i.width for i in ln) + 12 * (len(ln) + 1) for ln in linhas)
    topo = 40 if legenda else 0
    out = Image.new("RGB", (W, topo + len(linhas) * (alt + 12) + 12), (110, 110, 110))
    if legenda:
        ImageDraw.Draw(out).text((12, 8), legenda, font=f("segoeuib.ttf", 22), fill=(255, 255, 255))
    y = topo + 12
    for ln in linhas:
        x = 12
        for im in ln:
            out.paste(im, (x, y))
            x += im.width + 12
        y += alt + 12
    out.save(dst, quality=85)
    return dst
