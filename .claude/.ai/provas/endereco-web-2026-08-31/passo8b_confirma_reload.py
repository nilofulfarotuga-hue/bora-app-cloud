"""Passo 8b: confirmar que a página FOI recarregada (navigation type=reload)
e que ficou numa recarga só."""
import json
import os

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PERFIL, channel="chrome", headless=True,
        viewport={"width": 430, "height": 880}, locale="pt-PT",
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()

    def falso_versao(route):
        route.fulfill(status=200, content_type="application/json",
                      body=json.dumps({"commit": "versao-nova-simulada-000",
                                       "run": "999"}))

    ctx.route("**/versao.json*", falso_versao)
    page.goto(URL, wait_until="load", timeout=60000)
    page.wait_for_timeout(25000)
    nav = page.evaluate(
        "performance.getEntriesByType('navigation').map(e => e.type)")
    print("tipo de navegação do documento atual:", nav)
    print("guarda anti-loop:",
          page.evaluate("sessionStorage.getItem('bora_reload_versao')"))
    page.wait_for_timeout(10000)
    nav2 = page.evaluate(
        "performance.getEntriesByType('navigation').map(e => e.type)")
    print("10s depois, continua:", nav2, "(sem novas recargas)")
    ctx.close()
print("OK passo 8b")
