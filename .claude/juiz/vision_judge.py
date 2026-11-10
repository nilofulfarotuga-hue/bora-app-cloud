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

Olhos (10/11/2026, missão fechar-tudo bloco H): o Gemini do projeto Google bora-juiz saiu (conta de
pagamento vencida, HTTP 402; sem pagamento novo no Google). Agora .claude/juiz/ia_visao.py: Claude
primeiro (claude-haiku-5-5; direto só com CLAUDE_ROBOS_API_KEY, senão pelo porteiro do Motor Bora na
VPS) → rotação grátis de visão do Motor Bora → erro claro. Sem nenhum motor configurado: sai 0 com
aviso claro (não inventa vereditos).
Escrita na BD: SERVICE_ROLE_KEY/SUPABASE_SERVICE_ROLE_KEY de backend/.env.
Sem service key: só o JSON local (avisa).

Alerta admin: cada 🔴 dispara a Edge Fn `notify-admin-urgent` (modo generic).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_visao  # noqa: E402 — Claude primeiro, rotação grátis, erro claro

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUPABASE_URL = "https://ojykpzwqrtusfeakzrna.supabase.co"
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


def _chave_servico() -> str | None:
    svc = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or os.environ.get("SERVICE_ROLE_KEY")
    for env_file in (os.path.join(RAIZ, "scripts", "scraper", ".env"),
                     os.path.join(RAIZ, "backend", ".env")):
        vals = _le_env(env_file)
        svc = svc or vals.get("SUPABASE_SERVICE_ROLE_KEY") or vals.get("SERVICE_ROLE_KEY")
    return svc


def _post_json(url: str, payload: dict, headers: dict, timeout: int = 60) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", **headers}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        corpo = resp.read().decode("utf-8", errors="replace")
    return json.loads(corpo) if corpo.strip() else {}


def julga_foto(png_path: str, svc_key: str | None = None) -> dict:
    with open(png_path, "rb") as f:
        dados = f.read()

    def livro(linha: dict) -> None:  # só quando o Claude é chamado direto (o porteiro regista sozinho)
        if svc_key:
            _post_json(f"{SUPABASE_URL}/rest/v1/ia_gastos", linha,
                       {"apikey": svc_key, "Authorization": f"Bearer {svc_key}", "Prefer": "return=minimal"})

    r = ia_visao.pedir(PROMPT, "Captura de ecrã em anexo. Responde só com o JSON.",
                       [("image/png", dados)], robo="juiz-visao", livro=livro)
    if not r["ok"]:
        return {"severity": "amarelo", "finding": f"juiz sem olhos: {r['erro'][:300]}", "motor": None}
    texto = r["texto"]
    # O modelo pode envolver o JSON em ```json ... ``` ou pôr texto antes;
    # apanha o objeto JSON mesmo assim (o {...} mais interno).
    m = re.search(r"\{[^{}]*\"severity\"[^{}]*\}", texto, re.S) \
        or re.search(r"\{.*\}", texto, re.S)
    motor = f"{r['motor']}:{r['modelo']}"
    if not m:
        return {"severity": "amarelo", "finding": f"juiz sem veredito legível: {texto[:120]}", "motor": motor}
    try:
        v = json.loads(m.group(0))
        sev = v.get("severity", "amarelo")
        if sev not in ("verde", "amarelo", "vermelho"):
            sev = "amarelo"
        return {"severity": sev, "finding": str(v.get("finding", ""))[:400], "motor": motor}
    except json.JSONDecodeError:
        return {"severity": "amarelo", "finding": f"JSON inválido do juiz: {texto[:120]}", "motor": motor}


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

    svc = _chave_servico()
    ts = time.strftime("%Y%m%dT%H%M%S")
    relatorio = {"ts": ts, "source": args.source, "dir": args.dir, "findings": []}

    motores = ia_visao.motores_configurados()
    if not motores:
        print("[vision_judge] SEM OLHOS: nem CLAUDE_ROBOS_API_KEY nem a senha do porteiro do Motor Bora "
              f"({ia_visao.FICHEIRO_SENHA_PADRAO}). O juiz NÃO corre sem olhos e não inventa "
              f"vereditos. {len(pngs)} fotos ficam por julgar.")
        relatorio["skipped"] = "sem motor de visão (nem Claude direto nem porteiro)"
    else:
        rows = []
        for n_i, png in enumerate(pngs):
            if n_i > 0:
                time.sleep(2)  # a reserva grátis tem limites por minuto
            nome = os.path.splitext(os.path.basename(png))[0]
            try:
                v = julga_foto(png, svc)
            except Exception as e:  # noqa: BLE001
                v = {"severity": "amarelo", "finding": f"erro do juiz: {e}", "motor": None}
            v["screen_name"] = nome
            relatorio["findings"].append(v)
            print(f"[vision_judge] {v['severity'].upper():8s} {nome}: {v['finding']} [{v.get('motor') or 'sem motor'}]")
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
