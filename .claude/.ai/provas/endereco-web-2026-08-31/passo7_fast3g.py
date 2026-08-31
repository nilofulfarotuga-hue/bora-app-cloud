"""Passo 7 — Prova 2: rede Fast 3G simulada (CDP). O campo de morada tem de
aparecer e responder; se o SDK ainda não chegou, mostra "A procurar moradas…"
em vez de ecrã mudo."""
import os
import time

from playwright.sync_api import sync_playwright

PASTA = os.path.dirname(os.path.abspath(__file__))
PERFIL = r"C:\Users\danil\AppData\Local\Temp\bora-prova-perfil"
URL = "https://bora-app-web.pages.dev/"


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
    cdp = ctx.new_cdp_session(page)
    cdp.send("Network.enable")
    # Fast 3G do DevTools: 562.5 ms RTT, ~1.6 Mbps down, ~0.75 Mbps up.
    cdp.send("Network.emulateNetworkConditions", {
        "offline": False,
        "latency": 562.5,
        "downloadThroughput": int(1.6 * 1024 * 1024 / 8),
        "uploadThroughput": int(0.75 * 1024 * 1024 / 8),
    })

    t0 = time.time()
    page.goto(URL, wait_until="load", timeout=120000)
    print(f"load em {time.time()-t0:.1f}s (Fast 3G)")
    page.wait_for_timeout(20000)
    t_home = time.time() - t0
    foto(page, "p7_home_fast3g")
    print(f"home visivel aos {t_home:.1f}s")

    page.mouse.click(268, 583)          # tile Bora Motorista
    page.wait_for_timeout(9000)
    page.mouse.click(215, 388)          # campo destino
    page.wait_for_timeout(800)
    page.keyboard.type("rua dom miguel de alarcao", delay=60)
    t_digitou = time.time() - t0
    page.wait_for_timeout(1200)
    foto(page, "p7_logo_apos_digitar")
    page.wait_for_timeout(6000)
    foto(page, "p7_sugestoes_fast3g")
    print(f"digitado aos {t_digitou:.1f}s; estado maps:",
          page.evaluate("window.boraMapsEstado"))
    ctx.close()
print("OK passo 7")
