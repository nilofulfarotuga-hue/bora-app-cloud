"""Passo 5b: fluxo completo com maps BLOQUEADO — confirmar a corrida (dinheiro),
fotografar, e CANCELAR de imediato pela RPC da própria app (tvde_cancel_ride)
para não prender os motoristas reais. Prova material: id + status da corrida."""
import os
import re

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"
SB = "https://ojykpzwqrtusfeakzrna.supabase.co"
EMAIL = "prova.endereco@bora.app"
SENHA = "ProvaEndereco!2026"

raiz = r"C:\BoraLocal\projetosflutter\bora_app"
anon = None
with open(os.path.join(raiz, ".dart_defines"), encoding="utf-8") as f:
    for linha in f:
        m = re.match(r"^SUPABASE_ANON_KEY=(.+)$", linha.strip())
        if m:
            anon = m.group(1)
assert anon, "anon key nao encontrada"

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
    page.mouse.click(268, 583)
    page.wait_for_timeout(7000)
    page.mouse.click(215, 388)
    page.wait_for_timeout(1000)
    page.keyboard.type("rua dom miguel de alarcao", delay=45)
    page.wait_for_timeout(5000)
    page.mouse.click(215, 445)
    page.wait_for_timeout(8000)
    page.mouse.click(215, 621)          # Solicitar corrida
    page.wait_for_timeout(4000)
    page.mouse.click(215, 841)          # Confirmar · pagar em dinheiro
    page.wait_for_timeout(6000)
    foto(page, "p5b_corrida_pedida")

    # ── cancelar já, pela porta da própria app ──────────────────────────────
    req = ctx.request
    login = req.post(
        f"{SB}/auth/v1/token?grant_type=password",
        headers={"apikey": anon, "Content-Type": "application/json"},
        data={"email": EMAIL, "password": SENHA},
    )
    tok = login.json().get("access_token")
    print("login para cancelar:", login.status, "token:", bool(tok))
    h = {"apikey": anon, "Authorization": f"Bearer {tok}"}

    rides = req.get(
        f"{SB}/rest/v1/tvde_rides?select=id,status,created_at"
        f"&order=created_at.desc&limit=1",
        headers=h,
    )
    print("corrida criada:", rides.status, rides.text()[:300])
    lista = rides.json()
    if lista:
        ride_id = lista[0]["id"]
        cancel = req.post(
            f"{SB}/rest/v1/rpc/tvde_cancel_ride",
            headers={**h, "Content-Type": "application/json"},
            data={"p_ride_id": ride_id, "p_reason": "teste tecnico endereco-web"},
        )
        print("cancelamento:", cancel.status, cancel.text()[:300])
        depois = req.get(
            f"{SB}/rest/v1/tvde_rides?select=id,status&id=eq.{ride_id}",
            headers=h,
        )
        print("status final:", depois.status, depois.text()[:200])

    page.wait_for_timeout(4000)
    foto(page, "p5b_apos_cancelar")
    ctx.close()
print("OK passo 5b")
