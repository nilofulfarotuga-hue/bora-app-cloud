"""Grava em vídeo NÍTIDO a navegação real na app web do Bora (telemóvel simulado, 3x).
Usa o screencast do Chrome (CDP) à resolução do ecrã -> 1170x2532.
Uso: python gravar.py <nome> <url> [passo ...]
Passos: "x,y" = toque; "rN" = scroll suave N px; "wS" = esperar S s; "s" = captura de controlo.
Saída: <nome>.mp4 (só a parte depois de a página estar pronta) + <nome>-passoK.png.
"""
import sys, time, os, base64, subprocess, shutil
from playwright.sync_api import sync_playwright

nome, url, *passos = sys.argv[1:]
tmp = f"_frames_{nome}"
shutil.rmtree(tmp, ignore_errors=True); os.makedirs(tmp)
frames = []  # (t, ficheiro)
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=3,
                        is_mobile=True, has_touch=True, locale="pt-PT", storage_state="estado.json")
    pg = ctx.new_page()
    pg.goto(url, wait_until="networkidle", timeout=90000)
    time.sleep(5)
    k = 0
    for s in passos:
        if s.startswith("r"):
            n = int(s[1:])
            for _ in range(max(1, abs(n) // 12)):
                pg.mouse.wheel(0, 12 if n > 0 else -12)
                time.sleep(0.025)
            time.sleep(0.5)
        elif s.startswith("w"):
            time.sleep(float(s[1:]))
        elif s.startswith("t:"):
            pg.keyboard.type(s[2:], delay=90); time.sleep(2)
        elif s == "s":
            k += 1
            pg.screenshot(path=f"{nome}-passo{k}.png")
        else:
            x, y = map(float, s.split(","))
            pg.touchscreen.tap(x, y)
            time.sleep(1.6)
    time.sleep(1.2)
    b.close()
print("ok", nome)

