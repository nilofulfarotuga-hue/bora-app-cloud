"""Prova endereco-web — passo 1: abrir a app publicada COM maps.googleapis
BLOQUEADO (como um browser com bloqueador de privacidade) e fotografar até à
home do cliente. Perfil persistente reutiliza o login da prova de 29/08."""
import os
import sys

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"

ARRANQUE = """
localStorage.setItem('flutter.bora_app.consent_answered', 'true');
localStorage.setItem('flutter.bora_app.consent_version', '"1.0"');
localStorage.setItem('flutter.bora_app.consent_location', 'true');
localStorage.setItem('flutter.bora_app.consent_notifications', 'true');
localStorage.setItem('flutter.bora_app.consent_analytics', 'true');
"""


def foto(page, nome):
    page.screenshot(path=os.path.join(PASTA, nome + ".png"))
    print("foto:", nome)


with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PERFIL,
        channel="chrome",
        headless=True,
        viewport={"width": 430, "height": 880},
        geolocation={"latitude": 40.5373, "longitude": -7.2657},
        permissions=["geolocation"],
        locale="pt-PT",
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()

    bloqueados = {"n": 0}

    def bloquear(route):
        bloqueados["n"] += 1
        route.abort()

    ctx.route("**://maps.googleapis.com/**", bloquear)
    ctx.route("**://maps.gstatic.com/**", bloquear)

    page.add_init_script(ARRANQUE)
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(12000)
    print("url:", page.url)
    print("boraMapsEstado:", page.evaluate("window.boraMapsEstado"))
    print("boraMapsMotivo:", page.evaluate("window.boraMapsMotivo"))
    print("pedidos a maps bloqueados:", bloqueados["n"])
    foto(page, "p1_arranque_maps_bloqueado")
    page.wait_for_timeout(4000)
    foto(page, "p1_apos_16s")
    ctx.close()
print("OK passo 1")
