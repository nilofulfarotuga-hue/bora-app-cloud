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
import os
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
LOCK_FILE = BASE / ".loop-noturno.lock"

# Diário E2E — o loop escreve eventos de ALTO NÍVEL (ciclo/classificação) em e2e_log;
# o runner (subprocesso) escreve os passos finos. Ambos → mesma tabela, mesmo Claude.ai a ver.
sys.path.insert(0, str(BASE))
import e2e_diario  # noqa: E402

MAX_CICLOS = 10
MAX_FIX_TENTATIVAS = 2          # afinações de timing por fluxo antes de virar BUG DO APP
MAX_AMBIENTE_FALHAS = 3         # PRE-CONDICAO-FALHOU seguidas antes de desistir do fluxo
VERDES_PARA_ESTAVEL = 2
TIMEOUT_RUNNER_S = 3600

CRITICOS_PAT = re.compile(r"checkout|delivery|dispatch", re.I)
RED_ZONE_PAT = re.compile(
    r"pagamento|pagar|checkout|dinheiro|stripe|mb\s?way|mbway|bora_tokens|token|wallet|"
    r"refund|reembolso|comiss|fee|pricing|finalizePurchase", re.I)
# Lição 2026-07-12: das últimas 48h, 68 falhas eram desconexão de device/adb (INFRA)
# e 15 foram erradamente marcadas BUG-APP (todas reset-role-screen a cair por device
# caído). Infra NUNCA é bug do app — reconecta e re-corre. Verificado ANTES de tudo.
INFRA_PAT = re.compile(
    r"device not connected|device not found|device offline|\boffline\b|"
    r"\bunauthorized\b|no devices(?:/emulators)? found|"
    r"device '[^']*' not found|error: device|daemon not running|"
    # Lição 2026-07-12 (run 20260712-073807): a frase REAL do Maestro quando o
    # device cai a meio é "Device <serial> was requested, but it is not connected."
    # O INFRA_PAT antigo só tinha "device not connected" (colado), por isso NÃO
    # apanhava esta — o smoke caía em reset-role-screen e era mal-marcado BUG-APP.
    r"was requested, but it is not connected|\bis not connected\b|not connected", re.I)
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


APP_PACKAGE = "pt.boraapp.bora"
# Lição 2026-07-11: um diálogo de permissão do Android (armazenamento) travou o
# arranque da suite à espera de toque humano. Concedemos TODAS as permissões de
# runtime por adb assim que o device está presente — o runner repete por segurança.
_RUNTIME_PERMISSIONS = [
    "android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION", "android.permission.CAMERA",
    "android.permission.POST_NOTIFICATIONS", "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE", "android.permission.READ_MEDIA_IMAGES",
    "android.permission.RECORD_AUDIO",
]


def concede_permissoes(eventos: list):
    """Best-effort, idempotente: pm grant de cada permissão em cada device presente.
    Tolera erro por permissão (não declarada / versão Android) — nunca aborta a noite."""
    for serial in adb_serials():
        n_ok = 0
        for perm in _RUNTIME_PERMISSIONS:
            try:
                r = subprocess.run([_adb(), "-s", serial, "shell", "pm", "grant", APP_PACKAGE, perm],
                                   capture_output=True, text=True, timeout=20)
                if r.returncode == 0:
                    n_ok += 1
            except Exception:
                pass
        for op in ("SYSTEM_ALERT_WINDOW", "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"):
            try:
                subprocess.run([_adb(), "-s", serial, "shell", "appops", "set", APP_PACKAGE, op, "allow"],
                               capture_output=True, timeout=20)
            except Exception:
                pass
        eventos.append({"ts": time.time(), "evento": f"permissões concedidas via adb ({n_ok} ok) @ {serial}"})
        log(f"permissões de runtime concedidas via adb ({n_ok} ok) @ {serial}")


