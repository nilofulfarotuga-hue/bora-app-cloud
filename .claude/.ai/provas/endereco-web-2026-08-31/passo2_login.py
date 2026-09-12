"""Passo 2: maps BLOQUEADO, clicar Sou Cliente, screenshot do ecrã de login,
preencher credenciais da conta de prova e entrar."""
import os

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"
EMAIL = "prova.endereco@bora.app"
SENHA = "ProvaEndereco!2026"

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
    page.wait_for_timeout(12000)

    # Sou Cliente (botão verde, centro ~(215, 543) na captura do passo 1)
    page.mouse.click(215, 543)
    page.wait_for_timeout(4000)
    foto(page, "p2_ecra_login_cliente")

    # Campo email: clica no primeiro campo e escreve com teclado a sério.
    page.mouse.click(215, 300)
    page.wait_for_timeout(800)
    page.keyboard.type(EMAIL, delay=30)
    foto(page, "p2_email_escrito")

    # Tab para a senha (o Flutter respeita a ordem de foco).
    page.keyboard.press("Tab")
    page.wait_for_timeout(500)
    page.keyboard.type(SENHA, delay=30)
    foto(page, "p2_senha_escrita")

    page.keyboard.press("Enter")
    page.wait_for_timeout(9000)
    foto(page, "p2_apos_entrar")
    ctx.close()
print("OK passo 2")
