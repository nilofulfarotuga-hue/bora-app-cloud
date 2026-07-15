# -*- coding: utf-8 -*-
"""
heartbeat-browser.py — Loop 🟢 Core: fecha o loop de orquestracao SEM API paga.

PROBLEMA: quando uma ordem do loop chega a estado FINAL (aprovada / travada /
zona_vermelha / cancelada) ou quando ha testes novos, o Claude.ai (a cabeca que
decide a proxima ordem) so sabe se alguem lhe contar. Contar por API custa.

SOLUCAO (sem custo de API): o agente que JA CLICA — o browser-operador
(Claude in Chrome, sessao Pro do Danilo, ja pareado) — abre o claude.ai num
CHAT NOVO e cola uma frase fixa. O Claude.ai age sozinho a partir dai. Este
script e so o GATILHO + o ANTI-SPAM: deteta se houve mudanca real de estado e,
so nesse caso, deixa um pedido (pending.trigger) para o browser-operador
executar. Se nada mudou desde a ultima verificacao -> silencio total (nao
enche o Danilo de chats vazios).

FLUXO:
  cron/schtask */10  ->  este script  ->  (mudou?) sim -> escreve pending.trigger
                                          nao        -> exit 0 silencioso
  browser-operador (PC, Claude in Chrome) ve pending.trigger -> abre claude.ai
     chat NOVO -> cola a FRASE_FIXA -> envia -> fecha -> marca trigger consumido.

FONTES DE ESTADO (watermark barato, read-only):
  1) Fila local `orquestracao/*.md` — ids em estado FINAL (o sintoma principal).
  2) e2e_log (Supabase, anon read via PostgREST) — ultimo teste registado.
  3) orders (Supabase) — ultimo pedido (best-effort; degrada se RLS bloquear).
Qualquer fonte que falhe degrada em silencio (nunca parte o heartbeat).

SEGURANCA: read-only sobre estado; nao toca dinheiro/dispatch/tokens. A frase
fixa e benigna e o proprio Claude.ai tem os seus guardrails (Trava/Juiz). Nunca
imprime segredos (le a key de .env em runtime, nunca a mostra).

Registado em permanente/semantica/loops.md (🟢 Core). Dono: browser-operador.
Licao: wiki/licoes/heartbeat-sem-api-via-browser.md.

Uso:
  python heartbeat-browser.py            # corre o ciclo (cron)
  python heartbeat-browser.py --dry      # so decide+loga, nao escreve trigger
  python heartbeat-browser.py --force    # forca o trigger (teste do mecanismo)
  python heartbeat-browser.py --status   # mostra o estado atual e sai
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = Path(__file__).resolve().parent            # .claude/scripts
REPO = BASE.parent.parent                          # raiz do repo (bora_app)
HB_DIR = REPO / ".claude" / ".ai" / "hermes" / "heartbeat-browser"
STATE_FILE = HB_DIR / "state.json"
TRIGGER_FILE = HB_DIR / "pending.trigger"
LOG_FILE = HB_DIR / "heartbeat-browser.log"
CONSUMED_DIR = HB_DIR / "consumidos"

ORQ_DIR = Path(os.environ.get("BORA_ORQ_DIR", str(REPO / "orquestracao")))
FINAL_STATES = {"aprovada", "travada", "zona_vermelha", "cancelada"}

# FRASE FIXA — colada num chat NOVO do claude.ai pelo browser-operador. VERBATIM.
FRASE_FIXA = (
    "Bora Loop automatico: puxa o contexto do Bora pela tua memoria e Cortex, "
    "verifica o estado das ordens (cortex_ler) e dos testes (SELECT em orders e "
    "e2e_log no Supabase), e age no que for preciso - dispara a proxima ordem se "
    "algo travou ou ficou incompleto, ou responde que esta tudo ok se nao ha nada "
    "pendente. So avisa o Danilo se for importante ou decisao de dinheiro."
)


def ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(msg):
    HB_DIR.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"[{ts()}] {msg}\n")


def _load_env():
    """SUPABASE_URL/KEY de .env do e2e, fallback backend/.env. So valores; nunca imprime."""
    env = {}
    for f in [REPO / ".claude" / "testes-e2e" / ".env", REPO / "backend" / ".env"]:
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*[\"']?([^\"'#]+)", line)
                if m:
                    env.setdefault(m.group(1), m.group(2).strip())
    url = env.get("SUPABASE_URL") or env.get("SUPABASE_PROJECT_URL")
    # SELECT read-only: qualquer key serve; preferimos anon.
    key = (env.get("SUPABASE_ANON_KEY") or env.get("SUPABASE_KEY")
           or env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SERVICE_ROLE_KEY"))
    return url, key


def _get_latest(url, key, table, order_col):
    """Ultimo registo (id+order_col) de uma tabela via PostgREST. '' se falhar/vazio/RLS."""
    if not url or not key:
        return ""
    try:
        q = f"{url}/rest/v1/{table}?select=id,{order_col}&order={order_col}.desc&limit=1"
        req = urllib.request.Request(q, headers={
            "apikey": key, "Authorization": f"Bearer {key}", "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as r:
            rows = json.loads(r.read().decode("utf-8"))
        if rows:
            return f"{rows[0].get('id', '')}|{rows[0].get(order_col, '')}"
    except Exception as e:
        log(f"aviso: SELECT {table} degradou ({type(e).__name__}) — ignoro esta fonte")
    return ""


def _get(field, text):
    m = re.search(rf"(?m)^{re.escape(field)}:\s*(.+?)\s*$", text)
    return m.group(1).strip() if m else ""


def _orders_signature():
    """Assinatura das ordens em estado FINAL: sha256 de 'id:estado' ordenados. '' se pasta ausente."""
    if not ORQ_DIR.is_dir():
        return ""
    finals = []
    for f in sorted(ORQ_DIR.glob("*.md")):
        try:
            txt = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        estado = _get("estado", txt).lower()
        if estado in FINAL_STATES:
            oid = _get("id", txt) or f.stem
            finals.append(f"{oid}:{estado}")
    if not finals:
        return "none"
    return hashlib.sha256("\n".join(sorted(finals)).encode("utf-8")).hexdigest()[:16]


def compute_watermark():
    url, key = _load_env()
    return {
        "orders_final": _orders_signature(),
        "e2e_latest": _get_latest(url, key, "e2e_log", "created_at"),
        "db_orders_latest": _get_latest(url, key, "orders", "created_at"),
    }


def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text(encoding="utf-8"))
        except Exception:
            return {}
    return {}


def save_state(wm):
    HB_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(wm, indent=2, ensure_ascii=False), encoding="utf-8")


def changed(prev, wm):
    """Mudou se QUALQUER fonte NAO-vazia avancou. Fonte que degradou ('') nao dispara sozinha."""
    diffs = []
    for k, v in wm.items():
        if v and v != prev.get(k):
            diffs.append(f"{k}: {prev.get(k, '<novo>')} -> {v}")
    return diffs


def write_trigger(diffs):
    HB_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "criado": ts(),
        "motivo": diffs,
        "acao": "abrir claude.ai em CHAT NOVO (sessao do Danilo) e colar a frase, enviar, fechar",
        "frase": FRASE_FIXA,
    }
    TRIGGER_FILE.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


def main():
    argv = sys.argv[1:]
    dry = "--dry" in argv
    force = "--force" in argv

    if "--status" in argv:
        wm = compute_watermark()
        print(json.dumps({"agora": wm, "guardado": load_state(),
                          "trigger_pendente": TRIGGER_FILE.exists()},
                         indent=2, ensure_ascii=False))
        return 0

    wm = compute_watermark()
    prev = load_state()

    # Primeira execucao: semeia sem disparar (backlog atual nao e novidade).
    if not prev and not force:
        if dry:
            print(f"DRY: init watermark (sem disparo) -> {wm}")
            return 0
        save_state(wm)
        log(f"init watermark (sem disparo) -> {wm}")
        return 0

    diffs = changed(prev, wm) if not force else ["--force (teste do mecanismo)"]

    if not diffs:
        if dry:
            print(f"DRY: sem mudanca de estado — silencio. wm={wm}")
        log("sem mudanca — silencio (anti-spam)")
        return 0

    # Ha mudanca real -> deixa o pedido para o browser-operador.
    if dry:
        print("DRY: DISPARARIA browser-operador. Motivo:\n  - " + "\n  - ".join(diffs))
        print("DRY: frase =\n" + FRASE_FIXA)
        return 0

    write_trigger(diffs)
    save_state(wm)
    log("DISPAROU pending.trigger. Motivo: " + " | ".join(diffs))
    print("pending.trigger escrito. browser-operador deve abrir chat novo no claude.ai.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
