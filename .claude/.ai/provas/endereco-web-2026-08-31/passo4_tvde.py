"""Passo 4 — A PROVA CENTRAL: maps.googleapis BLOQUEADO, ecrã TVDE,
escrever destino à mão e ver as sugestões chegarem pelo places-proxy.
Regista também as chamadas à Edge Function para prova material."""
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

    proxy_calls = []
    page.on(
        "response",
        lambda res: proxy_calls.append((res.status, res.url))
        if "places-proxy" in res.url else None,
    )

    page.add_init_script(ARRANQUE)
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(14000)

    # Tile "Bora Motorista" (TVDE) — centro ~(268, 583) na home.
    page.mouse.click(268, 583)
    page.wait_for_timeout(7000)
    foto(page, "p4_ecra_tvde")

    # Campo destino "Para onde vais?" fica na metade de baixo; fotografa
    # primeiro, clica depois (coordenadas afinadas à captura anterior se
    # falhar). Tentativa: campo destino ~(215, 700)?? — ver foto p4_ecra_tvde.
    ctx.close()
print("chamadas places-proxy:", proxy_calls)
print("OK passo 4a (reconhecimento)")
