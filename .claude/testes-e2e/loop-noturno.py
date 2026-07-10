# -*- coding: utf-8 -*-
"""
Loop Noturno E2E — Fase 7 (single-device).

Ciclo:
  1. guarda de ambiente: telemóvel no adb (reconnect se caiu) + NENHUM gradle/java pesado
     a correr (lição OOM JVM — Maestro nunca em simultâneo com build).
  2. corre a suite (runner.py --single-device, cinegrafista ON — o runner filma sempre).
  3. falha → frames já extraídos pelo runner → CLASSIFICA:
       BUG DO TESTE (selector/timing) → afina o YAML (timeouts ×1.5) e re-corre no próximo ciclo.
       BUG DO APP  → zona verde  → BUG-APP-REGISTADO (fica para o Danilo/loop de ordens);
                     zona vermelha (pagamento/checkout/dinheiro) → BLOQUEADO-APROVACAO.
  4. re-corre SÓ os falhados; repete até tudo PASSOU ou só restarem
     BLOQUEADO-APROVACAO / MANUAL-2-DEVICES / BUG-APP-REGISTADO.
  5. verde 2 ciclos seguidos → não re-corre (EXCETO críticos: checkout/delivery/dispatch,
     que continuam como regressão enquanto houver outros pendentes).
  6. device caiu do adb → pausa + adb reconnect + regista. O loop NUNCA crasha.

O loop NÃO corrige código da app (lib/, supabase/) — SÓ YAMLs de teste e timeouts do registry.
Progresso por ciclo: .claude/.ai/knowledge/inbox/e2e-resultados-<data>.md + loop-noturno-<data>.json.
Parar a meio: criar o ficheiro PARAR nesta pasta.
"""
import json
import re
import subprocess
import sys
import time
import traceback
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent
FLOWS = BASE / "flows"
INBOX = REPO / ".claude" / ".ai" / "knowledge" / "inbox"
STOP_FILE = BASE / "PARAR"

MAX_CICLOS = 10
MAX_FIX_TENTATIVAS = 2          # afinações de timing por fluxo antes de virar BUG DO APP
MAX_AMBIENTE_FALHAS = 3         # PRE-CONDICAO-FALHOU seguidas antes de desistir do fluxo
VERDES_PARA_ESTAVEL = 2
TIMEOUT_RUNNER_S = 3600

CRITICOS_PAT = re.compile(r"checkout|delivery|dispatch", re.I)
RED_ZONE_PAT = re.compile(
    r"pagamento|pagar|checkout|dinheiro|stripe|mb\s?way|mbway|bora_tokens|token|wallet|"
    r"refund|reembolso|comiss|fee|pricing|finalizePurchase", re.I)
TESTE_PAT = re.compile(r"element not found|timed ?out|timeout|assertion|not visible|"
                       r"unable to find|extendedwaituntil", re.I)
APP_PAT = re.compile(r"crashed|crash|anr |fatal exception|unable to launch app", re.I)

ESTADOS_TERMINAIS = {"BLOQUEADO-APROVACAO", "BUG-APP-REGISTADO", "MANUAL-2-DEVICES",
                     "AMBIENTE-NAO-ISOLADO", "PENDENTE-HUMANO"}


def log(msg: str):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)


# ── guarda de ambiente ────────────────────────────────────────────────────────

def _adb() -> str:
    import os
    cand = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/platform-tools/adb.exe"
    return str(cand) if cand.exists() else "adb"


def adb_serials() -> list:
    try:
        out = subprocess.run([_adb(), "devices"], capture_output=True, text=True, timeout=20).stdout or ""
    except Exception:
        return []
    return [l.split("\t")[0] for l in out.splitlines()[1:] if "\tdevice" in l]


def garante_device(eventos: list) -> bool:
    """Telemóvel presente? Se caiu: pausa + adb reconnect (regista). Nunca lança exceção."""
    for tentativa in range(1, 16):  # ~5 min
        if adb_serials():
            return True
        eventos.append({"ts": time.time(), "evento": f"device ausente (tentativa {tentativa}) — adb reconnect"})
        log(f"telemóvel caiu do adb — reconnect (tentativa {tentativa}/15)")
        for cmd in (["reconnect"], ["reconnect", "offline"]):
            try:
                subprocess.run([_adb()] + cmd, capture_output=True, timeout=20)
            except Exception:
                pass
        time.sleep(20)
    eventos.append({"ts": time.time(), "evento": "device NÃO voltou após 15 tentativas"})
    return False


