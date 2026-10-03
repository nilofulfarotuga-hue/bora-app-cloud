"""Passo 5a: repetir o fluxo (maps bloqueado) e clicar "Solicitar corrida".
Fotografa o que aparece a seguir — sem confirmar mais nada às cegas."""
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
    page.mouse.click(268, 583)          # tile Bora Motorista
    page.wait_for_timeout(7000)
    page.mouse.click(215, 388)          # campo destino
    page.wait_for_timeout(1000)
    page.keyboard.type("rua dom miguel de alarcao", delay=45)
    page.wait_for_timeout(5000)
    page.mouse.click(215, 445)          # primeira sugestão
    page.wait_for_timeout(8000)
    page.mouse.click(215, 621)          # Solicitar corrida
    page.wait_for_timeout(3000)
    foto(page, "p5a_apos_solicitar_3s")
    page.wait_for_timeout(3000)
    foto(page, "p5a_apos_solicitar_6s")
    ctx.close()
print("OK passo 5a")
