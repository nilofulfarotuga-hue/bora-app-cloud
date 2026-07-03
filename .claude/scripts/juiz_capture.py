#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
JUIZ — CAPTURA AUTOMÁTICA DE ECRÃ (Fase 5, "olhos de verdade")
==============================================================

O loop de auto-cura maestro↔Juiz dá NOTA 0-10 com um teto de 8 sem olhos
(`tem_visual=false`). Até agora `tem_visual=true` era marcado À MÃO — o Juiz não
abria nada sozinho. Este script dá ao Juiz uma forma REAL de tirar o print, sem
depender de ninguém marcar a flag.

HONESTIDADE ACIMA DE TUDO: se a captura não for possível (sem emulador/dispositivo,
Playwright não instalado, site bloqueia bot), devolvemos `ok:false` + `motivo_falha`.
NUNCA um sucesso falso. O teto de 8 do design continua a valer — isso é correto.

Três modos, cada um devolve um PNG real validado (assinatura + IHDR com dims > 0):

  • mobile     — apps cliente/estafeta/parceiro (Flutter em emulador/dispositivo
                 Android). `adb exec-out screencap -p`. Assume o ecrã já aberto (o
                 maestro acabou de o construir/hot-reload) — não há deep link
                 universal (só `tel:` no manifest; rotas nomeadas só admin in-app).
  • web        — admin panel (Flutter web). Playwright/Chromium navega, espera o
                 conteúdo carregar (não fotografa ecrã em branco/loading) e captura.
  • referencia — best-effort: tira print de uma URL dos MELHORES (benchmark). Se
                 detetar captcha/bloqueio → NÃO contorna: `ok:false,
                 motivo_falha:"bloqueado_por_bot_detection"`. O Juiz cai no
                 fallback de texto (checklist_features/notas_ux) que já existe.

Saída: SEMPRE um JSON numa linha em stdout, para o Juiz ler programaticamente:
  {"ok": true|false, "path": "...", "motivo_falha": "...", "mode": "...",
   "dims": [w, h], "via": "mobile|web"}
Exit: 0 = capturou (ok:true) · 1 = falhou de forma honesta (ok:false).

Uso:
  python .claude/scripts/juiz_capture.py --mode mobile --out volta_N_propria.png
  python .claude/scripts/juiz_capture.py --mode web    --url <url> --out volta_N_propria.png
  python .claude/scripts/juiz_capture.py --mode referencia --url <url-melhor> --out ref_N.png
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import time

APP_ID = "pt.boraapp.bora"  # applicationId Android (build.gradle.kts)

# Sinais de bloqueio anti-bot (modo referencia — NÃO contornar, cair no fallback).
BOT_BLOCK_MARKERS = (
    "captcha",
    "unusual traffic",
    "are you a robot",
    "verify you are human",
    "verify you're human",
    "checking your browser",
    "cf-challenge",
    "access denied",
    "attention required",
    "px-captcha",
)


