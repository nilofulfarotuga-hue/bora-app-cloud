"""Passo 6: pior cenário — maps.googleapis E places-proxy AMBOS bloqueados.
O campo tem de mostrar o aviso PT-PT + modo manual (nunca mudo), e a falha
tem de ficar registada em web_health_events (Bloco E)."""
import os

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, nome + ".png"))
    print("foto:", nome)


with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel="chrome", headless=True,
        viewport={"width": 430, "height": 880},
        geolocation={"latitude": 40.5373, "longitude": -7.2657},
        permissions=["geolocation"], locale="pt-PT",
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    ctx.route("**://maps.googleapis.com/**", lambda r: r.abort())
    ctx.route("**://maps.gstatic.com/**", lambda r: r.abort())
    ctx.route("**/functions/v1/places-proxy", lambda r: r.abort())
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(14000)
    page.mouse.click(268, 583)          # tile Bora Motorista
    page.wait_for_timeout(7000)
    page.mouse.click(215, 388)          # campo destino
    page.wait_for_timeout(1000)
    page.keyboard.type("rua batalha reis 7 guarda", delay=45)
    page.wait_for_timeout(6000)
    foto(page, "p6_aviso_indisponivel_e_modo_manual")

    # Tocar no "Usar esta morada" (fica por baixo do aviso, ~2ª linha).
    page.mouse.click(215, 500)
    page.wait_for_timeout(6000)
    foto(page, "p6_apos_usar_morada_manual")
    ctx.close()
print("OK passo 6")
