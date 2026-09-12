# -*- coding: utf-8 -*-
"""
Teste PONTA-A-PONTA do heartbeat-browser (browser-operador ao vivo).
Conduz o Chrome REAL do Danilo (perfil Default = sessao claude.ai Pro), abre um
CHAT NOVO em claude.ai/new, cola a frase fixa do pending.trigger, ENVIA, e prova
com screenshot. Nunca faz login: se nao houver sessao ativa -> aborta com prova.

Saida (stdout): linhas 'STEP <n> OK/FAIL: <detalhe>'. Screenshot final/erro em
.claude/testes-e2e/screenshots-pc/teste-heartbeat.png
"""
import json
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

BASE = Path(__file__).resolve().parents[3]  # .../bora_app/.claude -> parents: hermes, .ai, .claude
# BASE deve ser a pasta .claude
REPO = Path(r"C:\Users\danil\Desktop\projetosflutter\bora_app")
HB_DIR = REPO / ".claude" / ".ai" / "hermes" / "heartbeat-browser"
TRIGGER = HB_DIR / "pending.trigger"
CONSUMIDOS = HB_DIR / "consumidos"
SHOT = REPO / ".claude" / "testes-e2e" / "screenshots-pc" / "teste-heartbeat.png"
SHOT_ERR = REPO / ".claude" / "testes-e2e" / "screenshots-pc" / "teste-heartbeat-erro.png"
# O executor corre como o utilizador 'hermes'. A sessao claude.ai Pro vive no perfil
# do Danilo (utilizador 'danil'). Permite override por env para testar esse perfil.
USER_DATA = Path(os.environ.get("HB_USER_DATA",
                                str(Path(os.environ["LOCALAPPDATA"]) / "Google" / "Chrome" / "User Data")))
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


def log(msg):
    print(msg, flush=True)


def main():
    if not TRIGGER.exists():
        log("STEP 0 FAIL: pending.trigger nao existe (gatilho nao disparado)")
        return 3
    frase = json.loads(TRIGGER.read_text(encoding="utf-8"))["frase"]
    log(f"STEP 0 OK: trigger lido, frase {len(frase)} chars")

    with sync_playwright() as p:
        ctx = p.chromium.launch_persistent_context(
            user_data_dir=str(USER_DATA),
            executable_path=CHROME,
            headless=False,
            args=["--profile-directory=Default", "--no-first-run", "--no-default-browser-check"],
            viewport={"width": 1280, "height": 900},
            timeout=45000,
        )
        try:
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            log("STEP 1 OK: Chrome real (perfil Default) aberto")

            page.goto("https://claude.ai/new", wait_until="domcontentloaded", timeout=60000)
            time.sleep(4)
            url = page.url
            log(f"STEP 2 nav: url={url}")

            # Deteta login: se redirecionou para /login ou aparece botao de login -> sem sessao
            if "/login" in url or "login" in url:
                page.screenshot(path=str(SHOT_ERR))
                log("STEP 2 FAIL: sem sessao ativa (redir login). Abortado, nao inventa login.")
                return 4

            # Procura o composer (ProseMirror / contenteditable)
            composer = None
            for sel in ['div.ProseMirror[contenteditable="true"]', '[contenteditable="true"]',
                        'div[contenteditable="true"]']:
                try:
                    page.wait_for_selector(sel, timeout=8000, state="visible")
                    composer = page.query_selector(sel)
                    if composer:
                        log(f"STEP 3 OK: composer encontrado ({sel})")
                        break
                except PWTimeout:
                    continue

            if not composer:
                page.screenshot(path=str(SHOT_ERR))
                log("STEP 3 FAIL: composer nao encontrado (login? UI mudou?)")
                return 5

            composer.click()
            time.sleep(0.5)
            # Escreve a frase (type para simular teclado real do ProseMirror)
            page.keyboard.type(frase, delay=4)
            time.sleep(1)
            log("STEP 4 OK: frase escrita no composer")

            # Screenshot ANTES de enviar (prova da frase escrita)
            page.screenshot(path=str(REPO / ".claude" / "testes-e2e" / "screenshots-pc" / "teste-heartbeat-antes.png"))

            # Enviar: Enter
            page.keyboard.press("Enter")
            log("STEP 5: Enter pressionado, a aguardar mensagem no thread...")

            # Prova de envio: a URL muda para /chat/<uuid> E/OU aparece a mensagem do user no thread
            sent = False
            for _ in range(30):
                time.sleep(1)
                if "/chat/" in page.url:
                    sent = True
                    break
                # fallback: procura o texto no DOM
                if page.query_selector(f'text="{frase[:40]}"'):
                    sent = True
                    break

            time.sleep(3)
            page.screenshot(path=str(SHOT))
            if sent:
                log(f"STEP 6 OK: mensagem ENVIADA. url={page.url}")
                # Consome o trigger
                CONSUMIDOS.mkdir(exist_ok=True)
                iso = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
                dest = CONSUMIDOS / f"consumido-{iso}.trigger"
                dest.write_text(TRIGGER.read_text(encoding="utf-8"), encoding="utf-8")
                TRIGGER.unlink()
                log(f"STEP 7 OK: trigger consumido -> {dest.name}")
                return 0
            else:
                log(f"STEP 6 FAIL: nao confirmou envio (url ainda {page.url}). Screenshot guardado.")
                return 6
        except Exception as e:
            try:
                ctx.pages[0].screenshot(path=str(SHOT_ERR))
            except Exception:
                pass
            log(f"STEP X FAIL: excecao {type(e).__name__}: {e}")
            return 7
        finally:
            time.sleep(2)
            ctx.close()


if __name__ == "__main__":
    sys.exit(main())
