"""Peça "A GUARDA TODA NUMA APP" (11/11/2026): carrossel de 8 cartões 1080x1080 + mosaico 1080x1350 e 1080x1920.
Mesma família do amigo-a1-feed (fundo escuro de cinema, Impact branco/amarelo, faixa de pincel, logo Bora real).
Cenas de cinema: ChatGPT (limpeza, estafeta de mota, saco de compras) + as já aprovadas a 11/11 (Sé, roupeiro).
Comida: SÓ fotos reais do catálogo (Fuku T22/T20/T33, Boom Clássico, Pôr do Sol pizza e kebab), sem nomes nem logos.
python montar_tudo.py  -> saida/tudo-*.jpg"""
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

AQUI = os.path.dirname(os.path.abspath(__file__))
ANTES = os.path.join(AQUI, "..", "propaganda-casa-amigo-2026-11-11")
sys.path.insert(0, ANTES)
from montar import fonte, logo, cobrir  # noqa: E402
from montar_amigo import (impact, pincel, texto_sombra, fila_icones, faixa_baixo, italico,  # noqa: E402
                          AMARELO, LARANJA, VERDE, BRANCO, TINTA, ESCURO)

IA = os.path.join(AQUI, "ia")
FOTOS = os.path.join(AQUI, "fotos")
SAIDA = os.path.join(AQUI, "saida")
os.makedirs(SAIDA, exist_ok=True)
SE = os.path.join(ANTES, "ia", "amigo_a1_v1.jpg")
ROUPEIRO = os.path.join(ANTES, "ia", "c1_roupeiro_v2.jpg")
W = 1080


# ---------------------------------------------------------------- bases
def abrir(p):
    return Image.open(p).convert("RGB")


def fundo_se(w, h, desfoque=10, brilho=0.75):
    """Sé da Guarda à noite (só a parte de cima da cena aprovada, sem o telemóvel), desfocada."""
    se = abrir(SE).crop((0, 300, 1536, 1300))
    im = cobrir(se, w, h, fy=0.6)
    im = im.filter(ImageFilter.GaussianBlur(desfoque))
    return ImageEnhance.Brightness(im).enhance(brilho)


def escurecer(im, topo_ate, topo_a, fundo_de, fundo_a, cor=ESCURO):
    w, h = im.size
    m = Image.new("L", (1, h)); px = m.load()
    for y in range(h):
        a = 0
        if y < topo_ate:
            a = int(255 * topo_a * (1 - y / topo_ate) ** 0.8)
        if y > fundo_de:
            a = max(a, int(255 * fundo_a * min(1, (y - fundo_de) / max(1, h - fundo_de)) ** 0.9))
        px[0, y] = a
    return Image.composite(Image.new("RGB", (w, h), cor), im, m.resize((w, h)))


def arredondar(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=r, fill=255)
    out = im.convert("RGBA"); out.putalpha(m)
    return out


def com_sombra(tela, peca, x, y, raio=18, desloc=14, forca=0.7):
    a = peca.split()[3].point(lambda v: int(v * forca))
    s = Image.new("RGBA", (peca.width + 80, peca.height + 80), (0, 0, 0, 0))
    preto = Image.new("RGBA", peca.size, (0, 0, 0, 255)); preto.putalpha(a)
    s.paste(preto, (40, 40 + desloc), preto)
    s = s.filter(ImageFilter.GaussianBlur(raio))
    tela.alpha_composite(s, (x - 40, y - 40))
    tela.alpha_composite(peca, (x, y))


def brilho_quente(tela, cx, cy, r, cor=(255, 170, 60), forca=120):
    m = Image.new("L", tela.size, 0)
    ImageDraw.Draw(m).ellipse([cx - r, cy - r, cx + r, cy + r], fill=forca)
    m = m.filter(ImageFilter.GaussianBlur(r * 0.45))
    camada = Image.new("RGBA", tela.size, cor + (0,)); camada.putalpha(m)
    tela.alpha_composite(camada)


def titulo_ajustado(d, linhas, y, max_w=960, tam=112, entre=1.0, s=5):
    """linhas = [(texto, cor)]; encolhe a letra até caber em max_w. Devolve o y final."""
    t = tam
    while t > 40 and max(d.textlength(tx, font=impact(t)) for tx, _ in linhas) > max_w:
        t -= 2
    f = impact(t)
    for tx, cor in linhas:
        texto_espacado(d, W / 2, y, tx, f, cor, s, centro=True)
        y += int(t * entre)
    return y


