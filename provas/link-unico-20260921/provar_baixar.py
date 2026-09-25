# -*- coding: utf-8 -*-
"""Prova da pagina /baixar nos tres aparelhos (iPhone, Android, computador).

Abre a pagina com o Playwright a fingir cada aparelho (agente + ecra reais dos
descritores do Playwright), tira a captura e le da propria pagina o que ficou
VISIVEL: que botao de loja se ve, para onde aponta, se o QR aparece, e o que
diz a linha do site. A prova e' o que a pagina mostra, nao o que o HTML diz.

Uso:  python provar_baixar.py <url> <pasta-de-saida> [etiqueta]
Sai com 1 se alguma regra falhar. A ultima linha e' sempre VEREDITO.
"""
import json
import os
import sys

from playwright.sync_api import sync_playwright

URL = sys.argv[1]
SAIDA = sys.argv[2]
ETQ = sys.argv[3] if len(sys.argv) > 3 else "prova"
os.makedirs(SAIDA, exist_ok=True)

APPSTORE = "https://apps.apple.com/pt/app/bora-entregas-e-servicos/id6809954739"
PLAY = "https://play.google.com/store/apps/details?id=pt.boraapp.bora"

LER = """
() => {
  const vis = el => !!el && el.getClientRects().length > 0 &&
                    getComputedStyle(el).display !== 'none';
  const app = document.getElementById('btn-appstore');
  const play = document.getElementById('btn-play');
  const web = document.getElementById('btn-web');
  const qr = document.querySelector('.qr');
  const lojas = document.querySelector('.lojas');
  return {
    aparelho: document.documentElement.getAttribute('data-aparelho'),
    appstore_visivel: vis(app), appstore_href: app && app.href,
    play_visivel: vis(play), play_href: play && play.href,
    web_visivel: vis(web), web_href: web && web.href,
    web_e_botao: web ? getComputedStyle(web).display.indexOf('flex') >= 0 : null,
    web_fonte_px: web ? parseFloat(getComputedStyle(web).fontSize) : null,
    site_linha: document.querySelector('.site') && document.querySelector('.site').innerText.trim(),
    qr_visivel: vis(qr), qr_src: qr && qr.querySelector('img') && qr.querySelector('img').src,
    lojas_direccao: lojas && getComputedStyle(lojas).flexDirection,
    bemvindo: /BEMVINDO/.test(document.body.innerText),
    tokens_5eur: /1000 tokens, que valem 5/.test(document.body.innerText),
    largura: innerWidth, altura: innerHeight,
  };
}
"""

res = {}
falhas = []


def ok(cond, msg):
    print(("  OK  " if cond else "  FALHA ") + msg)
    if not cond:
        falhas.append(msg)


with sync_playwright() as p:
    casos = [
        ("iphone", p.webkit, p.devices["iPhone 14"]),
        ("android", p.chromium, p.devices["Pixel 7"]),
        ("computador", p.chromium, {"viewport": {"width": 1280, "height": 900}}),
    ]
    for nome, motor, opts in casos:
        b = motor.launch()
        ctx = b.new_context(**opts)
        pg = ctx.new_page()
        pg.goto(URL, wait_until="networkidle")
        pg.wait_for_timeout(600)
        d = pg.evaluate(LER)
        cap = os.path.join(SAIDA, "%s-%s.png" % (ETQ, nome))
        pg.screenshot(path=cap, full_page=True)
        d["captura"] = cap
        res[nome] = d
        b.close()
        print("== %s (%sx%s, aparelho=%s)" % (nome, d["largura"], d["altura"], d["aparelho"]))
        if nome == "iphone":
            ok(d["aparelho"] == "ios", "detectou iOS")
            ok(d["appstore_visivel"] and d["appstore_href"] == APPSTORE, "botao da App Store visivel com o link real")
            ok(not d["play_visivel"], "botao da Play escondido")
            ok(not d["qr_visivel"], "QR escondido no telemovel")
        elif nome == "android":
            ok(d["aparelho"] == "android", "detectou Android")
            ok(d["play_visivel"] and d["play_href"].startswith(PLAY), "botao da Play visivel com referrer")
            ok(not d["appstore_visivel"], "botao da App Store escondido")
            ok(not d["qr_visivel"], "QR escondido no telemovel")
        else:
            ok(d["aparelho"] == "pc", "detectou computador")
            ok(d["appstore_visivel"] and d["play_visivel"], "as duas lojas visiveis")
            ok(d["lojas_direccao"] == "row", "as duas lojas lado a lado")
            ok(d["qr_visivel"] and d["qr_src"].endswith("qr-baixar.png"), "QR unico grande visivel")
        ok(d["web_visivel"] and not d["web_e_botao"] and d["web_fonte_px"] <= 15,
           "pedir pelo site e' linha pequena (%.0fpx), nao botao" % (d["web_fonte_px"] or 0))
        ok(d["web_href"].startswith("https://app.boraguarda.com"), "linha do site aponta ao site")
        ok(d["bemvindo"] and d["tokens_5eur"], "BEMVINDO 1000 tokens = 5 euros na pagina")

with open(os.path.join(SAIDA, "%s-resultado.json" % ETQ), "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=1)
print("VEREDITO: %s (%d falhas) -> %s" % ("APROVADO" if not falhas else "REPROVADO", len(falhas), SAIDA))
sys.exit(1 if falhas else 0)
