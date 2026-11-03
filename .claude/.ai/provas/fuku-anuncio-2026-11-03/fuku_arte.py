"""Peças do anúncio do Fuku Sushi (missão fuku-anuncio-2026-11-03).

Regra: o sushi vem SÓ das fotos reais do catálogo do Fuku (recortadas, não alteradas); o cenário (mesa,
porta, luz) vem do Gemini; os ecrãs são capturas reais da app web; o selo do Fuku é a foto real do
letreiro dele; o logótipo da Bora é o do repositório. Saídas: reel 9:16 (15 s), imagem 1:1, imagem 9:16.
Uso: python fuku_arte.py <pasta_trabalho> <pasta_saida> [reel|imagens|tudo|frames]
"""
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H, FPS, DUR = 1080, 1920, 30, 15.0
FONTE = r"C:/BoraLocal/projetosflutter/bora_app/assets/fonts/Inter-VariableFont.ttf"
VERDE, LARANJA, BRANCO = (22, 163, 74), (249, 115, 22), (255, 255, 255)
T, OUT = sys.argv[1], sys.argv[2]
MODO = sys.argv[3] if len(sys.argv) > 3 else "tudo"
SEGURO_CIMA, SEGURO_BAIXO = 270, H - 270  # zona segura dos Stories (250 px + folga)


def fonte(tam, peso=800):
    f = ImageFont.truetype(FONTE, tam)
    f.set_variation_by_axes([min(32, tam), peso])
    return f


def abrir(p, modo="RGBA"):
    return Image.open(p).convert(modo)


_BORA = None


def bora_sem_fundo():
    global _BORA
    if _BORA is None:
        im = abrir(f"{T}/logo/bora_logo.png", "RGB")
        quase = im.convert("L").point(lambda v: 255 if v > 236 else 0)
        marca = Image.new("L", im.size, 0)
        w, h = im.size
        for sd in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
            tmp = quase.copy()
            ImageDraw.floodfill(tmp, sd, 128)
            marca = ImageChops.lighter(marca, tmp.point(lambda v: 255 if v == 128 else 0))
        alfa = ImageChops.invert(marca).filter(ImageFilter.GaussianBlur(0.8))
        _BORA = im.convert("RGBA")
        _BORA.putalpha(alfa)
        _BORA = _BORA.crop(alfa.getbbox())
    return _BORA


# ── recursos ────────────────────────────────────────────────────────────────
def recorte_caixa(p):
    """Tira o fundo cinzento liso à volta da caixa (inundação a partir das bordas), sem mexer na caixa."""
    im = abrir(p, "RGB")
    a = np.asarray(im).astype(int)
    canto = np.median(np.concatenate([a[:8, :8].reshape(-1, 3), a[-8:, -8:].reshape(-1, 3),
                                      a[:8, -8:].reshape(-1, 3), a[-8:, :8].reshape(-1, 3)]), axis=0)
    # fundo = cinzento sem cor e não escuro (a sombra cinzenta também); o rebordo preto da caixa trava a inundação
    sat = a.max(axis=2) - a.min(axis=2)
    lum = a.mean(axis=2)
    perto = (((sat < 38) & (lum > 85)) | (np.abs(a - canto).sum(axis=2) < 60)).astype("uint8") * 255
    m = Image.fromarray(perto)
    marca = Image.new("L", im.size, 0)
    w, h = im.size
    for s in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        tmp = m.copy()
        if tmp.getpixel(s) == 255:
            ImageDraw.floodfill(tmp, s, 128)
            marca = ImageChops.lighter(marca, tmp.point(lambda v: 255 if v == 128 else 0))
    # forma da caixa: o rebordo preto é escuro; a caixa = retângulo de cantos redondos que o contém
    escuro = (lum < 70)
    ys, xs = np.where(escuro)
    x0, x1 = np.percentile(xs, [0.3, 99.7]).astype(int)
    y0, y1 = np.percentile(ys, [0.3, 99.7]).astype(int)
    alfa = Image.new("L", im.size, 0)
    raio = int(0.06 * (x1 - x0))
    ImageDraw.Draw(alfa).rounded_rectangle([x0 + 13, y0 + 13, x1 - 13, y1 - 13], raio, fill=255)
    alfa = alfa.filter(ImageFilter.GaussianBlur(2))
    out = im.convert("RGBA")
    out.putalpha(alfa)
    return out.crop(alfa.getbbox())


