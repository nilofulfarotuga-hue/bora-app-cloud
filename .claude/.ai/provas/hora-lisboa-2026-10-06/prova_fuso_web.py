"""Prova pela web pública com o NAVEGADOR NOUTRO FUSO (missão hora-lisboa-2026-10-06).

Cópia de ronda-05-10/prova_ecras_web.py. O fuso do navegador vem de FUSO
(por omissão Asia/Tokyo). Abre app.boraguarda.com num browser do tamanho de um
telemóvel, liga a camada de acessibilidade do Flutter, entra com o cliente de
demonstração (a conta do autoteste do CI) e lê os rótulos "Aberto"/"Fechada"
das lojas. NÃO cria pedido.

  FUSO=Asia/Tokyo python prova_fuso_web.py <raiz-do-repo> <passo> [ordens...]
"""
import json
import os
import re
import sys

from playwright.sync_api import sync_playwright

RAIZ = sys.argv[1] if len(sys.argv) > 1 else "."
PASSO = sys.argv[2] if len(sys.argv) > 2 else "descobrir"
AQUI = os.path.dirname(os.path.abspath(__file__))
URL = "https://app.boraguarda.com/"
FUSO = os.environ.get("FUSO", "Asia/Tokyo")

teste = open(os.path.join(RAIZ, "integration_test", "demo_real_test.dart"), encoding="utf-8").read()
EMAIL = re.search(r"'DEMO_EMAIL', defaultValue: '([^']+)'", teste).group(1)
SENHA = re.search(r"'DEMO_PASSWORD', defaultValue: '([^']+)'", teste).group(1)

ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""

ROTULOS = """() => [...document.querySelectorAll('flt-semantics')].map(e => {
  const r = e.getAttribute('role') || '';
  const t = (e.getAttribute('aria-label') || (e.children.length === 0 ? e.textContent : '') || '').trim();
  return t ? (r ? r + ': ' : '') + t.replace(/\\s+/g, ' ').slice(0, 110) : null;
}).filter(Boolean)"""


def foto(page, nome):
    page.screenshot(path=os.path.join(AQUI, nome + ".png"))
    print("   foto:", nome + ".png")


def ligar_acessibilidade(page):
    page.evaluate("() => { const b = document.querySelector('flt-semantics-placeholder'); if (b) b.click(); }")
    page.wait_for_timeout(1500)


def rotulos(page, limite=60):
    ligar_acessibilidade(page)
    vistos, saida = set(), []
    for r in page.evaluate(ROTULOS):
        if r not in vistos:
            vistos.add(r)
            saida.append(r)
    return saida[:limite]


def mostrar(page, titulo, limite=60):
    print(f"--- {titulo} ---")
    for r in rotulos(page, limite):
        print("   ", r)


def tocar(page, texto, exacto=False, espera=4000):
    ligar_acessibilidade(page)
    alvo = page.get_by_text(texto, exact=exacto).first
    try:
        alvo.scroll_into_view_if_needed(timeout=4000)
    except Exception:
        pass
    alvo.click(timeout=8000)
    page.wait_for_timeout(espera)
    print("   toquei:", texto)


def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(
            viewport={"width": 430, "height": 900},
            geolocation={"latitude": 40.5373, "longitude": -7.2676},
            permissions=["geolocation"], locale="pt-PT", timezone_id=FUSO)
        page = ctx.new_page()
        page.add_init_script(ARRANQUE)
        erros = []
        page.on("pageerror", lambda e: erros.append(str(e)[:200]))
        page.goto(URL, wait_until="load")
        print("fuso do navegador:",
              page.evaluate("() => Intl.DateTimeFormat().resolvedOptions().timeZone"),
              "| relogio do navegador:", page.evaluate("() => new Date().toString()"))
        page.wait_for_timeout(20000)
        mostrar(page, "arranque")
        foto(page, f"web-{FUSO.replace('/', '_')}-01-arranque")
        if PASSO == "descobrir":
            print("erros de página:", json.dumps(erros, ensure_ascii=False))
            browser.close()
            return
        # Guião: t:<texto> toca (contém) · tx:<texto> exacto · b:<nome> botão
        #   e:<n>:<texto> escreve na n-ésima caixa (EMAIL/SENHA trocados)
        #   w:<ms> espera · v:<título> mostra rótulos · f:<nome> fotografa · r:<px> rola
        for ordem in sys.argv[3:]:
            tipo, _, resto = ordem.partition(":")
            try:
                if tipo == "t":
                    tocar(page, resto)
                elif tipo == "tx":
                    tocar(page, resto, exacto=True)
                elif tipo == "b":
                    ligar_acessibilidade(page)
                    page.get_by_role("button", name=resto).first.click(timeout=8000)
                    page.wait_for_timeout(4000)
                    print("   botão:", resto)
                elif tipo == "e":
                    n, _, texto = resto.partition(":")
                    texto = texto.replace("EMAIL", EMAIL).replace("SENHA", SENHA)
                    ligar_acessibilidade(page)
                    page.get_by_role("textbox").nth(int(n)).click(timeout=8000)
                    page.wait_for_timeout(600)
                    page.keyboard.type(texto, delay=25)
                    page.wait_for_timeout(600)
                    print("   escrevi na caixa", n)
                elif tipo == "w":
                    page.wait_for_timeout(int(resto))
                elif tipo == "v":
                    mostrar(page, resto, 120)
                elif tipo == "f":
                    foto(page, f"web-{FUSO.replace('/', '_')}-{resto}")
                elif tipo == "r":
                    page.mouse.move(215, 600)
                    page.mouse.wheel(0, int(resto))
                    page.wait_for_timeout(1500)
            except Exception as e:
                if tipo in ("b", "t", "tx") and "Timeout" in str(e):
                    print(f"   (toque sem confirmação em {resto!r}; segue-se)")
                    page.wait_for_timeout(3000)
                    continue
                print(f"   FALHOU {ordem!r}: {str(e)[:160]}")
                mostrar(page, "estado no momento da falha", 90)
                foto(page, "web-falha")
                break
        print("erros de página:", json.dumps(erros, ensure_ascii=False))
        browser.close()


main()