def garante_device(eventos: list) -> bool:
    """Telemóvel presente? Se caiu: pausa + recuperação adb (regista). Nunca lança exceção.

    Lição 2026-07-11: o device pode ficar 'unauthorized' (não conta como presente).
    `adb reconnect` NÃO limpa um daemon preso em 'unauthorized' — só kill-server +
    start-server o faz (reusa ~/.android/adbkey já autorizada). Por isso, em cada
    tentativa, forçamos primeiro um restart completo do daemon e só depois reconnect."""
    for tentativa in range(1, 16):  # ~5 min
        if adb_serials():
            concede_permissoes(eventos)
            return True
        eventos.append({"ts": time.time(), "evento": f"device ausente/unauthorized (tentativa {tentativa}) — restart daemon + reconnect"})
        log(f"telemóvel caiu do adb — kill/start-server + reconnect (tentativa {tentativa}/15)")
        # restart completo do daemon: o que realmente destranca 'unauthorized'
        for cmd in (["kill-server"], ["start-server"], ["reconnect"], ["reconnect", "offline"]):
            try:
                subprocess.run([_adb()] + cmd, capture_output=True, timeout=30)
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
    """'infra' (device/adb caiu → reconecta e re-corre, NUNCA bug do app),
    'teste' (selector/timing → afinar YAML) ou 'app' (regista/bloqueia)."""
    txt = texto_da_falha(resultado)
    if INFRA_PAT.search(txt):
        return "infra"  # desconexão de device/adb — nunca é bug do app
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
                            "infra_falhas": 0,
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
        e2e_diario.registar("loop-noturno", f"ciclo {n} arranca", "iniciou",
                            detalhe=f"{len(a_correr)} fluxos: {a_correr}", device="host")
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
                    if tipo == "infra":
                        st["infra_falhas"] = st.get("infra_falhas", 0) + 1
                        log(f"  {fid}: FALHA-INFRA (device/adb caiu) → reconecta e re-corre "
                            f"(infra #{st['infra_falhas']}, NÃO é bug do app)")
                        e2e_diario.registar(fid, "classificação do loop", "falhou",
                                            detalhe=f"FALHA-INFRA (device/adb) → reconecta e re-corre "
                                                    f"(infra #{st['infra_falhas']})",
                                            device="host")
                        garante_device(eventos)  # recupera já; re-corre no próximo ciclo
                    elif tipo == "teste":
                        aplica_fix_teste(st, r, mudancas)
                        log(f"  {fid}: BUG DO TESTE → YAML afinado (tentativa {st['fix_tentativas']})")
                        e2e_diario.registar(fid, "classificação do loop", "falhou",
                                            detalhe=f"BUG DO TESTE → YAML afinado (tentativa {st['fix_tentativas']})",
                                            device="host")
                    else:
                        z = zona(r)
                        st["estado_final"] = "BLOQUEADO-APROVACAO" if z == "vermelha" else "BUG-APP-REGISTADO"
                        log(f"  {fid}: BUG DO APP (zona {z}) → {st['estado_final']}")
                        e2e_diario.registar(fid, "classificação do loop", "falhou",
                                            detalhe=f"BUG DO APP (zona {z}) → {st['estado_final']}",
                                            device="host")
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


def _pid_vivo(pid):
    try:
        out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                              capture_output=True, text=True, timeout=10).stdout or ""
        return str(pid) in out
    except Exception:
        return False


def adquire_lock_unico():
    """Lição 2026-07-12: as tarefas agendadas HORÁRIAS empilhavam-se em cima de corridas
    presas (o schtask dispara de novo mesmo com a corrida anterior ainda viva) — 4 instâncias
    chegaram a correr ao mesmo tempo, todas a lutar pelos mesmos 2 telemóveis via adb. Isso
    é que produzia os erros persistentes "device not connected"/"unauthorized", não o
    hardware. Lock de instância única: se já há um PID vivo dono do lock, esta corrida NÃO
    arranca por cima — sai já (o schtask tenta de novo na próxima hora)."""
    if LOCK_FILE.exists():
        try:
            pid_antigo = int(LOCK_FILE.read_text(encoding="utf-8").strip())
        except Exception:
            pid_antigo = None
        if pid_antigo and _pid_vivo(pid_antigo):
            log(f"já há uma instância a correr (pid={pid_antigo}) — não arranco outra em cima; saio")
            return False
        log(f"lock órfão (pid antigo {pid_antigo} já não está vivo) — assumo o lock")
    LOCK_FILE.write_text(str(os.getpid()), encoding="utf-8")
    return True


def liberta_lock_unico():
    try:
        if LOCK_FILE.exists() and LOCK_FILE.read_text(encoding="utf-8").strip() == str(os.getpid()):
            LOCK_FILE.unlink()
    except Exception:
        pass


if __name__ == "__main__":
    if not adquire_lock_unico():
        sys.exit(0)
    try:
        main()
    finally:
        liberta_lock_unico()