def sombra(img, raio=40, opac=170, desl=(0, 30)):
    s = Image.new("RGBA", (img.width + raio * 4, img.height + raio * 4), (0, 0, 0, 0))
    a = img.getchannel("A").point(lambda v: opac if v > 20 else 0)
    preto = Image.new("RGBA", img.size, (0, 0, 0, 255))
    preto.putalpha(a)
    s.alpha_composite(preto, (raio * 2 + desl[0], raio * 2 + desl[1]))
    return s.filter(ImageFilter.GaussianBlur(raio))


def cobrir(img, w, h, zoom=1.0, cx=0.5, cy=0.5):
    """Redimensiona para cobrir w×h (com zoom) e recorta à volta de (cx, cy)."""
    esc = max(w / img.width, h / img.height) * zoom
    nw, nh = round(img.width * esc), round(img.height * esc)
    r = img.resize((nw, nh), Image.LANCZOS)
    x = min(max(0, round(nw * cx - w / 2)), nw - w)
    y = min(max(0, round(nh * cy - h / 2)), nh - h)
    return r.crop((x, y, x + w, y + h))


def texto(img, t, f, cor, y, x=None, sombra_on=True, ancora="c"):
    cx = f.getbbox(t)
    tw = cx[2] - cx[0]
    if x is None:
        x = (img.width - tw) // 2 - cx[0]
    elif ancora == "l":
        x = x - cx[0]
    if sombra_on:
        s = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(s).text((x + 3, y - cx[1] + 5), t, font=f, fill=(0, 0, 0, 200))
        img.alpha_composite(s.filter(ImageFilter.GaussianBlur(7)))
    ImageDraw.Draw(img).text((x, y - cx[1]), t, font=f, fill=cor)
    return y + (cx[3] - cx[1])


