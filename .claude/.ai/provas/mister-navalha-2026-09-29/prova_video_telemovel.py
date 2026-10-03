"""Prova do video de fundo do site misternavalha.boraguarda.com em telemovel,
com "reduzir movimento" LIGADO e DESLIGADO (prefers-reduced-motion).

Motores: WebKit (o motor do Safari do iPhone) com o perfil iPhone 15, e Chromium
com iPhone 15 e Pixel 7. Para cada caso mede duas vezes o currentTime do video
#bgv: se avancou, o video esta mesmo a correr (nao basta o elemento existir).

Uso: python -X utf8 prova_video_telemovel.py
"""
import json
import pathlib
import time

from playwright.sync_api import sync_playwright

URL = "https://misternavalha.boraguarda.com/"
AQUI = pathlib.Path(__file__).resolve().parent
OUT = AQUI / "telemovel"
OUT.mkdir(exist_ok=True)

MEDIR = """() => {
  const v = document.getElementById('bgv');
  const e = v.error;
  return {
    reduz: matchMedia('(prefers-reduced-motion: reduce)').matches,
    src: (v.currentSrc || v.src || '').split('/').pop(),
    paused: v.paused, readyState: v.readyState, t: +v.currentTime.toFixed(2),
    erro: e ? e.code : null, largura: innerWidth, altura: innerHeight,
    scrollW: document.documentElement.scrollWidth,
    fontes: document.fonts.check('62px Norican')
  };
}"""

casos = []
with sync_playwright() as p:
    for motor, aparelho in (("webkit", "iPhone 15"), ("chromium", "iPhone 15"), ("chromium", "Pixel 7")):
        nav = getattr(p, motor).launch()
        for reduz in ("reduce", "no-preference"):
            ctx = nav.new_context(**p.devices[aparelho], reduced_motion=reduz)
            pg = ctx.new_page()
            pg.goto(URL, wait_until="load", timeout=90000)
            pg.wait_for_timeout(2500)
            a = pg.evaluate(MEDIR)
            pg.wait_for_timeout(2500)
            b = pg.evaluate(MEDIR)
            nome = f"{motor}-{aparelho.replace(' ', '')}-{'reduzir-LIGADO' if reduz == 'reduce' else 'reduzir-DESLIGADO'}"
            pg.screenshot(path=str(OUT / f"{nome}.png"))
            corre = (not b["paused"]) and b["t"] > a["t"] and b["erro"] is None
            caso = {"caso": nome, "reduzir_movimento_css": b["reduz"], "video": b["src"],
                    "t1": a["t"], "t2": b["t"], "paused": b["paused"], "readyState": b["readyState"],
                    "erro_media": b["erro"], "viewport": f'{b["largura"]}x{b["altura"]}',
                    "scrollWidth": b["scrollW"], "fonte_norican": b["fontes"], "VIDEO_CORRE": corre}
            casos.append(caso)
            print(json.dumps(caso, ensure_ascii=False))
            ctx.close()
        nav.close()

(OUT / "resultado.json").write_text(json.dumps(casos, ensure_ascii=False, indent=2), encoding="utf-8")
print("\nresumo:", sum(c["VIDEO_CORRE"] for c in casos), "de", len(casos), "casos com o video a correr")
