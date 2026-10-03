# -*- coding: utf-8 -*-
"""
JUIZ — PROVA DE PROCESSO EM SEGUNDO PLANO / TESTE NO TELEMÓVEL (chão determinístico)
====================================================================================

Motivo (falha real 2026-07-11): o Juiz aprovou PELO MENOS 2 ordens que alegavam ter
arrancado um teste E2E em segundo plano — mas era FALSO (zero pedidos novos em 18h,
telemóvel confirmado parado). O Juiz aceitou a PALAVRA do executor. Regra a partir de
agora, MECÂNICA e não-negociável, análoga ao anti_trapaca.py:

  Qualquer tarefa que ALEGUE ter (a) arrancado um processo em segundo plano ou
  (b) iniciado/corrido um teste no telemóvel SÓ pode ser ACEITE se existir PELO MENOS
  UMA prova concreta e verificável, das quatro:

    (a) PID  — um processo real que CONTINUA VIVO agora (--pid N).
    (b) ADB  — pelo menos um comando adb REAL com resposta registada em log (--adb-log F).
    (c) VIDEO— pelo menos um ficheiro de vídeo a CRESCER em bytes (--video F).
    (d) ORDER— uma linha NOVA na tabela `orders` com marca de teste E2E (--orders-marker).

Sem nenhuma prova válida → exit 2 → o Juiz REJEITA e a ordem reporta honestamente
"BLOQUEADO — sem prova" em vez de ser aprovada.

Isto é MECÂNICO — não dá para conversar em volta. Não é um hook (a Trava vive em
.claude/hooks/); é um script que o `juiz-revisor` é OBRIGADO a correr sempre que a
tarefa fizer uma destas alegações.

Exit: 0 = HÁ PROVA (aceita) · 2 = SEM PROVA (rejeita).

Uso:
  python .claude/juiz/prova_processo.py [--pid N] [--adb-log F] [--video F] \
         [--orders-marker] [--orders-since-min 60] [--json]
"""
from __future__ import annotations
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent
FRESCURA_S = 15 * 60          # provas mais velhas que isto não contam como "agora"
VIDEO_SAMPLE_WAIT_S = 4.0     # janela para confirmar que o vídeo cresce
TEST_MARKER = "TESTE E2E"     # convenção do loop (limpar-dados-teste.py: customer_name ILIKE)


# ── (a) PID vivo ──────────────────────────────────────────────────────────────
def prova_pid(pid: int) -> dict:
    """Windows: tasklist confirma se o PID existe agora. Verdade mecânica."""
    try:
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                             capture_output=True, text=True, timeout=20).stdout or ""
    except Exception as e:
        return {"prova": "pid", "ok": False, "motivo": f"tasklist falhou: {e}", "pid": pid}
    vivo = bool(re.search(rf'","{pid}",', out) or f',"{pid}",' in out or f'"{pid}"' in out)
    linha = next((l for l in out.splitlines() if str(pid) in l), "")
    return {"prova": "pid", "ok": vivo, "pid": pid,
            "detalhe": linha.strip()[:200] if vivo else "PID não está na tasklist (processo morto)",
            "motivo": None if vivo else "processo não existe / já terminou"}


# ── (b) log adb com resposta real ─────────────────────────────────────────────
def prova_adb_log(path: str) -> dict:
    p = Path(path)
    if not p.exists():
        return {"prova": "adb-log", "ok": False, "motivo": f"log inexistente: {path}"}
    idade = time.time() - p.stat().st_mtime
    txt = p.read_text(encoding="utf-8", errors="replace")
    tem_cmd = bool(re.search(r"\badb\b.*\b(devices|shell|logcat|get-state|reconnect)\b", txt, re.I))
    # resposta real: serial listado como 'device', estado, ou saída de logcat/getprop
    tem_resp = bool(re.search(r"\bdevice\b|\bList of devices\b|\bpackage:|^\w{6,}\s+device$|getprop|logcat",
                              txt, re.I | re.M))
    fresco = idade <= FRESCURA_S
    ok = tem_cmd and tem_resp and fresco and p.stat().st_size > 0
    motivo = None
    if not ok:
        faltas = []
        if not tem_cmd: faltas.append("sem comando adb")
        if not tem_resp: faltas.append("sem resposta do device")
        if not fresco: faltas.append(f"log velho ({int(idade)}s > {FRESCURA_S}s)")
        if p.stat().st_size == 0: faltas.append("log vazio")
        motivo = "; ".join(faltas)
    return {"prova": "adb-log", "ok": ok, "path": str(p), "idade_s": int(idade),
            "bytes": p.stat().st_size, "motivo": motivo}