def texto_espacado(d, x, y, tx, f, cor, s=5, centro=False):
    """Escreve o texto; se acabar em '?', dá 9 px de folga antes do '?' (a Impact encosta-o à letra)."""
    if not tx.endswith("?"):
        texto_sombra(d, (x, y), tx, f, cor, anchor="ma" if centro else "la", s=s)
        return
    corpo = tx[:-1]; wc = d.textlength(corpo, font=f); wq = d.textlength("?", font=f); gap = 4
    x0 = x - (wc + gap + wq) / 2 if centro else x
    texto_sombra(d, (x0, y), corpo, f, cor, anchor="la", s=s)
    texto_sombra(d, (x0 + wc + gap, y), "?", f, cor, anchor="la", s=s)


def seta(d, x, y, tam, cor):
    """Seta → desenhada (a Impact não tem a seta)."""
    h = tam
    d.rectangle([x, y + h * 0.40, x + h * 0.75, y + h * 0.60], fill=cor)
    d.polygon([(x + h * 0.62, y + h * 0.18), (x + h * 1.05, y + h * 0.50), (x + h * 0.62, y + h * 0.82)], fill=cor)


def cabecalho(im, n, y=34):
    d = ImageDraw.Draw(im)
    f = fonte("ExtraBold", 28); t = "A GUARDA TODA NUMA APP"; w = d.textlength(t, font=f)
    d.rounded_rectangle([44, y, 44 + w + 40, y + 50], radius=25, fill=LARANJA)
    d.text((44 + 20 + w / 2, y + 25), t, font=f, fill=BRANCO, anchor="mm")
    if n:
        fn = fonte("ExtraBold", 28); tn = f"{n}/8"; wn = d.textlength(tn, font=fn)
        d.rounded_rectangle([W - 44 - wn - 36, y, W - 44, y + 50], radius=25, fill=(0, 0, 0, 150), outline=BRANCO, width=2)
        d.text((W - 44 - 18 - wn / 2, y + 25), tn, font=fn, fill=BRANCO, anchor="mm")


