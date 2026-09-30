"""Explora a app web do Bora num telemóvel simulado e tira capturas.
Uso: python explorar.py <nome> <url> [clique_x,clique_y ...]
Cada clique é em coordenadas CSS do ecrã 390x844; entre cliques espera 3 s.
"""
import sys, time
from playwright.sync_api import sync_playwright

nome, url, *cliques = sys.argv[1:]
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=3,
                        is_mobile=True, has_touch=True, locale="pt-PT",
                        storage_state="estado.json" if __import__("os").path.exists("estado.json") else None)
    pg = ctx.new_page()
    pg.goto(url, wait_until="networkidle", timeout=90000)
    time.sleep(6)
    for i, c in enumerate(cliques):
        if c.startswith("scroll"):
            pg.mouse.wheel(0, int(c[6:]))
        elif c.startswith("type:"):
            pg.keyboard.type(c[5:])
        else:
            x, y = map(float, c.split(","))
            pg.mouse.click(x, y)
        time.sleep(3.5)
    pg.screenshot(path=f"{nome}.png")
    ctx.storage_state(path="estado.json")
    b.close()
print("ok", nome)