def gradle_a_correr() -> bool:
    """True se houver java.exe com 'gradle' na command line (lição OOM: nunca Maestro + build)."""
    ps = ("Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" | "
          "ForEach-Object { $_.CommandLine }")
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command", ps],
                             capture_output=True, text=True, timeout=45).stdout or ""
    except Exception:
        return False  # não conseguiu verificar → não bloqueia a noite
    return bool(re.search(r"gradle", out, re.I))


def espera_sem_gradle(eventos: list):
    t0 = time.time()
    while gradle_a_correr():
        if time.time() - t0 > 1800:
            eventos.append({"ts": time.time(), "evento": "gradle ainda a correr após 30min — sigo com cautela"})
            return
        eventos.append({"ts": time.time(), "evento": "gradle/java a correr — espero 60s (OOM guard)"})
        log("build gradle ativo — espero 60s antes do Maestro (lição OOM)")
        time.sleep(60)


# ── correr fluxos via runner.py ───────────────────────────────────────────────

def corre_runner_fluxo(fid: str) -> dict:
    """Corre 1 fluxo no runner (single-device default) e devolve o resultado dele."""
    cmd = [sys.executable, str(BASE / "runner.py"), "--fluxo", fid]
    try:
        subprocess.run(cmd, cwd=str(BASE), timeout=TIMEOUT_RUNNER_S,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    except subprocess.TimeoutExpired:
        return {"id": fid, "estado": "FALHOU", "falha": {"erro": f"runner excedeu {TIMEOUT_RUNNER_S}s"}}
    except Exception as e:
        return {"id": fid, "estado": "FALHOU", "falha": {"erro": f"runner rebentou: {e}"}}
    # runner escreve resultados-<dia>.json (overwrite por invocação) — ler o mais recente
    files = sorted(BASE.glob("resultados-*.json"), key=lambda p: p.stat().st_mtime)
    if not files:
        return {"id": fid, "estado": "FALHOU", "falha": {"erro": "runner não escreveu resultados"}}
    try:
        dados = json.loads(files[-1].read_text(encoding="utf-8"))
        for r in dados.get("resultados", []):
            if r["id"] == fid:
                return r
    except Exception as e:
        return {"id": fid, "estado": "FALHOU", "falha": {"erro": f"resultados ilegíveis: {e}"}}
    return {"id": fid, "estado": "FALHOU", "falha": {"erro": "fluxo sem resultado no JSON"}}


def limpa_dados_teste(eventos: list):
    try:
        r = subprocess.run([sys.executable, str(BASE / "limpar-dados-teste.py")],
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=120)
        eventos.append({"ts": time.time(), "evento": f"limpeza pós-ciclo: {(r.stdout or '').strip()[:200]}"})
    except Exception as e:
        eventos.append({"ts": time.time(), "evento": f"limpeza falhou (não-fatal): {e}"})


# ── classificação + auto-afinação (SÓ YAMLs de teste) ────────────────────────

def texto_da_falha(resultado: dict) -> str:
    f = resultado.get("falha") or {}
    return " ".join(str(f.get(k, "")) for k in ("yaml", "tail", "erro", "poll_db"))


def classifica(resultado: dict, tentativas_fix: int) -> str:
    """'teste' (selector/timing → afinar YAML) ou 'app' (regista/bloqueia)."""
    txt = texto_da_falha(resultado)
    if APP_PAT.search(txt):
        return "app"
    if tentativas_fix >= MAX_FIX_TENTATIVAS:
        return "app"  # afinado 2x e continua a falhar → deixou de ser timing
    if TESTE_PAT.search(txt) or resultado.get("estado") == "FALHOU-DB-CHECK":
        return "teste"
    return "teste" if tentativas_fix == 0 else "app"  # 1º benefício da dúvida


def zona(resultado: dict) -> str:
    return "vermelha" if RED_ZONE_PAT.search(texto_da_falha(resultado)) else "verde"


def afina_yaml_timeouts(yaml_rel: str, mudancas: list) -> bool:
    """Afinação mecânica de timing: timeout(Ms) ×1.5, cap 300000. SÓ em flows/ de teste."""
    p = (FLOWS / yaml_rel).resolve()
    if FLOWS.resolve() not in p.parents or not p.exists():
        return False
    txt = p.read_text(encoding="utf-8")

    def bump(m):
        novo = min(int(int(m.group(2)) * 1.5), 300000)
        return f"{m.group(1)}{novo}"

    novo_txt = re.sub(r"(timeout:\s*)(\d+)", bump, txt)
    if novo_txt != txt:
        p.write_text(novo_txt, encoding="utf-8")
        mudancas.append(f"{yaml_rel}: timeouts ×1.5")
        return True
    return False


def afina_registry_poll(fid: str, mudancas: list) -> bool:
    """poll_db a dar timeout → sobe timeout_s no registry (×1.5, cap 900)."""
    reg_path = FLOWS / "registry.json"
    reg = json.loads(reg_path.read_text(encoding="utf-8"))
    mudou = False
    for f in reg["fluxos"]:
        if f["id"] != fid:
            continue
        for passo in f.get("passos", []):
            if passo.get("tipo") == "poll_db":
                antigo = passo.get("timeout_s", 180)
                passo["timeout_s"] = min(int(antigo * 1.5), 900)
                mudou = mudou or passo["timeout_s"] != antigo
    if mudou:
        reg_path.write_text(json.dumps(reg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        mudancas.append(f"{fid}: poll_db timeout_s ×1.5 (registry)")
    return mudou


def aplica_fix_teste(st: dict, resultado: dict, mudancas: list):
    falha = resultado.get("falha") or {}
    if falha.get("yaml"):
        afina_yaml_timeouts(falha["yaml"], mudancas)
    elif falha.get("poll_db") or resultado.get("estado") == "FALHOU-DB-CHECK":
        afina_registry_poll(resultado["id"], mudancas)
    st["fix_tentativas"] += 1


# ── relatório ────────────────────────────────────────────────────────────────

def escreve_progresso(dia: str, ciclos: list, estados: dict, eventos: list, mudancas: list, fim: bool):
    INBOX.mkdir(parents=True, exist_ok=True)
    verdes = [f for f, s in estados.items() if s["ultimo_estado"] == "PASSOU"]
    linhas = ["---", f"id: e2e-resultados-{dia}", "tipo: relatorio",
              "origem: [loop-noturno E2E testes-e2e (Fase 7 single-device)]",
              f"ultima_confirmacao: {dia}", "zona: verde", "confianca: auto", "---", "",
              f"# Loop Noturno E2E — {dia}: {len(verdes)}/{len(estados)} verdes"
              f" ({'TERMINADO' if fim else 'a correr'})", ""]
    linhas.append("## Estado por fluxo")
    for fid, s in estados.items():
        final = s["estado_final"] or s["ultimo_estado"] or "por correr"
        icon = {"PASSOU": "✅", "MANUAL-2-DEVICES": "📱📱", "BLOQUEADO-APROVACAO": "🔴",
                "BUG-APP-REGISTADO": "🐛", "AMBIENTE-NAO-ISOLADO": "⚠️",
                "PENDENTE-HUMANO": "🙋"}.get(final, "❌")
        extra = f" · verdes seguidos: {s['verdes_seguidos']} · afinações: {s['fix_tentativas']}"
        if s.get("nota"):
            extra += f" · {s['nota']}"
        linhas.append(f"- {icon} **{fid}** — {final}{extra}")
    linhas.append("")
    linhas.append("## Ciclos")
    for c in ciclos:
        linhas.append(f"- ciclo {c['n']}: corridos {c['corridos']} → "
                      f"{c['passou']} PASSOU / {c['falhou']} FALHOU ({c['dur_s']}s)")
    if mudancas:
        linhas.append("")
        linhas.append("## YAMLs de teste afinados pelo loop (NUNCA código da app)")
        linhas += [f"- {m}" for m in mudancas]
    bugs = [(f, s) for f, s in estados.items() if s["estado_final"] in ("BUG-APP-REGISTADO", "BLOQUEADO-APROVACAO")]
    if bugs:
        linhas.append("")
        linhas.append("## Bugs do APP para o Danilo/loop de ordens (o loop NÃO corrige a app)")
        for fid, s in bugs:
            linhas.append(f"- **{fid}** ({s['estado_final']}): `{str(s.get('ultima_falha'))[:300]}`")
    (INBOX / f"e2e-resultados-{dia}.md").write_text("\n".join(linhas) + "\n", encoding="utf-8")
    (BASE / f"loop-noturno-{dia}.json").write_text(json.dumps(
        {"data": datetime.now().isoformat(timespec="seconds"), "fim": fim, "ciclos": ciclos,
         "estados": estados, "mudancas": mudancas, "eventos": eventos[-200:]},
        indent=2, ensure_ascii=False, default=str), encoding="utf-8")


# ── loop principal ───────────────────────────────────────────────────────────

def main():
    dia = datetime.now().strftime("%Y-%m-%d")
    reg = json.loads((FLOWS / "registry.json").read_text(encoding="utf-8"))
    eventos, mudancas, ciclos = [], [], []

    estados = {}
    for f in reg["fluxos"]:
        estados[f["id"]] = {"verdes_seguidos": 0, "fix_tentativas": 0, "ambiente_falhas": 0,
                            "estado_final": None, "ultimo_estado": None, "ultima_falha": None,
                            "critico": bool(CRITICOS_PAT.search(f["id"])), "nota": ""}
        if f.get("manual_2_devices"):
            estados[f["id"]]["estado_final"] = "MANUAL-2-DEVICES"
            estados[f["id"]]["nota"] = "exige 2 telemóveis em tempo real"

    log(f"loop noturno Fase 7 — {len(estados)} fluxos no registry")

    for n in range(1, MAX_CICLOS + 1):
        if STOP_FILE.exists():
            eventos.append({"ts": time.time(), "evento": "ficheiro PARAR encontrado — paro"})
            break
        elegiveis = [f for f, s in estados.items() if s["estado_final"] is None]
        pendentes = [f for f in elegiveis if estados[f]["verdes_seguidos"] < VERDES_PARA_ESTAVEL]
        if not pendentes:
            log("tudo verde-estável ou terminal — fim do loop")
            break
        # críticos (checkout/delivery/dispatch) re-correm como regressão enquanto há pendentes
        a_correr = pendentes + [f for f in elegiveis
                                if estados[f]["critico"] and f not in pendentes]
        log(f"── CICLO {n}: {len(a_correr)} fluxos → {a_correr}")
        t0 = time.time()
        passou = falhou = 0

        for fid in a_correr:
            if STOP_FILE.exists():
                break
            try:
                if not garante_device(eventos):
                    for g in a_correr:
                        if estados[g]["estado_final"] is None:
                            estados[g]["estado_final"] = "PENDENTE-HUMANO"
                            estados[g]["nota"] = "telemóvel caiu do adb e não voltou — ligar e correr run-tudo.cmd"
                    break
                espera_sem_gradle(eventos)
                r = corre_runner_fluxo(fid)
                st = estados[fid]
                st["ultimo_estado"] = r["estado"]
                if r["estado"] == "PASSOU":
                    passou += 1
                    st["verdes_seguidos"] += 1
                    st["ambiente_falhas"] = 0
                elif r["estado"] == "MANUAL-2-DEVICES":
                    st["estado_final"] = "MANUAL-2-DEVICES"
                elif r["estado"] == "PRE-CONDICAO-FALHOU":
                    falhou += 1
                    st["verdes_seguidos"] = 0
                    st["ambiente_falhas"] += 1
                    st["ultima_falha"] = r.get("erro")
                    if st["ambiente_falhas"] >= MAX_AMBIENTE_FALHAS:
                        st["estado_final"] = "AMBIENTE-NAO-ISOLADO"
                        st["nota"] = "estafetas reais online — guarda de isolamento abortou 3x"
                else:  # FALHOU / FALHOU-DB-CHECK
                    falhou += 1
                    st["verdes_seguidos"] = 0
                    st["ultima_falha"] = r.get("falha") or r.get("estado")
                    tipo = classifica(r, st["fix_tentativas"])
                    if tipo == "teste":
                        aplica_fix_teste(st, r, mudancas)
                        log(f"  {fid}: BUG DO TESTE → YAML afinado (tentativa {st['fix_tentativas']})")
                    else:
                        z = zona(r)
                        st["estado_final"] = "BLOQUEADO-APROVACAO" if z == "vermelha" else "BUG-APP-REGISTADO"
                        log(f"  {fid}: BUG DO APP (zona {z}) → {st['estado_final']}")
            except Exception as e:  # o loop NUNCA crasha
                eventos.append({"ts": time.time(), "evento": f"exceção em {fid}: {e}",
                                "trace": traceback.format_exc()[-800:]})
                log(f"  {fid}: exceção não-fatal registada — sigo")
        limpa_dados_teste(eventos)
        ciclos.append({"n": n, "corridos": len(a_correr), "passou": passou,
                       "falhou": falhou, "dur_s": round(time.time() - t0, 1)})
        escreve_progresso(dia, ciclos, estados, eventos, mudancas, fim=False)

    escreve_progresso(dia, ciclos, estados, eventos, mudancas, fim=True)
    finais = {f: (s["estado_final"] or s["ultimo_estado"]) for f, s in estados.items()}
    log(f"FIM: {json.dumps(finais, ensure_ascii=False)}")
    ok = all(v in ("PASSOU",) or v in ESTADOS_TERMINAIS for v in finais.values())
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
