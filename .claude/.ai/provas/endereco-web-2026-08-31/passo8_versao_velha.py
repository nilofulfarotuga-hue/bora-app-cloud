"""Passo 8 — Prova 3: cliente numa versão velha. Simula-se servindo um
versao.json com commit DIFERENTE do carimbado no bundle: a página tem de
limpar service worker + caches e recarregar UMA única vez (anti-loop)."""
import json
import os

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"

loads = []

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel="chrome", headless=True,
        viewport={"width": 430, "height": 880}, locale="pt-PT",
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()

    def falso_versao(route):
        route.fulfill(
            status=200,
            content_type="application/json",
            body=json.dumps({"commit": "versao-nova-simulada-000",
                             "run": "999"}),
        )

    ctx.route("**/versao.json*", falso_versao)
    page.on("load", lambda _: loads.append(page.url))

    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(20000)   # tempo para: fetch versao → limpar → reload
    print("cargas da página:", len(loads))
    print("guarda anti-loop:",
          page.evaluate("sessionStorage.getItem('bora_reload_versao')"))
    sw = page.evaluate(
        "navigator.serviceWorker.getRegistrations().then(r => r.length)")
    print("service workers registados após limpeza:", sw)
    page.screenshot(path=os.path.join(PASTA, "p8_apos_reload_unico.png"))
    ctx.close()
print("OK passo 8")