def barra_baixo(im, y=930, h=118, texto="PEDE NA APP BORA", desliza=True):
    d = ImageDraw.Draw(im)
    x0, x1 = 44, W - 44
    d.rounded_rectangle([x0, y, x1, y + h], radius=24, fill=(12, 12, 14, 235), outline=AMARELO, width=4)
    cw = 250
    d.rounded_rectangle([x0 + 16, y + 12, x0 + 16 + cw, y + h - 12], radius=14, fill=BRANCO)
    lg = logo(min(int(cw * 0.92 * 580 / 1260), h - 30))
    im.paste(lg, (x0 + 16 + (cw - lg.width) // 2, y + (h - lg.height) // 2))
    resto0 = x0 + 16 + cw
    if desliza:
        f = impact(46)
        cx = resto0 + 200
        italico(im, texto, 46, cx, y + 26)
        fD = fonte("ExtraBold", 30); tD = "Desliza"; wD = d.textlength(tD, font=fD)
        xd = x1 - 40 - wD - 52
        d.text((xd, y + h / 2), tD, font=fD, fill=AMARELO, anchor="lm")
        seta(d, xd + wD + 10, y + h / 2 - 22, 44, AMARELO)
    else:
        cx = (resto0 + x1) // 2
        italico(im, texto, 50, cx, y + 26)


# ---------------------------------------------------------------- cenas
def imprimir_logo(im, x0, y0, lw, ang=0):
    """Marca Bora IMPRESSA no kraft como serigrafia plana a 2 cores (verde e laranja do logo real, sem volume
    nem brilho): só a palavra BORA do logótipo real, tinta multiplicada pela luz e textura do papel."""
    import numpy as np
    lg = Image.open(os.path.join(ANTES, "bora_logo.png")).convert("RGB").crop((60, 110, 1320, 690))
    a = np.asarray(lg).astype(int)
    # só a palavra (a mascote 3D fica de fora): colunas a partir do fim da mascote
    lum = a.mean(axis=2)
    col_tinta = (lum < 225).sum(axis=0)
    xs = np.nonzero(col_tinta > 3)[0]
    # o maior intervalo vazio separa a mascote da palavra
    gaps = np.diff(xs); i = int(np.argmax(gaps)); x_pal = xs[i + 1] - 6
    lg = lg.crop((x_pal, 0, lg.width, lg.height))
    a = np.asarray(lg).astype(int)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = a.mean(axis=2)
    tinta = lum < 215
    laranja = tinta & (r > g + 40)
    ys, xs2 = np.nonzero(tinta)
    lg_box = (xs2.min(), ys.min(), xs2.max() + 1, ys.max() + 1)
    cor = np.zeros(a.shape, dtype=np.uint8)
    cor[...] = (24, 96, 52)                     # verde de serigrafia
    cor[laranja] = (190, 62, 8)                 # laranja-telha de serigrafia: contrasta com o kraft
    alfa = (tinta * 235).astype(np.uint8)
    pinta = Image.fromarray(cor).crop(lg_box); m = Image.fromarray(alfa).crop(lg_box)
    h = int(lw * pinta.height / pinta.width)
    pinta = pinta.resize((lw, h), Image.LANCZOS); m = m.resize((lw, h), Image.LANCZOS)
    if ang:
        pinta = pinta.rotate(ang, resample=Image.BICUBIC, expand=True); m = m.rotate(ang, resample=Image.BICUBIC, expand=True)
    papel = im.crop((x0, y0, x0 + pinta.width, y0 + pinta.height))
    # tinta * luz do papel (as dobras e a sombra passam por cima da tinta)
    luz = np.asarray(papel.convert("L")).astype(float)
    luz = luz / max(1.0, np.percentile(luz, 90))
    p = np.asarray(pinta).astype(float) * np.clip(luz, 0.35, 1.08)[..., None]
    pinta = Image.fromarray(np.clip(p, 0, 255).astype(np.uint8))
    # a fibra do kraft aparece através da tinta (tinta não cobre a 100 %)
    grao = papel.convert("L").filter(ImageFilter.FIND_EDGES).point(lambda v: 255 - min(255, v * 3))
    from PIL import ImageChops
    m = ImageChops.multiply(m, grao.point(lambda v: 150 + int(v * 105 / 255)))
    im.paste(pinta, (x0, y0), m)
    return im


def colocar(img, dy=0):
    """Cena a cobrir o cartão, deslocada dy px (positivo = para baixo); a faixa que fica vazia
    é preenchida com a borda da própria cena, desfocada e escura."""
    base = cobrir(img, W, W)
    if not dy:
        return base
    out = Image.new("RGB", (W, W), ESCURO)
    out.paste(base, (0, dy))
    if dy > 0:
        tira = base.crop((0, 0, W, 40)).resize((W, dy)).filter(ImageFilter.GaussianBlur(18))
        out.paste(ImageEnhance.Brightness(tira).enhance(0.6), (0, 0))
    else:
        tira = base.crop((0, W - 40, W, W)).resize((W, -dy)).filter(ImageFilter.GaussianBlur(18))
        out.paste(ImageEnhance.Brightness(tira).enhance(0.5), (0, W + dy))
    return out


def cena_saco():
    """Saco de papel kraft da cena do ChatGPT com o logo Bora impresso na frente lisa."""
    im = abrir(os.path.join(IA, "bora-tudo-saco-v1.png"))
    return imprimir_logo(im, 440, 770, 400)


def cena_estafeta():
    """Estafeta à porta: o saco kraft dele leva a marca Bora impressa."""
    im = abrir(os.path.join(IA, "bora-tudo-estafeta-v1.png"))
    return imprimir_logo(im, 752, 1050, 220, ang=2)


def recortar_tabuleiro(p, rodar=False):
    """Foto real do catálogo (tabuleiro preto sobre fundo cinzento claro) -> só o tabuleiro, fundo transparente."""
    import numpy as np
    im = abrir(p)
    a = np.asarray(im).astype(int)
    mx, mn = a.max(axis=2), a.min(axis=2)
    fundo = ((mx - mn) < 22) & (mx > 150)
    nao = ~fundo
    ys, xs = np.nonzero(nao)
    # caixa do tabuleiro = linhas/colunas com muito "não fundo"
    lin = nao.sum(axis=1) > a.shape[1] * 0.12
    col = nao.sum(axis=0) > a.shape[0] * 0.12
    y0, y1 = np.nonzero(lin)[0][[0, -1]]
    x0, x1 = np.nonzero(col)[0][[0, -1]]
    im = im.crop((x0, y0, x1, y1))
    m = Image.fromarray((nao[y0:y1, x0:x1] * 255).astype("uint8")).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))
    m = m.filter(ImageFilter.GaussianBlur(1.5))
    out = im.convert("RGBA"); out.putalpha(m)
    if rodar:
        out = out.rotate(90, expand=True)
    return out


