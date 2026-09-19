# -*- coding: utf-8 -*-
"""
Peca 2 do heartbeat-DESKTOP (substitui o browser-operador que bateu no Cloudflare Turnstile).

Em vez de conduzir o Chrome por Playwright/CDP (detetado como automacao -> Turnstile), este
operador trata o Claude como o "app fixo na barra de tarefas" que o Danilo ja tem aberto e
logado: uma PWA/Chrome App (chrome_proxy --app-id=... --profile-directory="Profile 3").
Trabalha por INPUT DE SISTEMA OPERATIVO (foco de janela + clique + colar + Enter) e por
SCREENSHOTS (tira print em cada passo antes de decidir) -- nao ha flags de automacao, logo
nao dispara o Turnstile.

Passos:
  1. Traz a janela do "app Claude" para primeiro plano. Se nao estiver aberta, ABRE o app
     (janela --app=claude.ai/new no Profile 3 = a MESMA coisa que clicar no icone da barra;
     nunca abre um separador de browser normal, nunca faz login -- a sessao ja esta no perfil).
  2. Clica na area do chat (composer).
  3. Escreve a frase fixa (lida do pending.trigger) -- colada via clipboard (aguenta acentos).
  4. Envia (Enter).
Prova: screenshot final em .claude/testes-e2e/screenshots-pc/teste-heartbeat-desktop.png

Saida (stdout): linhas 'STEP <n> OK/FAIL: <detalhe>'.
Exit: 0 ok | 3 sem trigger | 4 app nao abriu/janela nao encontrada | 5 composer nao encontrado
      | 7 excecao.

IMPORTANTE: tem de correr NA SESSAO INTERATIVA do Danilo (Session 1). O executor headless
(Hermes, Session 0) NAO alcanca o desktop visivel -- por isso o gatilho corre via schtask
/RU danil /IT (ver instalar-schtask-desktop.cmd).
"""
import ctypes
import json
import os
import sys
import time
from pathlib import Path

REPO = Path(r"C:\Users\danil\Desktop\projetosflutter\bora_app")
# Deps de automacao instaladas localmente (pip --target) -> import independente da sessao/user.
_LIBS = Path(__file__).resolve().parent / "_libs"
if _LIBS.is_dir():
    sys.path.insert(0, str(_LIBS))
# O detetor (Peca 1, inalterado) escreve o trigger na pasta heartbeat-browser.
HB_BROWSER = REPO / ".claude" / ".ai" / "hermes" / "heartbeat-browser"
HB_DESKTOP = REPO / ".claude" / ".ai" / "hermes" / "heartbeat-desktop"
TRIGGER = HB_BROWSER / "pending.trigger"
CONSUMIDOS = HB_DESKTOP / "consumidos"
SHOTS = REPO / ".claude" / "testes-e2e" / "screenshots-pc"
SHOT = SHOTS / "teste-heartbeat-desktop.png"            # prova final (nome exigido)
SHOT_WIN = SHOTS / "teste-heartbeat-desktop-1-janela.png"
SHOT_ANTES = SHOTS / "teste-heartbeat-desktop-2-antes.png"
SHOT_ERR = SHOTS / "teste-heartbeat-desktop-erro.png"

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
PROFILE = os.environ.get("HB_CLAUDE_PROFILE", "Profile 3")  # perfil logado do Danilo
APP_URL = "https://claude.ai/new"


def log(msg):
    print(msg, flush=True)


def _dpi_aware():
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)  # per-monitor v2
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


def _foreground(hwnd):
    """Traz a janela mesmo quando outra tem o foco (ALT trick + SetForegroundWindow)."""
    u = ctypes.windll.user32
    SW_RESTORE = 9
    u.ShowWindow(hwnd, SW_RESTORE)
    # Simula tecla ALT para desbloquear SetForegroundWindow (regra do Windows).
    u.keybd_event(0x12, 0, 0, 0)      # ALT down
    u.keybd_event(0x12, 0, 0x0002, 0)  # ALT up
    u.SetForegroundWindow(hwnd)
    u.BringWindowToTop(hwnd)


def _find_claude_windows(gw):
    wins = []
    for w in gw.getAllWindows():
        t = (w.title or "").lower()
        if not t:
            continue
        if "claude" in t or "claude.ai" in t:
            wins.append(w)
    return wins


