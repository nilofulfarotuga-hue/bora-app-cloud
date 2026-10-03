# -*- coding: utf-8 -*-
"""Prova do lado do CLIENTE (Bloco 4) na web local (build/web servida em :8765).

Uso: python prova_cliente.py <passo>
  arranque   -> abre a app, escolhe "Sou Cliente", fotografa
  login      -> entra com demo@bora.app e fotografa o acompanhamento da corrida em fila
  eta        -> tira N fotos com 6 s de intervalo (ETA vivo)

Chrome real (channel=chrome) num perfil proprio em %TEMP% — nunca os perfis do Danilo.
Consentimento gravado ANTES do arranque (PADRAO_BORA 3.10).
"""
import os, sys, time
from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = os.path.join(os.environ.get('TEMP', '.'), 'bora-prova-cliente-perfil')
URL = 'http://localhost:8765/'
EMAIL = 'demo@bora.app'
SENHA = 'BoraDemo2026!'
ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""


def foto(page, nome):
    p = os.path.join(PASTA, nome + '.png')
    page.screenshot(path=p)
    print('foto', nome, os.path.getsize(p))


def abrir(p, espera=15000):
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel='chrome', headless=False,
        viewport={'width': 430, 'height': 880},
        geolocation={'latitude': 40.5381819, 'longitude': -7.2653492},
        permissions=['geolocation'], locale='pt-PT', timezone_id='Europe/Lisbon',
        args=['--disable-dev-shm-usage', '--no-sandbox'])
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.add_init_script(ARRANQUE)
    page.goto(URL, wait_until='load', timeout=180000)
    page.wait_for_timeout(espera)
    return ctx, page


def escrever(page, x, y, texto):
    page.mouse.click(x, y)
    page.wait_for_timeout(700)
    page.keyboard.type(texto, delay=25)
    page.wait_for_timeout(400)


def main():
    passo = sys.argv[1] if len(sys.argv) > 1 else 'arranque'
    with sync_playwright() as p:
        ctx, page = abrir(p)
        foto(page, 'c00_arranque')
        if passo == 'arranque':
            # "Sou Cliente" — botao verde, a ~78% da altura no ecra dos papeis
            page.mouse.click(215, int(sys.argv[2]) if len(sys.argv) > 2 else 690)
            page.wait_for_timeout(8000)
            foto(page, 'c01_depois_papel')
        elif passo == 'login':
            ye, ys, yb = [int(v) for v in sys.argv[2:5]] if len(sys.argv) > 4 else (285, 348, 427)
            escrever(page, 215, ye, EMAIL)
            escrever(page, 215, ys, SENHA)
            foto(page, 'c02_preenchido')
            page.mouse.click(215, yb)
            page.wait_for_timeout(15000)
            foto(page, 'c03_depois_login')
            page.wait_for_timeout(10000)
            foto(page, 'c04_acompanhamento')
        elif passo == 'eta':
            n = int(sys.argv[2]) if len(sys.argv) > 2 else 3
            for i in range(n):
                foto(page, 'c1%d_eta' % i)
                page.wait_for_timeout(6000)
        elif passo == 'clicar':
            x, y = int(sys.argv[2]), int(sys.argv[3])
            page.mouse.click(x, y)
            page.wait_for_timeout(12000)
            foto(page, sys.argv[4] if len(sys.argv) > 4 else 'c20_clicou')
            if len(sys.argv) > 5:
                for i in range(int(sys.argv[5])):
                    page.wait_for_timeout(6000)
                    foto(page, '%s_%d' % (sys.argv[4], i + 1))
        elif passo == 'painel':
            # abre o ecra da corrida e puxa o painel para cima; depois N fotos
            page.mouse.click(267, 585)
            page.wait_for_timeout(12000)
            # puxar o painel com PointerEvents sintéticos no flutter-view (o
            # iframe do mapa engole os eventos reais do rato)
            page.evaluate('''() => {
              const el = document.querySelector('flutter-view') || document.body;
              const mk = (t, x, y, extra) => new PointerEvent(t, Object.assign({clientX:x, clientY:y, screenX:x, screenY:y,
                bubbles:true, cancelable:true, composed:true, pointerId:7, isPrimary:true, pointerType:'touch', width:1, height:1}, extra));
              el.dispatchEvent(mk('pointerdown', 120, 795, {button:0, buttons:1, pressure:0.5}));
              let y = 795; const step = () => { y -= 20; el.dispatchEvent(mk('pointermove', 120, y, {button:-1, buttons:1, pressure:0.5}));
                if (y > 200) setTimeout(step, 16); else el.dispatchEvent(mk('pointerup', 120, y, {button:0, buttons:0, pressure:0})); };
              setTimeout(step, 50);
            }''')
            page.wait_for_timeout(4000)
            nome = sys.argv[2] if len(sys.argv) > 2 else 'c07_painel'
            foto(page, nome)
            n = int(sys.argv[3]) if len(sys.argv) > 3 else 0
            for i in range(n):
                page.wait_for_timeout(int(sys.argv[4]) if len(sys.argv) > 4 else 8000)
                foto(page, '%s_%d' % (nome, i + 1))
        elif passo == 'foto':
            page.wait_for_timeout(8000)
            foto(page, sys.argv[2] if len(sys.argv) > 2 else 'c99')
        ctx.close()


if __name__ == '__main__':
    main()
