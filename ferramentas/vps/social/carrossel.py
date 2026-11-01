#!/usr/bin/env python3
# carrossel.py - monta as folhas de um carrossel do Bora, 1080x1350.
# Escrito 2026-09-04, missao crescer-bora-04-09 (Bloco B1).
#
#   carrossel.py --serie coisas-que-faz --saida-dir /opt/data/social/saidas/carrossel/<data>
#
# Segue /opt/data/social/design-kit.md: verde #16A34A -> #053D28, laranja
# #F97316 SO na chamada da ultima folha, Inter, raios 14/16, margem 72.
# Nunca desenha um icone novo: usa os cat_*.png reais do app.

import argparse
import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

import sys as _sys
if '/opt/data/social' not in _sys.path:
    _sys.path.insert(0, '/opt/data/social')
from bora_qr import colar_qr as _colar_qr

B = "/opt/data/social"
W, H = 1080, 1350
MARGEM = 72
VERDE = (22, 163, 74)
VERDE_FUNDO = (5, 61, 40)
VERDE_TINTA = (220, 252, 231)
LARANJA = (249, 115, 22)
BRANCO = (255, 255, 255)
INTER = B + "/fontes/Inter-VariableFont.ttf"
DEJAVU_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
DEJAVU_R = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
LINK_PLAY = "boraguarda.com/baixar"
LINK_WEB = "app.boraguarda.com"

_avisos = []


def fonte(tam, bold=True):
    try:
        f = ImageFont.truetype(INTER, tam)
        try:
            f.set_variation_by_name("ExtraBold" if bold else "Regular")
        except Exception:
            pass
        return f
    except Exception:
        _avisos.append("Inter indisponivel: caiu no DejaVu (o kit manda dizer isto)")
        return ImageFont.truetype(DEJAVU_B if bold else DEJAVU_R, tam)


def fundo():
    im = Image.new("RGB", (W, H), VERDE)
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / float(H - 1)
        cor = tuple(int(VERDE[i] * (1 - t) + VERDE_FUNDO[i] * t) for i in range(3))
        d.line([(0, y), (W, y)], fill=cor)
    return im


def quebrar(d, texto, f, larg):
    linhas, atual = [], ""
    for p in texto.split():
        t = (atual + " " + p).strip()
        if d.textlength(t, font=f) <= larg:
            atual = t
        else:
            if atual:
                linhas.append(atual)
            atual = p
    if atual:
        linhas.append(atual)
    return linhas


def ajustar(d, texto, larg, max_linhas, tmax, tmin):
    for tam in range(tmax, tmin - 1, -4):
        f = fonte(tam)
        ls = quebrar(d, texto, f, larg)
        if len(ls) <= max_linhas:
            return f, ls
    f = fonte(tmin)
    return f, quebrar(d, texto, f, larg)[:max_linhas]


def cartao_icone(ico, lado, raio=56):
    """Os cat_*.png do app trazem margem BRANCA OPACA a volta, com halo suave.
    Duas tentativas de a CORTAR falharam (04/09): sobrava sempre uma faixa,
    porque o halo nao e branco puro. A abordagem que resolve e outra -- em vez
    de lutar contra o branco, assume-se: arredonda-se o icone para ele ler como
    um CARTAO do design system (raio 16 do app, a escala desta peca). O branco
    do ficheiro passa a ser o fundo do cartao, e nao um erro."""
    ico = ico.convert("RGBA")
    ico.thumbnail((lado, lado), Image.LANCZOS)
    w, h = ico.size
    cartao = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    cartao.alpha_composite(ico)
    mascara = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mascara).rounded_rectangle([0, 0, w - 1, h - 1], radius=raio, fill=255)
    cartao.putalpha(mascara)
    return cartao


def por_logo(im, caminho, x, y, alt=96):
    if not caminho or not os.path.exists(caminho):
        return
    lg = Image.open(caminho).convert("RGBA")
    r = alt / float(lg.height)
    lg = lg.resize((max(1, int(lg.width * r)), alt), Image.LANCZOS)
    placa = Image.new("RGBA", (lg.width + 36, alt + 28), (0, 0, 0, 0))
    ImageDraw.Draw(placa).rounded_rectangle(
        [0, 0, placa.width - 1, placa.height - 1], radius=14, fill=(255, 255, 255, 240))
    placa.alpha_composite(lg, (18, 14))
    im.paste(placa, (x, y), placa)


def cabecalho(im, n, total):
    por_logo(im, B + "/imagens/bora_logo.png", MARGEM, MARGEM, 76)
    d = ImageDraw.Draw(im)
    f = fonte(30, False)
    t = "%d/%d" % (n, total)
    d.text((W - MARGEM - d.textlength(t, font=f), MARGEM + 32), t, font=f, fill=(210, 235, 220))