def selo(t, f, fundo, cor=BRANCO, px=34, py=18):
    cx = f.getbbox(t)
    pw, ph = cx[2] - cx[0] + 2 * px, cx[3] - cx[1] + 2 * py
    s = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    ImageDraw.Draw(s).rounded_rectangle([0, 0, pw - 1, ph - 1], ph // 2, fill=fundo + (255,))
    ImageDraw.Draw(s).text((px - cx[0], py - cx[1]), t, font=f, fill=cor)
    return s


def colar_centro(img, peca, y, x=None):
    x = (img.width - peca.width) // 2 if x is None else x
    img.alpha_composite(peca, (x, y))
    return y + peca.height


def logo_bora_cartao(larg):
    bora = abrir(f"{T}/logo/bora_logo.png")
    bora = bora.resize((larg - 50, round((larg - 50) * bora.height / bora.width)), Image.LANCZOS)
    c = Image.new("RGBA", (larg, bora.height + 40), (0, 0, 0, 0))
    ImageDraw.Draw(c).rounded_rectangle([0, 0, larg - 1, c.height - 1], 26, fill=(255, 255, 255, 255))
    c.alpha_composite(bora, (25, 20))
    return c


def logo_fuku(larg):
    f = abrir(f"{T}/logo/fuku-logo.png")
    return f.resize((larg, round(larg * f.height / f.width)), Image.LANCZOS)


def escurecer(img, cima=0.0, baixo=0.0, meio=0.0):
    """Véu escuro em gradiente para o texto ler-se bem."""
    w, h = img.size
    g = np.zeros((h, 1), dtype=float)
    for i in range(h):
        t = i / h
        g[i] = max(cima * (1 - t / 0.45) if t < 0.45 else 0, baixo * ((t - 0.5) / 0.5) if t > 0.5 else 0, meio)
    a = (np.clip(g, 0, 1) * 255).astype("uint8").repeat(w, axis=1)
    v = Image.new("RGBA", (w, h), (8, 6, 5, 255))
    v.putalpha(Image.fromarray(a))
    img.alpha_composite(v)


CAIXA_T22 = None
MESA = PORTA = None
ECRA_GRELHA = ECRA_CARRINHO = ECRA_UMA = None
FOTOS = {}


def carregar():
    global CAIXA_T22, MESA, PORTA, ECRA_GRELHA, ECRA_CARRINHO
    CAIXA_T22 = recorte_caixa(f"{T}/fotos/t22.jpg")
    MESA = abrir(f"{T}/cenas/gem_mesa_cima.jpg")
    PORTA = porta_com_marca()
    ECRA_GRELHA = abrir(f"{T}/app2/app-2-caixas.png")
    global ECRA_UMA
    ECRA_UMA = abrir(f"{T}/app2/app-3a-uma.png")
    ECRA_CARRINHO = abrir(f"{T}/app2/app-3-no-carrinho.png")
    for k in ["t22", "t20", "t33"]:
        FOTOS[k] = abrir(f"{T}/fotos/{k}.jpg")


def porta_com_marca():
    """Cena do Gemini + logótipo da Bora impresso no saco e na faixa verde da carrinha (por código)."""
    p = abrir(f"{T}/cenas/gem_porta.jpg")
    bora = bora_sem_fundo()
    # saco: logótipo "impresso" no papel kraft (multiplicar), inclinado como o saco, com a luz do papel
    lw = 330
    lb = bora.resize((lw, round(lw * bora.height / bora.width)), Image.LANCZOS).rotate(-2, resample=Image.BICUBIC, expand=True)
    from PIL import ImageEnhance
    lb = Image.merge('RGBA', (*ImageEnhance.Color(lb.convert('RGB')).enhance(0.72).split(), lb.getchannel('A')))
    cx0, cy0 = 775 - lb.width // 2, 1868 - lb.height // 2
    zona = p.crop((cx0, cy0, cx0 + lb.width, cy0 + lb.height)).convert("RGB")
    tinta = Image.new("RGB", lb.size, (255, 255, 255))
    tinta.paste(lb.convert("RGB"), (0, 0), lb.getchannel("A"))
    impresso = ImageChops.multiply(zona, tinta)
    alfa = lb.getchannel("A").point(lambda v: int(v * 0.84)).filter(ImageFilter.GaussianBlur(1.0))
    p.paste(impresso, (cx0, cy0), alfa)
    # carrinha ao fundo: "BORA" em branco pintado na faixa verde (remendo da cor da faixa tapa o emblema)
    letras = Image.new("RGBA", (220, 70), (0, 0, 0, 0))
    fb = fonte(30, 900)
    bx = fb.getbbox("BORA")
    ImageDraw.Draw(letras).text((110 - (bx[2] - bx[0]) // 2 - bx[0], 35 - (bx[3] - bx[1]) // 2 - bx[1]), "BORA", font=fb, fill=(250, 250, 248, 205))
    p.alpha_composite(letras.filter(ImageFilter.GaussianBlur(3.2)), (1222 - 110, 1509 - 35))
    return p


def telefone(ecra, larg=560):
    """Moldura simples de telemóvel à volta de uma captura real."""
    e = ecra.resize((larg, round(larg * ecra.height / ecra.width)), Image.LANCZOS)
    b = 18
    t = Image.new("RGBA", (larg + 2 * b, e.height + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(t).rounded_rectangle([0, 0, t.width - 1, t.height - 1], 64, fill=(14, 14, 16, 255))
    m = Image.new("L", e.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, e.width - 1, e.height - 1], 48, fill=255)
    t.paste(e, (b, b), m)
    return t, larg / ecra.width, b


# ── planos ──────────────────────────────────────────────────────────────────
def ease(t):
    t = min(max(t, 0), 1)
    return t * t * (3 - 2 * t)


def plano_gancho(t):  # 0–3 s
    img = cobrir(MESA, W, H, zoom=1.0 + 0.06 * t / 3).copy()
    # brilho quente atrás da caixa
    luz = Image.new("L", (W, H), 0)
    ImageDraw.Draw(luz).ellipse([140, 760, 940, 1620], fill=int(120 * ease(t / 0.8)))
    luz = luz.filter(ImageFilter.GaussianBlur(120))
    img = Image.composite(Image.new("RGBA", (W, H), (255, 170, 90, 255)), img, luz)
    # caixa real T22 sobe e cresce um pouco (a "abrir-se" para a câmara)
    k = ease(t / 1.1)
    larg = int(560 + 120 * k + 40 * t / 3)
    cx = CAIXA_T22.resize((larg, round(larg * CAIXA_T22.height / CAIXA_T22.width)), Image.LANCZOS)
    cx = cx.rotate(-4 * (1 - k), resample=Image.BICUBIC, expand=True)
    y = int(1680 - cx.height - 140 * k)
    sh = sombra(cx, 30, 240, desl=(0, 42))
    img.alpha_composite(sh, ((W - sh.width) // 2, y - 60))
    img.alpha_composite(cx, ((W - cx.width) // 2, y))
    # varrimento de brilho (reflexo) por cima da caixa entre 0,6 e 1,6 s
    if False:  # brilho tirado (juiz ronda 4)
        s = (t - 0.6) / 1.0
        brilho = Image.new("L", (W, H), 0)
        xx = int(-300 + 1700 * s)
        ImageDraw.Draw(brilho).polygon([(xx, 700), (xx + 140, 700), (xx - 260, 1800), (xx - 400, 1800)], fill=70)
        brilho = brilho.filter(ImageFilter.GaussianBlur(30))
        img = Image.composite(Image.new("RGBA", (W, H), (255, 245, 225, 255)), img, brilho)
    escurecer(img, cima=0.75)
    a = 1.0
    if a > 0:
        cam = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        y2 = texto(cam, "Sushi do Fuku.", fonte(112, 850), BRANCO, SEGURO_CIMA + 30)
        texto(cam, "Em casa.", fonte(112, 850), (255, 214, 170), y2 + 34)
        cam.putalpha(cam.getchannel("A").point(lambda v: int(v * a)))
        img.alpha_composite(cam, (0, int(30 * (1 - a))))
    return img


ROTULOS = [("t22", "T22 Frio e Quente", 0.50, 0.50), ("t20", "T20 Sushi Frito", 0.50, 0.50),
           ("t33", "T33 Gunkan", 0.50, 0.50)]


def plano_cortes(t):  # 2,5–6 s, três pratos reais no mesmo formato: cartão do mesmo tamanho, nome por baixo
    d = 3.5 / 3
    i = min(2, int(t / d))
    tt = t - i * d
    k, nome, _, _ = ROTULOS[i]
    foto = FOTOS[k]
    img = cobrir(foto, W, H).filter(ImageFilter.GaussianBlur(45)).copy()
    escurecer(img, meio=0.55)
    caixa_w, caixa_h = 940, 705
    z = 1.0 + 0.03 * tt
    esc = min(caixa_w / foto.width, caixa_h / foto.height) * z
    fw, fh = round(foto.width * esc), round(foto.height * esc)
    f2 = foto.resize((fw, fh), Image.LANCZOS)
    mk = Image.new("L", f2.size, 0)
    ImageDraw.Draw(mk).rounded_rectangle([0, 0, fw - 1, fh - 1], 36, fill=255)
    f2.putalpha(mk)
    cy = 470 + caixa_h // 2
    x, y = (W - fw) // 2, cy - fh // 2
    img.alpha_composite(sombra(f2, 36, 170), (x - 72, y - 72 + 26))
    img.alpha_composite(f2, (x, y))
    fk = logo_fuku(380)
    img.alpha_composite(fk, ((W - fk.width) // 2, SEGURO_CIMA + 10))
    yt = 470 + caixa_h + 60
    yt = texto(img, nome, fonte(78, 850), BRANCO, yt) + 22
    texto(img, "Fuku Sushi · Guarda", fonte(46, 600), (255, 214, 170), yt)
    return img


def fundo_escuro():
    img = Image.new("RGBA", (W, H), (16, 12, 10, 255))
    d = ImageDraw.Draw(img)
    for i in range(H):
        u = i / H
        d.line([(0, i), (W, i)], fill=(int(36 - 20 * u), int(22 - 10 * u), int(16 - 8 * u), 255))
    luz = Image.new("L", (W, H), 0)
    ImageDraw.Draw(luz).ellipse([W * 0.05, H * 0.2, W * 0.95, H * 0.75], fill=130)
    luz = luz.filter(ImageFilter.GaussianBlur(160))
    return Image.composite(Image.new("RGBA", (W, H), (150, 70, 26, 255)), img, luz)


TOQUE_ECRA = (349 * 3, 400 * 3)  # onde se tocou no "+" da T2 (pixéis da captura 1170x2532)


def plano_app(t):  # 7–11 s: grelha real 2 s com dois toques no +, depois a barra do carrinho 26,80 € 2 s
    img = fundo_escuro()
    segundo = t >= 2.4
    if t >= 2.4:
        ecra = ECRA_CARRINHO
    elif t >= 2.05:
        ecra = ECRA_UMA
    else:
        ecra = ECRA_GRELHA
    tel, esc, b = telefone(ecra, 680)
    x0, y0 = (W - tel.width) // 2, 372
    img.alpha_composite(sombra(tel, 40, 150), (x0 - 80, y0 - 80 + 30))
    img.alpha_composite(tel, (x0, y0))
    tx, ty = x0 + b + TOQUE_ECRA[0] * esc, y0 + b + TOQUE_ECRA[1] * esc
    for t0 in (2.0, 2.35):  # dois toques, cada um um anel laranja pequeno à volta do "+"
        s0 = (t - t0) / 0.35
        if 0 <= s0 <= 1.0:
            r = 22 + 16 * min(s0, 1)
            al = int(255 * (1 - min(s0, 1)) * 0.75 + 70)
            ImageDraw.Draw(img).ellipse([tx - r, ty - r, tx + r, ty + r], outline=(249, 115, 22, al), width=6)
    if segundo:
        s = selo("Entrega grátis a partir de 22 €", fonte(54, 850), LARANJA)
        colar_centro(img, s, SEGURO_CIMA + 0)
    else:
        texto(img, "Escolhes a caixa na app Bora", fonte(60, 850), BRANCO, SEGURO_CIMA + 0)
    return img


def plano_porta(t):  # 11–13 s
    img = cobrir(PORTA, W, H, zoom=1.0 + 0.05 * t / 2, cx=0.5, cy=0.56).copy()
    escurecer(img, cima=0.65)
    texto(img, "Um estafeta da Guarda", fonte(70, 850), BRANCO, SEGURO_CIMA + 30)
    texto(img, "leva-ta à porta.", fonte(70, 850), (255, 214, 170), SEGURO_CIMA + 125)
    return img


def cartao_final(W_, H_, quadrado=False):
    """Cartão de fecho (também é a base da imagem 9:16 e 1:1)."""
    img = Image.new("RGBA", (W_, H_), (0, 0, 0, 0))
    img.alpha_composite(cobrir(fundo_escuro(), W_, H_))
    return img


def plano_fecho(t):  # 13–15 s
    img = fundo_escuro()
    a = ease(t / 0.35)
    y = SEGURO_CIMA + 130
    alt = 150
    fk = abrir(f"{T}/logo/fuku-logo.png"); fk = fk.resize((round(alt * fk.width / fk.height), alt), Image.LANCZOS)
    bc = cartao_bora_escuro(alt)
    gap = 26
    x = (W - (fk.width + gap + bc.width)) // 2
    img.alpha_composite(fk, (x, y)); img.alpha_composite(bc, (x + fk.width + gap, y))
    y += alt + 40
    cx = CAIXA_T22.resize((400, round(400 * CAIXA_T22.height / CAIXA_T22.width)), Image.LANCZOS)
    sh = sombra(cx, 30, 170)
    img.alpha_composite(sh, ((W - sh.width) // 2, y - 60 + 30))
    img.alpha_composite(cx, ((W - cx.width) // 2, y))
    y += cx.height + 40
    s = selo("ENTREGA GRÁTIS A PARTIR DE 22 €", fonte(54, 850), LARANJA)
    y = colar_centro(img, s, y) + 24
    y = texto(img, "Código BEMVINDO = 5 € em tokens", fonte(54, 800), BRANCO, y) + 30
    bt = selo("Descarregar", fonte(56, 850), VERDE, px=80, py=24)
    y = colar_centro(img, bt, y) + 20
    y = texto(img, "Acima de 22 €: pagas só a taxa de serviço e o saco.", fonte(36, 600), (235, 220, 205), y)
    assert y < SEGURO_BAIXO + 20, y
    if a < 1:
        img.putalpha(img.getchannel("A").point(lambda v: int(v * a)))
        base = Image.new("RGBA", (W, H), (0, 0, 0, 255))
        base.alpha_composite(img)
        img = base
    return img


def cartao_bora_escuro(alt):
    """Logótipo Bora (sem fundo) num cartão escuro com a mesma borda e o mesmo raio do selo do Fuku."""
    lb0 = bora_sem_fundo()
    ih = round(alt * 0.72)
    lb = lb0.resize((round(ih * lb0.width / lb0.height), ih), Image.LANCZOS)
    c = Image.new("RGBA", (lb.width + round(alt * 0.5), alt), (0, 0, 0, 0))
    raio = max(10, round(40 * alt / 350))
    borda = max(2, round(4 * alt / 350))
    ImageDraw.Draw(c).rounded_rectangle([0, 0, c.width - 1, alt - 1], raio, fill=(26, 22, 18, 255))
    c.alpha_composite(lb, ((c.width - lb.width) // 2, (alt - ih) // 2))
    ImageDraw.Draw(c).rounded_rectangle([1, 1, c.width - 2, alt - 2], raio, outline=(255, 140, 90, 200), width=borda)
    return c


PLANOS = [(0.0, 2.5, plano_gancho), (2.5, 6.0, plano_cortes), (6.0, 11.0, plano_app),
          (11.0, 13.0, plano_porta), (13.0, 15.0, plano_fecho)]


def quadro(tg):
    for a, b, f in PLANOS:
        if a <= tg < b:
            return f(tg - a).convert("RGB")
    return PLANOS[-1][2](PLANOS[-1][1] - PLANOS[-1][0] - 1e-3).convert("RGB")


def reel():
    n = int(DUR * FPS)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
           "-r", str(FPS), "-i", "-", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-shortest",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "medium", "-crf", "19", "-r", str(FPS),
           "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", f"{OUT}/fuku-reel-9x16.mp4"]
    pr = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(n):
        pr.stdin.write(quadro(i / FPS).tobytes())
        if i % 60 == 0:
            print("quadro", i, flush=True)
    pr.stdin.close()
    pr.wait()
    print("reel ok", pr.returncode)


def frames():  # fotogramas de prova para o juiz
    for tg in [0.0, 1.5, 3.0, 4.2, 5.4, 7.0, 8.2, 10.0, 12.0, 14.2]:
        quadro(tg).save(f"{OUT}/frame-{tg:04.1f}.jpg", quality=88)
    print("frames ok")


def imagem(W_, H_, nome):
    img = Image.new("RGBA", (W_, H_))
    img.alpha_composite(cobrir(MESA, W_, H_).convert("RGBA"))
    luz = Image.new("L", (W_, H_), 0)
    ImageDraw.Draw(luz).ellipse([W_ * 0.1, H_ * 0.35, W_ * 0.9, H_ * 0.85], fill=110)
    luz = luz.filter(ImageFilter.GaussianBlur(110))
    img = Image.composite(Image.new("RGBA", (W_, H_), (255, 170, 90, 255)), img, luz)
    escurecer(img, cima=0.8, baixo=0.85)
    quad = W_ == H_
    m = 60 if quad else SEGURO_CIMA
    alt = 130 if quad else 160
    fk = abrir(f"{T}/logo/fuku-logo.png"); fk = fk.resize((round(alt * fk.width / fk.height), alt), Image.LANCZOS)
    bc = cartao_bora_escuro(alt)
    gap = 30
    x = (W_ - (fk.width + gap + bc.width)) // 2
    yl = m
    img.alpha_composite(fk, (x, yl))
    img.alpha_composite(bc, (x + fk.width + gap, yl))
    y = yl + max(fk.height, bc.height) + (34 if quad else 60)
    f1 = fonte(74 if quad else 92, 850)
    y = texto(img, "O sushi do Fuku,", f1, BRANCO, y) + 18
    y = texto(img, "em casa na Guarda.", f1, (255, 214, 170), y) + (20 if quad else 50)
    larg = 470 if quad else 700
    cx = CAIXA_T22.resize((larg, round(larg * CAIXA_T22.height / CAIXA_T22.width)), Image.LANCZOS)
    rodape_h = 300 if quad else 420
    yb = H_ - (40 if quad else 270) - rodape_h
    yc = min(y, yb - cx.height - 10)
    if yc < y - 5:  # caixa grande demais: encolhe
        alt = max(200, yb - 10 - y)
        cx = cx.resize((round(cx.width * alt / cx.height), alt), Image.LANCZOS)
        yc = y
    sh = sombra(cx, 30, 180)
    img.alpha_composite(sh, ((W_ - sh.width) // 2, yc - 60 + 30))
    img.alpha_composite(cx, ((W_ - cx.width) // 2, yc))
    y = yb + 10
    s = selo("ENTREGA GRÁTIS A PARTIR DE 22 €", fonte(46 if quad else 54, 850), LARANJA)
    y = colar_centro(img, s, y) + 22
    y = texto(img, "Código BEMVINDO = 5 € em tokens", fonte(44 if quad else 52, 800), BRANCO, y) + 26
    bt = selo("Descarregar a app Bora", fonte(42 if quad else 50, 850), VERDE, px=50, py=18)
    y = colar_centro(img, bt, y) + 16
    texto(img, "Acima de 22 €: pagas só a taxa de serviço e o saco.", fonte(34 if quad else 36, 600),
          (220, 205, 190), y)
    img.convert("RGB").save(f"{OUT}/{nome}", quality=92)
    print(nome, "ok")


if __name__ == "__main__":
    carregar()
    if MODO in ("imagens", "tudo"):
        imagem(1080, 1080, "fuku-1x1.jpg")
        imagem(1080, 1920, "fuku-9x16.jpg")
    if MODO in ("frames", "tudo"):
        frames()
    if MODO in ("reel", "tudo"):
        reel()
