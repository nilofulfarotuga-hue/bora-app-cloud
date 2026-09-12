"""Passo 3: sessão persistida → home do cliente, fotografar para localizar a
categoria TVDE/Boleias. Maps continua bloqueado."""
import os

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
        PERFIL, channel="chrome", headless=True,
        viewport={"width": 430, "height": 880},
        geolocation={"latitude": 40.5373, "longitude": -7.2657},
        permissions=["geolocation"], locale="pt-PT",
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    ctx.route("**://maps.googleapis.com/**", lambda r: r.abort())
    ctx.route("**://maps.gstatic.com/**", lambda r: r.abort())
    page.add_init_script(ARRANQUE)
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(14000)
    print("boraMapsEstado:", page.evaluate("window.boraMapsEstado"))
    foto(page, "p3_home_cliente")
    page.mouse.wheel(0, 300)
    page.wait_for_timeout(1500)
    foto(page, "p3_home_scroll")
    ctx.close()
print("OK passo 3")
