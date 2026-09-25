"""Passo 4b: no ecrã TVDE com maps BLOQUEADO, escrever o destino e provar
que as sugestões chegam pelo places-proxy; escolher uma e ver a estimativa."""
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
        lambda res: proxy_calls.append((res.status, res.request.post_data))
        if "places-proxy" in res.url else None,
    )

    page.add_init_script(ARRANQUE)
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(14000)
    page.mouse.click(268, 583)          # tile Bora Motorista
    page.wait_for_timeout(7000)

    page.mouse.click(215, 388)          # campo "Para onde vais?"
    page.wait_for_timeout(1000)
    page.keyboard.type("rua dom miguel de alarcao", delay=45)
    page.wait_for_timeout(5000)
    foto(page, "p4b_sugestoes_com_maps_bloqueado")

    # Primeira sugestão do overlay (logo abaixo do campo).
    page.mouse.click(215, 445)
    page.wait_for_timeout(8000)
    foto(page, "p4b_destino_escolhido_estimativa")

    print("chamadas places-proxy:")
    for status, body in proxy_calls:
        print("  ", status, (body or "")[:90])
    ctx.close()
print("OK passo 4b")
