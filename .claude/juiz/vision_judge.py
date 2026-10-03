#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""F-OLHO · Camada 2 — JUIZ DE VISÃO (varredura 2026-08-17).

Olha as fotos geradas pela Camada 1 (test/golden/_fotos) ou pelos runs do
Firebase Test Lab (Camada 3) e classifica cada uma:
  verde    — tela ok
  amarelo  — abaixo do padrão (texto colado, contraste fraco, vazio feio)
  vermelho — quebrado (botão cortado/pela metade, tela estourada, ilegível)

Achados vão para a tabela `vision_findings` (RLS só-admin) e um resumo local
fica SEMPRE em .claude/juiz/_capturas/vision_report_<ts>.json — o juiz nunca
falha em silêncio (lição parser-mudo).

Uso:
  python .claude/juiz/vision_judge.py                      # fotos golden
  python .claude/juiz/vision_judge.py --dir X --source robo # artefactos Robo

Chaves (por ordem): env GEMINI_API_KEY → scripts/scraper/.env → backend/.env.
Sem chave Gemini: sai 0 com aviso claro (não inventa vereditos).
Escrita na BD: SERVICE_ROLE_KEY/SUPABASE_SERVICE_ROLE_KEY de backend/.env.
Sem service key: só o JSON local (avisa).

Alerta admin: cada 🔴 dispara a Edge Fn `notify-admin-urgent` (modo generic).
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
# gemini-flash-lite-latest: modelo lite (rápido + cap free-tier DIÁRIO maior),
# suficiente para classificar telas verde/amarelo/vermelho. O 'gemini-3.6-flash'
# fixo e mesmo o 'gemini-flash-latest' esgotavam o cap ao correr os 13 goldens
# várias vezes no mesmo dia (429). A lite aguentou a corrida inteira 2026-08-17.
# Override por env GEMINI_MODEL (ex.: um flash "cheio" para análise mais fina).
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")

PROMPT = (
    "És o juiz de visão do Bora App (delivery/TVDE na Guarda, Portugal). "
    "Olha para esta captura de ecrã da app e responde SÓ com JSON: "
    '{"severity":"verde|amarelo|vermelho","finding":"<1 frase PT-PT>"}. '
    "vermelho = botão cortado/pela metade, texto por cima de texto, tela "
    "estourada, conteúdo ilegível ou vazio quebrado. amarelo = feio mas "
    "usável: texto colado às margens, contraste fraco, estado vazio pobre, "
    "alinhamentos tortos. verde = tela normal. Ignora a barra de estado e "
    "dados de exemplo. Sê conservador: na dúvida, verde."
)


def _le_env(caminho: str) -> dict:
    out = {}
    try:
        with open(caminho, "r", encoding="utf-8", errors="replace") as f:
            for linha in f:
                m = re.match(r"^([A-Z0-9_]+)=(.*)$", linha.strip())
                if m:
                    out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def _chaves() -> tuple[str | None, str | None]:
    gem = os.environ.get("GEMINI_API_KEY")
    svc = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SERVICE_ROLE_KEY")
    for env_file in (os.path.join(RAIZ, "scripts", "scraper", ".env"),
                     os.path.join(RAIZ, "backend", ".env")):
        vals = _le_env(env_file)
        gem = gem or vals.get("GEMINI_API_KEY")
        svc = svc or vals.get("SUPABASE_SERVICE_ROLE_KEY") or vals.get("SERVICE_ROLE_KEY")
    return gem, svc


def _post_json(url: str, payload: dict, headers: dict, timeout: int = 60) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", **headers}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        corpo = resp.read().decode("utf-8", errors="replace")
    return json.loads(corpo) if corpo.strip() else {}


def _post_json_retry(url, payload, headers, tentativas=5):
    """Post com backoff em 429 E erros transitórios (5xx, timeout de leitura).
    O gemini-flash-latest às vezes devolve 503/timeout sob carga — retentar
    para não marcar a tela como falso-amarelo por um soluço de infra."""
    ultimo = None
    for i in range(tentativas):
        try:
            return _post_json(url, payload, headers, timeout=120)
        except urllib.error.HTTPError as e:  # type: ignore[attr-defined]
            ultimo = e
            if e.code in (429, 500, 502, 503, 504) and i < tentativas - 1:
                time.sleep(5 * (i + 1))
                continue
            raise
        except (urllib.error.URLError, TimeoutError) as e:  # timeout/rede
            ultimo = e
            if i < tentativas - 1:
                time.sleep(5 * (i + 1))
                continue
            raise
    if ultimo:
        raise ultimo
    return {}