def rodape_link(d, y):
    f = fonte(30, False)
    d.text((MARGEM, y), "Bora — Guarda · %s · %s" % (LINK_PLAY, LINK_WEB),
           font=f, fill=(225, 245, 232))


def folha_gancho(s, n, total):
    im = fundo()
    d = ImageDraw.Draw(im)
    cabecalho(im, n, total)
    f, ls = ajustar(d, s["gancho"], W - 2 * MARGEM, 4, 118, 62)
    alt = len(ls) * (f.size + 14)
    y = (H - alt) // 2 - 60
    for l in ls:
        d.text((MARGEM, y), l, font=f, fill=BRANCO)
        y += f.size + 14
    fs = fonte(40, False)
    for l in quebrar(d, s.get("subgancho", ""), fs, W - 2 * MARGEM):
        y += 18
        d.text((MARGEM, y), l, font=fs, fill=VERDE_TINTA)
        y += fs.size
    d.text((MARGEM, H - MARGEM - 46), "Desliza →", font=fonte(34, False), fill=(200, 235, 214))
    return im


def _titulo_e_linha(im, d, nome, linha, topo):
    f, ls = ajustar(d, nome, W - 2 * MARGEM, 2, 86, 52)
    y = topo
    for l in ls:
        d.text((MARGEM, y), l, font=f, fill=BRANCO)
        y += f.size + 10
    fl = fonte(38, False)
    y += 12
    for l in quebrar(d, linha, fl, W - 2 * MARGEM):
        d.text((MARGEM, y), l, font=fl, fill=VERDE_TINTA)
        y += fl.size + 8