# ── (c) vídeo a crescer ───────────────────────────────────────────────────────
def prova_video(path: str) -> dict:
    p = Path(path)
    if not p.exists():
        return {"prova": "video", "ok": False, "motivo": f"vídeo inexistente: {path}"}
    b0 = p.stat().st_size
    time.sleep(VIDEO_SAMPLE_WAIT_S)
    b1 = p.stat().st_size if p.exists() else 0
    cresceu = b1 > b0 and b1 > 0
    return {"prova": "video", "ok": cresceu, "path": str(p),
            "bytes_inicio": b0, "bytes_fim": b1, "delta": b1 - b0,
            "motivo": None if cresceu else f"não cresceu ({b0}->{b1} bytes) — gravação parada?"}


# ── (d) linha nova nas orders com marca de teste ──────────────────────────────
def _env() -> dict:
    env = {}
    for f in [REPO / ".claude" / "testes-e2e" / ".env", REPO / "backend" / ".env"]:
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*([A-Z_]+)\s*=\s*[\"']?([^\"'#]+)", line)
                if m:
                    env.setdefault(m.group(1), m.group(2).strip())
    return env


def prova_orders_marker(desde_min: int) -> dict:
    import urllib.request
    import urllib.parse
    from datetime import datetime, timedelta, timezone
    env = _env()
    url = (env.get("SUPABASE_URL") or "").rstrip("/")
    key = env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SERVICE_ROLE_KEY")
    if not url or not key:
        return {"prova": "orders-marker", "ok": False, "motivo": "sem credenciais Supabase no .env"}
    desde = (datetime.now(timezone.utc) - timedelta(minutes=desde_min)).isoformat()
    q = urllib.parse.urlencode({
        "select": "id,customer_name,created_at",
        "customer_name": f"ilike.*{TEST_MARKER}*",
        "created_at": f"gte.{desde}",
        "order": "created_at.desc", "limit": "5"})
    req = urllib.request.Request(f"{url}/rest/v1/orders?{q}",
                                 headers={"apikey": key, "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            linhas = json.loads(resp.read().decode() or "[]")
    except Exception as e:
        return {"prova": "orders-marker", "ok": False, "motivo": f"query falhou: {e}"}
    ok = len(linhas) > 0
    return {"prova": "orders-marker", "ok": ok, "encontradas": len(linhas),
            "desde_min": desde_min, "amostra": [l.get("id") for l in linhas[:3]],
            "motivo": None if ok else f"nenhuma order '{TEST_MARKER}' nos últimos {desde_min} min"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pid", type=int)
    ap.add_argument("--adb-log")
    ap.add_argument("--video")
    ap.add_argument("--orders-marker", action="store_true")
    ap.add_argument("--orders-since-min", type=int, default=60)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    provas = []
    if a.pid is not None:
        provas.append(prova_pid(a.pid))
    if a.adb_log:
        provas.append(prova_adb_log(a.adb_log))
    if a.video:
        provas.append(prova_video(a.video))
    if a.orders_marker:
        provas.append(prova_orders_marker(a.orders_since_min))

    nenhuma_pedida = not provas
    validas = [p for p in provas if p.get("ok")]
    aceita = bool(validas)

    veredito = {
        "aceita": aceita,
        "veredito": "HÁ PROVA" if aceita else "SEM PROVA — BLOQUEADO",
        "provas": provas,
        "provas_validas": [p["prova"] for p in validas],
        "regra": ("Tarefa que alega arrancar processo em segundo plano / teste no telemóvel "
                  "SÓ passa com >=1 prova válida (pid vivo | adb-log | vídeo a crescer | order E2E nova)."),
    }
    if nenhuma_pedida:
        veredito["motivo"] = ("nenhuma evidência fornecida — o executor tem de apresentar pelo "
                              "menos uma prova; caso contrário reportar 'BLOQUEADO — sem prova'.")

    if a.json:
        print(json.dumps(veredito, ensure_ascii=False, indent=2))
    else:
        print(f"⚖️ PROVA DE PROCESSO — {veredito['veredito']}")
        for p in provas:
            mark = "✅" if p.get("ok") else "❌"
            print(f"  {mark} {p['prova']}: {p.get('motivo') or p.get('detalhe') or 'OK'}")
        if not aceita:
            print("  → REJEITA. A ordem deve reportar 'BLOQUEADO — sem prova'.")

    return 0 if aceita else 2


if __name__ == "__main__":
    sys.exit(main())