def julga_foto(gem_key: str, png_path: str) -> dict:
    with open(png_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    url = (f"https://generativelanguage.googleapis.com/v1beta/models/"
           f"{GEMINI_MODEL}:generateContent?key={gem_key}")
    payload = {
        "contents": [{"parts": [
            {"text": PROMPT},
            {"inline_data": {"mime_type": "image/png", "data": b64}},
        ]}],
        # maxOutputTokens alto: o gemini-3.6-flash "pensa" antes de responder e
        # com pouco teto devolvia texto vazio. (thinkingConfig dá 400 no 3.6.)
        "generationConfig": {"temperature": 0.1, "maxOutputTokens": 2000},
    }
    data = _post_json_retry(url, payload, {})
    texto = ""
    try:
        texto = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError, TypeError):
        pass
    # O gemini-3.6-flash envolve o JSON em ```json ... ``` e às vezes com
    # texto antes; apanha o objeto JSON mesmo assim (o {...} mais interno).
    m = re.search(r"\{[^{}]*\"severity\"[^{}]*\}", texto, re.S) \
        or re.search(r"\{.*\}", texto, re.S)
    if not m:
        return {"severity": "amarelo", "finding": f"juiz sem veredito legível: {texto[:120]}"}
    try:
        v = json.loads(m.group(0))
        sev = v.get("severity", "amarelo")
        if sev not in ("verde", "amarelo", "vermelho"):
            sev = "amarelo"
        return {"severity": sev, "finding": str(v.get("finding", ""))[:400]}
    except json.JSONDecodeError:
        return {"severity": "amarelo", "finding": f"JSON inválido do juiz: {texto[:120]}"}


def grava_bd(svc_key: str, rows: list[dict]) -> bool:
    try:
        _post_json(
            f"{SUPABASE_URL}/rest/v1/vision_findings",
            rows,  # type: ignore[arg-type]
            {"apikey": svc_key, "Authorization": f"Bearer {svc_key}",
             "Prefer": "return=minimal"},
        )
        return True
    except Exception as e:  # noqa: BLE001 — reportar, nunca esconder
        print(f"[vision_judge] ERRO a gravar na BD: {e}")
        return False


def alerta_admin(svc_key: str, titulo: str, corpo: str) -> None:
    try:
        _post_json(
            f"{SUPABASE_URL}/functions/v1/notify-admin-urgent",
            {"mode": "generic", "title": titulo, "body": corpo},
            {"apikey": svc_key, "Authorization": f"Bearer {svc_key}"},
        )
    except Exception as e:  # noqa: BLE001
        print(f"[vision_judge] alerta admin falhou (não-fatal): {e}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(RAIZ, "test", "golden", "_fotos"))
    ap.add_argument("--source", default="golden", choices=["golden", "robo"])
    ap.add_argument("--run-ref", default=None)
    args = ap.parse_args()

    # Sem --run-ref explícito, carimba a versão do harness que gerou as fotos
    # (test/golden/_fotos/_harness_version.txt) — distingue corridas antes/depois
    # de um fix de fidelidade, tanto local como no CI.
    if not args.run_ref:
        _vf = os.path.join(RAIZ, "test", "golden", "_fotos", "_harness_version.txt")
        try:
            with open(_vf, "r", encoding="utf-8") as _f:
                args.run_ref = _f.read().strip() or None
        except OSError:
            pass

    pngs = sorted(
        os.path.join(args.dir, f) for f in os.listdir(args.dir)
        if f.lower().endswith(".png")) if os.path.isdir(args.dir) else []
    if not pngs:
        print(f"[vision_judge] SEM FOTOS em {args.dir} — corre primeiro "
              f"`flutter test test/golden` (golden) ou aponta --dir (robo).")
        return 0

    gem, svc = _chaves()
    ts = time.strftime("%Y%m%dT%H%M%S")
    relatorio = {"ts": ts, "source": args.source, "dir": args.dir, "findings": []}

    if not gem:
        print("[vision_judge] SEM GEMINI_API_KEY (env, scripts/scraper/.env ou "
              "backend/.env). O juiz NÃO corre sem olhos — adiciona a chave "
              "(https://aistudio.google.com/apikey) e volta a correr. "
              f"{len(pngs)} fotos ficam por julgar.")
        relatorio["skipped"] = "sem GEMINI_API_KEY"
    else:
        rows = []
        for n_i, png in enumerate(pngs):
            if n_i > 0:
                time.sleep(8)  # gemini-3.6-flash free tier ~10-15 RPM
            nome = os.path.splitext(os.path.basename(png))[0]
            try:
                v = julga_foto(gem, png)
            except Exception as e:  # noqa: BLE001
                v = {"severity": "amarelo", "finding": f"erro do juiz: {e}"}
            v["screen_name"] = nome
            relatorio["findings"].append(v)
            print(f"[vision_judge] {v['severity'].upper():8s} {nome}: {v['finding']}")
            rows.append({
                "source": args.source, "screen_name": nome,
                "severity": v["severity"], "finding": v["finding"],
                "screenshot_path": os.path.relpath(png, RAIZ).replace("\\", "/"),
                "run_ref": args.run_ref,
            })
        vermelhos = [r for r in rows if r["severity"] == "vermelho"]
        if svc:
            if grava_bd(svc, rows):
                print(f"[vision_judge] {len(rows)} achados gravados em vision_findings.")
            if vermelhos:
                alerta_admin(
                    svc, "🔴 Juiz de visão: tela quebrada",
                    "; ".join(f"{r['screen_name']}: {r['finding']}" for r in vermelhos[:5]))
        else:
            print("[vision_judge] SEM service key — achados só no JSON local.")

    destino = os.path.join(RAIZ, ".claude", "juiz", "_capturas",
                           f"vision_report_{ts}.json")
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, "w", encoding="utf-8") as f:
        json.dump(relatorio, f, ensure_ascii=False, indent=2)
    print(f"[vision_judge] relatório local: {os.path.relpath(destino, RAIZ)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