def main():
    _dpi_aware()
    SHOTS.mkdir(parents=True, exist_ok=True)

    if not TRIGGER.exists():
        log("STEP 0 FAIL: pending.trigger nao existe (gatilho nao disparado)")
        return 3
    try:
        frase = json.loads(TRIGGER.read_text(encoding="utf-8"))["frase"]
    except Exception as e:
        log(f"STEP 0 FAIL: trigger ilegivel ({e})")
        return 3
    log(f"STEP 0 OK: trigger lido, frase {len(frase)} chars")

    try:
        import pyautogui
        import pygetwindow as gw
        import pyperclip
    except Exception as e:
        log(f"STEP 0 FAIL: dependencias em falta ({e}). Corre _setup-deps.cmd primeiro.")
        return 7
    pyautogui.FAILSAFE = False

    try:
        # --- PASSO 1: trazer / abrir o app Claude ---
        wins = _find_claude_windows(gw)
        if wins:
            log(f"STEP 1 OK: app Claude ja aberto ({len(wins)} janela(s)) -> trazer p/ frente")
        else:
            log("STEP 1: app nao esta aberto -> abrir a PWA (janela --app, nunca browser)")
            os.spawnv(os.P_NOWAIT, CHROME, [
                CHROME, f"--profile-directory={PROFILE}", f"--app={APP_URL}",
                "--new-window",
            ])
            for _ in range(20):
                time.sleep(1)
                wins = _find_claude_windows(gw)
                if wins:
                    break
            if not wins:
                pyautogui.screenshot(str(SHOT_ERR))
                log("STEP 1 FAIL: app nao abriu / janela 'Claude' nao encontrada (icone/app indisponivel)")
                return 4

        win = wins[0]
        try:
            _foreground(win._hWnd)
        except Exception:
            try:
                win.activate()
            except Exception:
                pass
        time.sleep(2.5)
        pyautogui.screenshot(str(SHOT_WIN))
        try:
            L, T, W, H = win.left, win.top, win.width, win.height
        except Exception:
            L, T, W, H = 0, 0, pyautogui.size().width, pyautogui.size().height
        log(f"STEP 1 OK: janela em frente rect=({L},{T},{W}x{H}) -> {SHOT_WIN.name}")

        if W < 300 or H < 300:
            pyautogui.screenshot(str(SHOT_ERR))
            log(f"STEP 1 FAIL: janela demasiado pequena/oculta ({W}x{H})")
            return 4

        # --- PASSO 2: clicar na area do chat (composer fica no fundo-centro) ---
        cx = L + W // 2
        cy = T + H - 90
        pyautogui.click(cx, cy)
        time.sleep(0.4)
        pyautogui.click(cx, cy)  # 2o clique garante foco no contenteditable
        time.sleep(0.6)
        log(f"STEP 2 OK: clicado no composer em ({cx},{cy})")

        # --- PASSO 3: escrever a frase fixa (colar via clipboard aguenta acentos) ---
        pyperclip.copy(frase)
        time.sleep(0.3)
        pyautogui.hotkey("ctrl", "v")
        time.sleep(1.2)
        pyautogui.screenshot(str(SHOT_ANTES))
        log(f"STEP 3 OK: frase colada no composer -> {SHOT_ANTES.name}")

        # --- PASSO 4: enviar ---
        pyautogui.press("enter")
        log("STEP 4: Enter pressionado, a aguardar...")
        time.sleep(4)
        pyautogui.screenshot(str(SHOT))
        log(f"STEP 5 OK: mensagem enviada (prova) -> {SHOT.name}")

        # consome o trigger (anti-spam camada 2)
        CONSUMIDOS.mkdir(parents=True, exist_ok=True)
        iso = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        dest = CONSUMIDOS / f"consumido-{iso}.trigger"
        dest.write_text(TRIGGER.read_text(encoding="utf-8"), encoding="utf-8")
        TRIGGER.unlink()
        log(f"STEP 6 OK: trigger consumido -> {dest.name}")
        return 0

    except Exception as e:
        try:
            import pyautogui
            pyautogui.screenshot(str(SHOT_ERR))
        except Exception:
            pass
        log(f"STEP X FAIL: excecao {type(e).__name__}: {e}")
        return 7


if __name__ == "__main__":
    sys.exit(main())
