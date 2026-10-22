"""Prova do commit 1702a55e no site no ar: o ecrã de aprovações pede só
estafetas não encerrados (`deleted_at=is.null` no pedido a /rest/v1/drivers).
Entra com a conta demo de estafeta (senha da conta demo pela variável
BORA_DEMO_SENHA, nunca escrita aqui) e regista o URL do pedido.
Uso: python -I prova_filtro_eliminados.py <pasta_saida>
"""
import os
import pathlib
import sys

from playwright.sync_api import sync_playwright

saida = pathlib.Path(sys.argv[1])
pedidos = []
with sync_playwright() as p:
    b = p.chromium.launch(headless=True)
    page = b.new_page(viewport={"width": 480, "height": 960}, locale="pt-PT", service_workers="block")
    page.on("request", lambda r: "/rest/v1/drivers?" in r.url and pedidos.append(r.url))
    page.goto("https://app.boraguarda.com/", wait_until="load", timeout=120000)
    page.wait_for_timeout(9000)
    page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
    page.wait_for_timeout(1200)
    for nome in ("Rejeitar",):
        try:
            page.get_by_role("button", name=nome).first.click(timeout=5000)
        except Exception:  # noqa: BLE001
            pass
    page.get_by_role("button", name="Sou Estafeta").first.click(timeout=15000)
    page.wait_for_timeout(3500)
    page.evaluate("() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); }")
    for rot, val in (("Email", "demo-estafeta@bora.app"), ("Palavra-passe", os.environ["BORA_DEMO_SENHA"])):
        c = page.get_by_label(rot).first
        c.click(timeout=15000)
        page.wait_for_timeout(1200)
        page.keyboard.type(val, delay=40)
    page.get_by_role("button", name="Entrar").first.click(timeout=15000)
    page.wait_for_timeout(12000)
    pedidos.clear()
    page.goto("https://app.boraguarda.com/#/admin/drivers/approval", wait_until="load", timeout=120000)
    page.wait_for_timeout(12000)
    page.screenshot(path=str(saida / "80-filtro-eliminados.png"))
    b.close()
com = [u for u in pedidos if "deleted_at=is.null" in u]
print("pedidos a drivers:", len(pedidos), "| com deleted_at=is.null:", len(com))
for u in pedidos[:3]:
    print(" ", u.split("/rest/v1/")[1][:160])