def folha_categoria(p, n, total):
    im = fundo()
    d = ImageDraw.Draw(im)
    cabecalho(im, n, total)
    ic = B + "/categorias/" + p["icone"]
    if os.path.exists(ic):
        lado = 520
        ico = cartao_icone(Image.open(ic), lado)
        im.paste(ico, ((W - ico.width) // 2, 270 + (lado - ico.height) // 2), ico)
    else:
        _avisos.append("icone em falta: " + p["icone"])
    _titulo_e_linha(im, d, p["nome"], p["linha"], 900)
    return im


def folha_passo(p, n, total):
    im = fundo()
    d = ImageDraw.Draw(im)
    cabecalho(im, n, total)
    r = 150
    cx, cy = W // 2, 430
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BRANCO)
    fn = fonte(180)
    t = p["num"]
    d.text((cx - d.textlength(t, font=fn) / 2, cy - fn.size * 0.62), t, font=fn, fill=VERDE)
    _titulo_e_linha(im, d, p["nome"], p["linha"], 700)
    return im


def folha_preco(p, n, total):
    im = fundo()
    d = ImageDraw.Draw(im)
    cabecalho(im, n, total)
    _titulo_e_linha(im, d, p["nome"], p["linha"], 470)
    return im


def folha_parceiro(p, n, total):
    cena = B + "/cenas/" + p.get("cena", "")
    if os.path.exists(cena):
        im = Image.open(cena).convert("RGB")
        r = max(W / float(im.width), H / float(im.height))
        im = im.resize((int(im.width * r) + 1, int(im.height * r) + 1), Image.LANCZOS)
        x0, y0 = (im.width - W) // 2, (im.height - H) // 2
        im = im.crop((x0, y0, x0 + W, y0 + H))
        veu = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        dv = ImageDraw.Draw(veu)
        for y in range(H):
            dv.line([(0, y), (W, y)], fill=(3, 40, 26, int(30 + 195 * (y / float(H)) ** 1.6)))
        im = Image.alpha_composite(im.convert("RGBA"), veu).convert("RGB")
    else:
        im = fundo()
        _avisos.append("cena em falta: " + p.get("cena", "?"))
    d = ImageDraw.Draw(im)
    cabecalho(im, n, total)
    lg = B + "/parceiros/" + p.get("logo", "")
    if os.path.exists(lg):
        l = Image.open(lg).convert("RGBA")
        lado = 190
        l.thumbnail((lado - 34, lado - 34), Image.LANCZOS)
        circ = Image.new("RGBA", (lado, lado), (0, 0, 0, 0))
        ImageDraw.Draw(circ).ellipse([0, 0, lado - 1, lado - 1], fill=(255, 255, 255, 245))
        circ.alpha_composite(l, ((lado - l.width) // 2, (lado - l.height) // 2))
        im.paste(circ, (W - MARGEM - lado, MARGEM), circ)
    _titulo_e_linha(im, d, p["nome"], p["linha"], 900)
    return im


def folha_chamada(s, n, total):
    im = fundo()
    d = ImageDraw.Draw(im)
    cabecalho(im, n, total)
    f, ls = ajustar(d, "Está tudo numa app só", W - 2 * MARGEM, 2, 96, 60)
    y = 420
    for l in ls:
        d.text((MARGEM, y), l, font=f, fill=BRANCO)
        y += f.size + 12
    d.text((MARGEM, y + 16), "Feita na Guarda, para a Guarda.", font=fonte(38, False),
           fill=VERDE_TINTA)
    # A UNICA chamada laranja do carrossel inteiro (design-kit.md, a regra do laranja).
    txt = "Código BEMVINDO no primeiro pedido"
    fsel = fonte(44)
    larg = d.textlength(txt, font=fsel)
    ys, alt = y + 150, 100
    d.rounded_rectangle([MARGEM, ys, MARGEM + larg + 64, ys + alt], radius=50, fill=LARANJA)
    d.text((MARGEM + 32, ys + (alt - fsel.size) // 2 - 4), txt, font=fsel, fill=BRANCO)
    rodape_link(d, H - MARGEM - 40)
    return im


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--serie", required=True)
    p.add_argument("--saida-dir", required=True)
    p.add_argument("--inicio", type=int, default=0, help="rotacao: por onde comecar")
    a = p.parse_args()

    cfg = json.load(open(B + "/series-carrossel.json", encoding="utf-8"))
    s = None
    for x in cfg["series"]:
        if x["id"] == a.serie:
            s = x
            break
    if s is None:
        print("serie desconhecida: %s (ha: %s)"
              % (a.serie, ", ".join(x["id"] for x in cfg["series"])))
        return 2

    todas = s["paginas"]
    # Regra das lojas permitidas (2026-10-27, missao redes-coming-soon): cada
    # pagina com "slug" (ou cujo texto fala de uma loja) passa pela base na hora
    # e pela lista fixa de exclusao. Base sem resposta = nao sai carrossel de loja.
    import lojas_permitidas as lp
    # B8 (2026-11-01, stories-em-breve): a pagina "beleza" (barbearia e
    # cabeleireiro) so entra se houver pelo menos uma barbearia/beleza
    # permitida; hoje estao todas em breve. Base sem resposta: fora.
    try:
        ha_beleza = any(v["permitida"] and v.get("categoria") in ("barbershop", "beauty")
                        for v in lp.lojas_vivas().values())
    except lp.SemResposta:
        ha_beleza = False
    filtradas = []
    for pg in todas:
        if (pg.get("nome") == "beleza" or pg.get("icone") == "cat_beleza.png") and not ha_beleza:
            print("LOJAS: fora do carrossel: pagina beleza (nenhuma barbearia/beleza aberta, todas em breve)")
            continue
        if pg.get("slug"):
            c, m = lp.verificar(pg["slug"])
        else:
            c, m = lp.verificar_texto(" ".join(v for v in pg.values() if isinstance(v, str)))
        if c == lp.OK:
            filtradas.append(pg)
        elif c == lp.SEM_RESPOSTA:
            print("LOJAS: %s" % m)
            return 4
        else:
            print("LOJAS: fora do carrossel: %s" % m)
    if not filtradas:
        print("LOJAS: nenhuma pagina da serie %s passou na regra" % s["id"])
        return 4
    todas = filtradas
    quantas = s.get("por_edicao", len(todas))
    quantas = min(quantas, len(todas), 8)
    escolhidas = [todas[(a.inicio + i) % len(todas)] for i in range(quantas)]
    total = len(escolhidas) + 2

    os.makedirs(a.saida_dir, exist_ok=True)
    desenho = {"categorias": folha_categoria, "passos": folha_passo,
               "precos": folha_preco, "parceiros": folha_parceiro}[s["modo"]]

    folhas = [folha_gancho(s, 1, total)]
    for i, pg in enumerate(escolhidas):
        folhas.append(desenho(pg, i + 2, total))
    folhas.append(folha_chamada(s, total, total))

    for i, im in enumerate(folhas):
        fp = os.path.join(a.saida_dir, "%02d.jpg" % (i + 1))
        im.save(fp, quality=92, optimize=True)
        print("%s %dx%d" % (fp, im.width, im.height))
    for w in dict.fromkeys(_avisos):
        print("AVISO: " + w)
    print("SERIE=%s" % s["id"])
    print("TITULO=%s" % s["titulo"])
    print("PERGUNTA=%s" % s.get("pergunta", ""))
    print("FOLHAS=%d" % len(folhas))
    return 0


if __name__ == "__main__":
    sys.exit(main())
