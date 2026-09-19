"""Passo 5c URGENTE: cancelar a corrida 2966ab4f (motorista real a caminho)
com o token da sessão guest que vive no perfil do browser — o caminho
canónico da app (tvde_cancel_ride, p_actor='cliente')."""
import json
import os
import re

from playwright.sync_api import sync_playwright

PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"
SB = "https://ojykpzwqrtusfeakzrna.supabase.co"
RIDE = "2966ab4f-ce44-4fca-b6fd-3476d2362842"

raiz = r"C:\BoraLocal\projetosflutter\bora_app"
anon = None
with open(os.path.join(raiz, ".dart_defines"), encoding="utf-8") as f:
    for linha in f:
        m = re.match(r"^SUPABASE_ANON_KEY=(.+)$", linha.strip())
        if m:
            anon = m.group(1)

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel="chrome", headless=True,
        viewport={"width": 430, "height": 880}, locale="pt-PT",
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(9000)

    # token supabase no localStorage (chave sb-<ref>-auth-token)
    tok = page.evaluate("""() => {
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.includes('auth-token')) {
          try { return JSON.parse(localStorage.getItem(k)).access_token || null; }
          catch (e) { return null; }
        }
      }
      return null;
    }""")
    print("token guest obtido:", bool(tok))

    if tok:
        h = {"apikey": anon, "Authorization": f"Bearer {tok}",
             "Content-Type": "application/json"}
        r = ctx.request.post(
            f"{SB}/rest/v1/rpc/tvde_cancel_ride",
            headers=h,
            data=json.dumps({"p_ride_id": RIDE, "p_actor": "cliente",
                             "p_reason": "teste tecnico endereco-web"}),
        )
        print("cancelamento:", r.status, r.text()[:400])
    ctx.close()
print("OK passo 5c")