# ---------------------------------------------------------------- cartões
def c1_capa():
    im = fundo_se(W, W, desfoque=6, brilho=0.8)
    im = escurecer(im, 520, 0.85, 760, 0.95).convert("RGBA")
    cabecalho(im, 1)
    d = ImageDraw.Draw(im)
    y = titulo_ajustado(d, [("O QUE TE FALTA", BRANCO), ("HOJE?", AMARELO)], 96, tam=140, entre=1.0)
    texto_sombra(d, (W / 2, y + 22), "Na Guarda, a Bora trata.", fonte("ExtraBold", 44), BRANCO, anchor="ma", s=3)
    # mosaico das 6 coisas, da largura do cartão (60..1020), legenda por BAIXO de cada foto (nada tapado)
    lw, lh, gap, leg = 304, 168, 24, 40
    x0 = (W - (3 * lw + 2 * gap)) // 2; yy = y + 90
    fr = fonte("ExtraBold", 28)
    for i, (n, rot) in enumerate(ROTULOS):
        x = x0 + (i % 3) * (lw + gap); yv = yy + (i // 3) * (lh + leg + 12)
        t = arredondar(foto_tile(n, lw, lh), 22)
        ImageDraw.Draw(t).rounded_rectangle([0, 0, lw - 1, lh - 1], radius=22, outline=(255, 255, 255, 220), width=4)
        com_sombra(im, t, x, yv, raio=10, desloc=8)
        texto_sombra(ImageDraw.Draw(im), (x + lw / 2, yv + lh + 6), rot, fr, BRANCO, anchor="ma", s=2)
    assert yy + 2 * (lh + leg + 12) <= 930, "mosaico da capa a entrar na barra"
    barra_baixo(im, y=932, h=118, texto="DESLIZA E VÊ TUDO", desliza=False)
    d = ImageDraw.Draw(im)
    seta(d, W - 44 - 90, 932 + 59 - 28, 56, AMARELO)
    return im


def cartao_titulo_esquerda(img, linhas, n, max_w=500, canto=(600, 430), dy=0):
    """Título alinhado à esquerda, no canto de cima, para não tapar a cara da pessoa (que está à direita)."""
    im = colocar(img, dy)
    im = ImageEnhance.Contrast(im).enhance(1.05)
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).rectangle([0, 0, canto[0], canto[1]], fill=210)
    m = m.filter(ImageFilter.GaussianBlur(70))
    im = Image.composite(Image.new("RGB", (W, W), ESCURO), im, m)
    im = escurecer(im, 140, 0.7, 820, 0.9).convert("RGBA")
    cabecalho(im, n)
    d = ImageDraw.Draw(im)
    t = 96
    while max(d.textlength(tx, font=impact(t)) for tx, _ in linhas) > max_w:
        t -= 2
    y = 118
    for tx, cor in linhas:
        texto_espacado(d, 46, y, tx, impact(t), cor, 5)
        y += int(t * 1.0)
    barra_baixo(im)
    return im


def c7_favores():
    return cartao_titulo_esquerda(cena_estafeta(), [("ESQUECESTE-TE DE", BRANCO), ("ALGUMA COISA?", BRANCO), ("VAMOS BUSCAR.", AMARELO)], 7, dy=-140, max_w=468)


def c5_limpeza():
    return cartao_titulo_esquerda(abrir(os.path.join(IA, "bora-tudo-limpeza-v1.png")),
                                  [("CASA A BRILHAR", BRANCO), ("SEM LEVANTARES", AMARELO), ("UM DEDO", AMARELO)], 5, max_w=468, canto=(540, 420), dy=-45)


def c2_supermercado():
    im = colocar(cena_saco(), 60)
    im = ImageEnhance.Contrast(im).enhance(1.05)
    im = escurecer(im, 330, 0.9, 820, 0.9).convert("RGBA")
    cabecalho(im, 2)
    d = ImageDraw.Draw(im)
    titulo_ajustado(d, [("AS COMPRAS DO SUPERMERCADO", BRANCO), ("À TUA PORTA", AMARELO)], 104, tam=84, max_w=990)
    barra_baixo(im)
    return im