# ---------------------------------------------------------------------------
# Resultado + validação de PNG (o coração da honestidade)
# ---------------------------------------------------------------------------
def _result(ok, path=None, motivo=None, mode=None, dims=None, via=None):
    """Imprime o veredito em JSON (uma linha) e devolve o exit code."""
    payload = {
        "ok": bool(ok),
        "path": path,
        "motivo_falha": motivo,
        "mode": mode,
        "dims": list(dims) if dims else None,
        "via": via,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0 if ok else 1


def _png_dims(path):
    """Devolve (w, h) se for um PNG válido não-vazio, senão None.

    Valida assinatura PNG + lê o chunk IHDR (largura/altura big-endian). É isto
    que impede um sucesso falso: um ficheiro de 0 bytes ou lixo não passa.
    """
    try:
        if not os.path.isfile(path) or os.path.getsize(path) < 24:
            return None
        with open(path, "rb") as f:
            head = f.read(24)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            return None
        if head[12:16] != b"IHDR":
            return None
        w, h = struct.unpack(">II", head[16:24])
        if w <= 0 or h <= 0:
            return None
        return (w, h)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# MODO MOBILE — adb screencap
# ---------------------------------------------------------------------------
def _find_adb(explicit=None):
    """Localiza o adb: --adb → PATH → Android SDK em %LOCALAPPDATA%."""
    if explicit and os.path.isfile(explicit):
        return explicit
    found = shutil.which("adb")
    if found:
        return found
    local = os.environ.get("LOCALAPPDATA", "")
    candidate = os.path.join(local, "Android", "Sdk", "platform-tools", "adb.exe")
    if os.path.isfile(candidate):
        return candidate
    home = os.path.expanduser("~")
    for base in (
        os.path.join(home, "AppData", "Local", "Android", "Sdk"),
        os.path.join(home, "Android", "Sdk"),
    ):
        c = os.path.join(base, "platform-tools", "adb.exe")
        if os.path.isfile(c):
            return c
    return None


def _online_device(adb, serial=None):
    """Devolve o serial de um dispositivo em estado 'device', ou None."""
    try:
        out = subprocess.run(
            [adb, "devices"], capture_output=True, text=True, timeout=15
        ).stdout
    except Exception:
        return None
    devices = []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    if serial:
        return serial if serial in devices else None
    return devices[0] if devices else None


def capture_mobile(out, serial=None, adb_path=None, route=None):
    adb = _find_adb(adb_path)
    if not adb:
        return _result(
            False, mode="mobile", via="mobile",
            motivo="adb_nao_encontrado (nem PATH nem Android SDK)",
        )
    dev = _online_device(adb, serial)
    if not dev:
        return _result(
            False, mode="mobile", via="mobile",
            motivo="sem_dispositivo_android (nenhum emulador/telemóvel ligado)",
        )

    # NÃO há deep link universal (só tel: no manifest). Se o maestro passar uma
    # rota nomeada de admin, tenta abrir por intent VIEW — best-effort; se falhar,
    # segue e captura o que já está no ecrã (o maestro acabou de o abrir).
    if route:
        try:
            subprocess.run(
                [adb, "-s", dev, "shell", "am", "start", "-a",
                 "android.intent.action.VIEW", "-d", route, APP_ID],
                capture_output=True, text=True, timeout=15,
            )
            time.sleep(2.5)  # deixa o ecrã assentar
        except Exception:
            pass  # limitação conhecida — capturamos o ecrã atual à mesma

    try:
        proc = subprocess.run(
            [adb, "-s", dev, "exec-out", "screencap", "-p"],
            capture_output=True, timeout=30,
        )
    except Exception as e:
        return _result(False, mode="mobile", via="mobile",
                       motivo=f"screencap_falhou: {e}")
    if proc.returncode != 0 or not proc.stdout:
        err = (proc.stderr or b"").decode("utf-8", "replace")[:200]
        return _result(False, mode="mobile", via="mobile",
                       motivo=f"screencap_sem_saida (rc={proc.returncode}) {err}")

    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    with open(out, "wb") as f:
        f.write(proc.stdout)

    dims = _png_dims(out)
    if not dims:
        return _result(False, path=out, mode="mobile", via="mobile",
                       motivo="png_invalido (screencap devolveu bytes não-PNG)")
    return _result(True, path=os.path.abspath(out), mode="mobile", via="mobile",
                   dims=dims)


# ---------------------------------------------------------------------------
# MODO WEB / REFERENCIA — Playwright
# ---------------------------------------------------------------------------
def _capture_with_playwright(url, out, detect_bot):
    """Núcleo Playwright partilhado por web e referencia.

    Devolve (ok, motivo, dims). detect_bot=True → deteta captcha/bloqueio.
    """
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        return (False, "playwright_nao_instalado (pip install playwright && "
                       "playwright install chromium)", None)

    try:
        with sync_playwright() as p:
            try:
                browser = p.chromium.launch(headless=True)
            except Exception as e:
                return (False, f"chromium_nao_instalado: {e} "
                               "(corre: playwright install chromium)", None)
            page = browser.new_page(viewport={"width": 1440, "height": 900})
            status = None
            try:
                resp = page.goto(url, wait_until="load", timeout=45000)
                status = resp.status if resp else None
            except Exception as e:
                browser.close()
                return (False, f"navegacao_falhou: {e}", None)

            # Deixa o conteúdo assentar (Flutter web pinta num canvas; SPAs
            # hidratam após load). networkidle é best-effort.
            try:
                page.wait_for_load_state("networkidle", timeout=15000)
            except Exception:
                pass
            page.wait_for_timeout(3500)

            if detect_bot:
                blocked = status in (403, 429, 503)
                if not blocked:
                    try:
                        body = (page.content() or "").lower()
                        title = (page.title() or "").lower()
                        hay = title + " " + body[:20000]
                        blocked = any(m in hay for m in BOT_BLOCK_MARKERS)
                    except Exception:
                        pass
                if blocked:
                    browser.close()
                    return (False, "bloqueado_por_bot_detection", None)

            os.makedirs(os.path.dirname(os.path.abspath(out)) or ".",
                        exist_ok=True)
            try:
                page.screenshot(path=out, full_page=True)
            except Exception:
                # full_page pode falhar em canvas gigante → viewport
                page.screenshot(path=out, full_page=False)
            browser.close()
    except Exception as e:
        return (False, f"playwright_erro: {e}", None)

    dims = _png_dims(out)
    if not dims:
        return (False, "png_invalido (screenshot vazio/corrompido)", None)
    return (True, None, dims)


def capture_web(url, out):
    if not url:
        return _result(False, mode="web", via="web", motivo="falta_--url")
    ok, motivo, dims = _capture_with_playwright(url, out, detect_bot=False)
    return _result(ok, path=os.path.abspath(out) if ok else out,
                   motivo=motivo, mode="web", via="web", dims=dims)


def capture_referencia(url, out):
    if not url:
        return _result(False, mode="referencia", via="web", motivo="falta_--url")
    ok, motivo, dims = _capture_with_playwright(url, out, detect_bot=True)
    return _result(ok, path=os.path.abspath(out) if ok else out,
                   motivo=motivo, mode="referencia", via="web", dims=dims)


# ---------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Captura automática de ecrã para o Juiz (olhos de verdade)."
    )
    ap.add_argument("--mode", required=True,
                    choices=["mobile", "web", "referencia"])
    ap.add_argument("--out", required=True, help="Caminho do PNG de saída.")
    ap.add_argument("--url", help="URL (obrigatório para web/referencia).")
    ap.add_argument("--route", help="Deep link/rota (mobile, best-effort).")
    ap.add_argument("--serial", help="Serial adb específico (mobile).")
    ap.add_argument("--adb", help="Caminho explícito do adb.exe (mobile).")
    args = ap.parse_args(argv)

    if args.mode == "mobile":
        return capture_mobile(args.out, serial=args.serial, adb_path=args.adb,
                              route=args.route)
    if args.mode == "web":
        return capture_web(args.url, args.out)
    return capture_referencia(args.url, args.out)


if __name__ == "__main__":
    sys.exit(main())
