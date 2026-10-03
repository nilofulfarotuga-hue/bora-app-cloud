# -*- coding: utf-8 -*-
"""Diagnostico: consegue o executor 'hermes' sequer LANCAR Chrome + chegar a claude.ai?
Perfil TEMP vazio (sem cookies do danil) para isolar o muro de sessao/crypto do muro DPAPI-cruzado.
Se lancar -> screenshot do que aparece (login/Cloudflare). Se nao lancar -> confirma muro de sessao."""
import sys, time, tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright

SHOT = Path(r"C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\testes-e2e\screenshots-pc\teste-heartbeat-erro.png")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
tmp = tempfile.mkdtemp(prefix="hb_diag_")

def log(m): print(m, flush=True)

try:
    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=tmp, executable_path=CHROME, headless=True,
            args=["--no-first-run", "--no-default-browser-check"], timeout=30000,
        )
        log("LAUNCH OK: Chrome lancou com perfil temp headless")
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.goto("https://claude.ai/new", wait_until="domcontentloaded", timeout=45000)
        time.sleep(5)
        log(f"NAV OK: url={page.url}")
        title = page.title()
        log(f"TITLE: {title}")
        page.screenshot(path=str(SHOT), full_page=False)
        log(f"SHOT OK: {SHOT}")
        ctx.close()
except Exception as e:
    log(f"LAUNCH/NAV FAIL: {type(e).__name__}: {str(e)[:300]}")
    sys.exit(2)