def c4_comida():
    im = fundo_se(W, W, desfoque=14, brilho=0.55)
    im = escurecer(im, 420, 0.8, 820, 0.9).convert("RGBA")
    brilho_quente(im, W // 2, 610, 380, forca=110)
    cabecalho(im, 4)
    d = ImageDraw.Draw(im)
    y = titulo_ajustado(d, [("PIZZA, HAMBÚRGUER,", BRANCO), ("KEBAB…", AMARELO)], 104, tam=116)
    texto_sombra(d, (W / 2, y + 2), "O QUE TE APETECER", impact(54), AMARELO, anchor="ma", s=4)
    pratos = [("pds-pizza-m-11.jpg", "Pizza", None), ("boom-classico.webp", "Hambúrguer", (150, 0, 1050, 800)),
              ("pds-doner-kebab.jpg", "Kebab", (60, 250, 996, 880))]
    fotos = []
    for p, rot, cx in pratos:
        f = abrir(os.path.join(FOTOS, p))
        fotos.append((f.crop(cx) if cx else f, rot))
    gap = 14
    hh = int((W - 60 - 2 * gap) / sum(f.width / f.height for f, _ in fotos))
    x = 30; yf = y + 112
    for f, rot in fotos:
        lw = int(hh * f.width / f.height)
        t = arredondar(cobrir(f, lw, hh), 24)
        ImageDraw.Draw(t).rounded_rectangle([0, 0, lw - 1, hh - 1], radius=24, outline=(255, 255, 255, 230), width=5)
        com_sombra(im, t, x, yf, raio=16, desloc=12, forca=0.8)
        texto_sombra(ImageDraw.Draw(im), (x + lw / 2, yf + hh + 10), rot, fonte("ExtraBold", 40), BRANCO, anchor="ma", s=3)
        x += lw + gap
    texto_sombra(ImageDraw.Draw(im), (W / 2, yf + hh + 74), "Dos restaurantes da Guarda, à tua porta.", fonte("ExtraBold", 36), BRANCO, anchor="ma", s=3)
    assert yf + hh + 74 + 44 <= 928, "texto a entrar na barra"
    barra_baixo(im)
    return im


def c3_sushi():
    im = fundo_se(W, W, desfoque=14, brilho=0.55)
    im = escurecer(im, 420, 0.8, 820, 0.9).convert("RGBA")
    brilho_quente(im, W // 2, 640, 380, forca=120)
    cabecalho(im, 3)
    d = ImageDraw.Draw(im)
    titulo_ajustado(d, [("SUSHI HOJE", BRANCO), ("À NOITE?", AMARELO)], 110, tam=120)
    # foto real do catálogo; o fundo cinzento sai por enchimento a partir das bordas (o contorno preto do
    # tabuleiro isola o interior, por isso o arroz e o sésamo ficam intactos — 0 píxeis transparentes dentro)
    t = Image.open(os.path.join(FOTOS, "_fuku-t22-recorte.png")).convert("RGBA")
    r = min(960 / t.width, 540 / t.height)
    t = t.resize((int(t.width * r), int(t.height * r)), Image.LANCZOS)
    com_sombra(im, t, (W - t.width) // 2, 655 - t.height // 2, raio=30, desloc=24, forca=0.95)
    barra_baixo(im)
    return im


def prato(p, w, h):
    """Foto real do catálogo com o prato INTEIRO à vista (sem cortar o pão nem a borda da pizza)."""
    f = abrir(os.path.join(FOTOS, p))
    if p.startswith("boom-classico"):
        f = f.crop((150, 0, 1050, 800))      # o hambúrguer e as batatas, com folga por cima do pão
    elif p.startswith("pds-pizza"):
        f = f.crop((0, 0, f.width, f.height))
    elif p.startswith("pds-doner"):
        f = f.crop((40, 150, 1016, 910))
    return cobrir(f, w, h)


ROUPEIRO_RET = os.path.join(IA, "roupeiro_retocado.jpg")   # cabides a flutuar apagados (juiz 2.ª volta)
# enquadramento de cada coisa: (largo ~1,73:1, quadrado)
FOCO = {
    "saco": ((180, 560, 1080, 1080), (180, 300, 1080, 1200)),
    "limpeza": ((100, 250, 1254, 917), (150, 150, 1200, 1200)),
    "casa": ((150, 1300, 1536, 2100), (0, 1150, 1536, 2686)),
    "favores": ((330, 660, 1254, 1194), (254, 220, 1254, 1220)),
}


def foto_tile(nome, w, h):
    largo = w / h > 1.3
    if nome == "pizza":
        meio = (w - 8) // 2
        out = Image.new("RGB", (w, h), (10, 10, 12))
        out.paste(prato("pds-pizza-m-11.jpg", meio, h), (0, 0))
        out.paste(prato("boom-classico.webp", w - meio - 8, h), (meio + 8, 0))
        return out
    if nome == "sushi":
        foto = abrir(os.path.join(FOTOS, "fuku-t22.jpg"))
        if largo:
            foto = foto.crop((560, 0, 1710, 1703)).rotate(90, expand=True)
            return cobrir(foto, w, h, zoom=1.08)
        return cobrir(foto.crop((420, 0, 1850, 1703)), w, h, zoom=1.05)
    fonte_img = {"saco": cena_saco, "limpeza": lambda: abrir(os.path.join(IA, "bora-tudo-limpeza-v1.png")),
                 "casa": lambda: abrir(ROUPEIRO_RET), "favores": cena_estafeta}[nome]()
    if nome == "favores" and largo:
        return conter(fonte_img.crop((0, 200, 1254, 1225)), w, h)
    caixa = FOCO[nome][0 if largo else 1]
    return cobrir(fonte_img.crop(caixa), w, h)


def conter(img, w, h, margem=0):
    """A imagem inteira dentro de w x h (sem cortar), com o resto preenchido pela própria imagem desfocada e escura."""
    fundo = ImageEnhance.Brightness(cobrir(img, w, h).filter(ImageFilter.GaussianBlur(14))).enhance(0.55)
    r = min((w - 2 * margem) / img.width, (h - 2 * margem) / img.height)
    peq = img.resize((int(img.width * r), int(img.height * r)), Image.LANCZOS)
    fundo.paste(peq, ((w - peq.width) // 2, (h - peq.height) // 2))
    return fundo


def miniatura(nome):
    return foto_tile(nome, 400, 400)


def cartao_cena(img, linhas, n, fx=0.5, fy=0.5, zoom=1.0, topo=520, extra=None, tam=112, y0=110):
    im = cobrir(img, W, W, fx=fx, fy=fy, zoom=zoom)
    im = ImageEnhance.Contrast(im).enhance(1.05)
    im = escurecer(im, topo, 0.88, 800, 0.9).convert("RGBA")
    cabecalho(im, n)
    d = ImageDraw.Draw(im)
    titulo_ajustado(d, linhas, y0, tam=tam)
    if extra:
        extra(im)
    barra_baixo(im)
    return im


def cartao_comida(fotos, linhas, n, sub=None):
    im = fundo_se(W, W, desfoque=14, brilho=0.55)
    im = escurecer(im, 420, 0.8, 820, 0.9).convert("RGBA")
    brilho_quente(im, W // 2, 610, 360, forca=110)
    cabecalho(im, n)
    d = ImageDraw.Draw(im)
    y = titulo_ajustado(d, linhas, 110, tam=120)
    if sub:
        texto_sombra(d, (W / 2, y + 2), sub, fonte("ExtraBold", 46), AMARELO, anchor="ma", s=3)
    for (p, x, yy, lw, lh, zoom, ang) in fotos:
        f = cobrir(abrir(os.path.join(FOTOS, p)), lw, lh, zoom=zoom)
        f = arredondar(f, 30)
        d2 = ImageDraw.Draw(f)
        d2.rounded_rectangle([0, 0, lw - 1, lh - 1], radius=30, outline=(255, 255, 255, 230), width=6)
        if ang:
            f = f.rotate(ang, resample=Image.BICUBIC, expand=True)
        com_sombra(im, f, x, yy, raio=20, desloc=16, forca=0.8)
    barra_baixo(im)
    return im


def etiquetas_casa(im):
    """Selos amarelos de 2 linhas, na zona da janela (x < 270), longe do braço do profissional."""
    d = ImageDraw.Draw(im)
    for i, (nome, preco) in enumerate([("Montar roupeiro", "80 €"), ("Trocar torneira", "40 €")]):
        x0, y = 30, 400 + i * 190
        fN = fonte("ExtraBold", 25); fP = impact(70)
        w = max(d.textlength(nome, font=fN), d.textlength(preco, font=fP)) + 30
        d.rounded_rectangle([x0 + 5, y + 7, x0 + w + 5, y + 157], radius=18, fill=(0, 0, 0, 120))
        d.rounded_rectangle([x0, y, x0 + w, y + 150], radius=18, fill=AMARELO)
        d.text((x0 + w / 2, y + 34), nome, font=fN, fill=TINTA, anchor="mm")
        d.text((x0 + w / 2, y + 98), preco, font=fP, fill=TINTA, anchor="mm")
    assert x0 + w < 275, f"selo largo demais: {x0 + w}"


def c8_fecho():
    im = fundo_se(W, W, desfoque=10, brilho=0.7)
    im = escurecer(im, 600, 0.75, 600, 0.9).convert("RGBA")
    brilho_quente(im, W // 2, 420, 330, cor=(22, 163, 74), forca=90)
    cabecalho(im, 8)
    d = ImageDraw.Draw(im)
    titulo_ajustado(d, [("TUDO NUMA APP.", BRANCO)], 112, tam=150)
    # logo grande num cartão branco
    lw, lh = 620, 300
    x0 = (W - lw) // 2; y0 = 300
    caixa = Image.new("RGBA", (lw, lh), (255, 255, 255, 255))
    lg = logo(250)
    caixa.paste(lg, ((lw - lg.width) // 2, (lh - lg.height) // 2))
    com_sombra(im, arredondar(caixa.convert("RGB"), 36), x0, y0, raio=22, desloc=14)
    d = ImageDraw.Draw(im)
    fB = fonte("ExtraBold", 44); tB = "Código BEMVINDO = 5 € em tokens"; wB = d.textlength(tB, font=fB)
    d.rounded_rectangle([(W - wB) / 2 - 30, 646, (W + wB) / 2 + 30, 718], radius=36, fill=AMARELO)
    d.text((W / 2, 682), tB, font=fB, fill=TINTA, anchor="mm")
    # botão Transferir
    fT = fonte("ExtraBold", 56); tT = "Transferir"; wT = d.textlength(tT, font=fT)
    bw = wT + 170; bx = (W - bw) / 2; by = 756
    d.rounded_rectangle([bx, by + 8, bx + bw, by + 112], radius=56, fill=(12, 90, 40))
    d.rounded_rectangle([bx, by, bx + bw, by + 104], radius=52, fill=VERDE)
    # ícone de descarregar
    ix = bx + 58; iy = by + 52
    d.rectangle([ix - 6, iy - 28, ix + 6, iy + 4], fill=BRANCO)
    d.polygon([(ix - 22, iy - 4), (ix + 22, iy - 4), (ix, iy + 20)], fill=BRANCO)
    d.rectangle([ix - 24, iy + 24, ix + 24, iy + 30], fill=BRANCO)
    d.text((bx + 96 + wT / 2, by + 52), tT, font=fT, fill=BRANCO, anchor="mm")
    im = im.convert("RGB")
    fila_icones(im, 912, W)
    faixa_baixo(im, 1016)
    return im


# ---------------------------------------------------------------- mosaico (feed 4:5 e story 9:16)
ROTULOS = [("saco", "Supermercado"), ("sushi", "Sushi"), ("pizza", "Pizza e hambúrguer"),
           ("limpeza", "Limpeza"), ("casa", "Casa e Manutenção"), ("favores", "Favores")]


def ladrilho_rotulo(nome, rot, lado):
    t = Image.new("RGBA", (lado, lado + 64), (0, 0, 0, 0))
    f = arredondar(foto_tile(nome, lado, lado), 26)
    t.alpha_composite(f)
    d = ImageDraw.Draw(t)
    d.rounded_rectangle([0, 0, lado - 1, lado - 1], radius=26, outline=(255, 255, 255, 220), width=5)
    # mesma letra em todos os rótulos: a maior em que o rótulo mais comprido cabe (pode entrar no espaço entre ladrilhos)
    tam = 32
    while max(d.textlength(r_, font=fonte("ExtraBold", tam)) for _, r_ in ROTULOS) > lado + 22:
        tam -= 1
    fr = fonte("ExtraBold", tam)
    t2 = Image.new("RGBA", (lado + 30, lado + 64), (0, 0, 0, 0))
    t2.alpha_composite(t, (15, 0))
    texto_sombra(ImageDraw.Draw(t2), ((lado + 30) / 2, lado + 12), rot, fr, BRANCO, anchor="ma", s=2)
    return t2


MOS_FEED = dict(H=1350, top=40, t_tam=136, t_y=112, sub=None, grade=424, lado=220, rot=48, fila=18,
                pincel=1062, cta=1124, cta_h=116, icones=1252, onda=1316, esc=(0.45, 0.85, 0.55, 0.95))
# story: tudo o que importa entre y=266 e y=1648 (fora dos 250 px de cima e de baixo); a Sé fica à vista em cima
# e a onda verde/laranja vai até ao fundo da imagem
MOS_STORY = dict(H=1920, top=266, t_tam=150, t_y=350, sub=None, grade=680, lado=270, rot=50, fila=24,
                 pincel=1430, cta=1494, cta_h=118, icones=1618, onda=1856, esc=(0.22, 0.55, 0.55, 0.9))


def mosaico(L, nome):
    H = L["H"]
    im = fundo_se(W, H, desfoque=8, brilho=0.7)
    e = L["esc"]
    im = escurecer(im, int(H * e[0]), e[1], int(H * e[2]), e[3]).convert("RGBA")
    d = ImageDraw.Draw(im)
    top = L["top"]
    f = fonte("ExtraBold", 29); t = "A GUARDA TODA NUMA APP"; w = d.textlength(t, font=f)
    d.rounded_rectangle([48, top, 48 + w + 40, top + 56], radius=28, fill=LARANJA)
    d.text((48 + 20 + w / 2, top + 28), t, font=f, fill=BRANCO, anchor="mm")
    fB = fonte("ExtraBold", 29); tB = "BEMVINDO: 5 € em tokens"; wB = d.textlength(tB, font=fB)
    d.rounded_rectangle([W - 48 - wB - 40, top, W - 48, top + 56], radius=28, fill=AMARELO)
    d.text((W - 48 - 20 - wB / 2, top + 28), tB, font=fB, fill=TINTA, anchor="mm")
    assert 48 + w + 40 + 16 < W - 48 - wB - 40, "etiquetas de cima a tocar"
    titulo_ajustado(d, [("O QUE TE FALTA", BRANCO), ("HOJE?", AMARELO)], L["t_y"], tam=L["t_tam"], entre=1.0)
    if L["sub"]:
        texto_sombra(d, (W / 2, L["sub"]), "Na Guarda, a Bora trata:", fonte("ExtraBold", 44), BRANCO, anchor="ma", s=3)
    lado, gap = L["lado"], 26
    for i, (n, r) in enumerate(ROTULOS):
        cx = (W - (3 * lado + 2 * gap)) // 2 + (i % 3) * (lado + gap)
        cy = L["grade"] + (i // 3) * (lado + L["rot"] + L["fila"])
        com_sombra(im, ladrilho_rotulo(n, r, lado), cx - 15, cy, raio=12, desloc=10)
    pincel(im, W // 2, L["pincel"], 760, 84, "NA GUARDA, A BORA TRATA!", 58)
    d = ImageDraw.Draw(im)
    # caixa de chamada como na Boom / Amigo
    cy0 = L["cta"]; ch = L["cta_h"]
    d.rounded_rectangle([60, cy0, W - 60, cy0 + ch], radius=26, fill=(12, 12, 14, 235), outline=AMARELO, width=5)
    cw = 290
    d.rounded_rectangle([84, cy0 + 12, 84 + cw, cy0 + ch - 12], radius=14, fill=BRANCO)
    lg = logo(min(int(cw * 0.94 * 580 / 1260), ch - 26))
    im.paste(lg, (84 + (cw - lg.width) // 2, cy0 + (ch - lg.height) // 2))
    cx = (84 + cw + W - 60) // 2
    italico(im, "PEDE JÁ!", int(ch * 0.46), cx, cy0)
    d.line([(cx - 120, cy0 + ch * 0.66), (cx + 130, cy0 + ch * 0.63)], fill=LARANJA, width=6)
    d.text((cx, cy0 + ch * 0.80), "NA APP BORA", font=impact(int(ch * 0.20)), fill=BRANCO, anchor="mm")
    im = im.convert("RGB")
    fila_icones(im, L["icones"], H)
    faixa_baixo(im, L["onda"])
    im.save(os.path.join(SAIDA, nome), quality=93, subsampling=0)
    print("feito", nome, im.size)


def guardar(im, nome):
    im.convert("RGB").save(os.path.join(SAIDA, nome), quality=93, subsampling=0)
    print("feito", nome, im.size)


if __name__ == "__main__":
    so = sys.argv[1:]
    def quer(k): return not so or k in so
    if quer("1"): guardar(c1_capa(), "tudo-1-capa.jpg")
    if quer("2"): guardar(c2_supermercado(), "tudo-2-supermercado.jpg")
    if quer("3"): guardar(c3_sushi(), "tudo-3-sushi.jpg")
    if quer("4"): guardar(c4_comida(), "tudo-4-pizza-hamburguer.jpg")
    if quer("5"): guardar(c5_limpeza(), "tudo-5-limpeza.jpg")
    if quer("6"): guardar(cartao_cena(abrir(ROUPEIRO_RET).crop((0, 860, 1536, 2396)), [("ROUPEIRO POR MONTAR?", BRANCO), ("TORNEIRA A PINGAR?", AMARELO)], 6, extra=etiquetas_casa), "tudo-6-casa.jpg")
    if quer("7"): guardar(c7_favores(), "tudo-7-favores.jpg")
    if quer("8"): guardar(c8_fecho(), "tudo-8-fecho.jpg")
    if quer("m"): mosaico(MOS_FEED, "tudo-mosaico-feed.jpg")
    if quer("s"): mosaico(MOS_STORY, "tudo-mosaico-story.jpg")
