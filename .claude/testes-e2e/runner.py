# -*- coding: utf-8 -*-
"""
Runner E2E — o Olho do Bora.

Por fluxo (flows/registry.json):
  cinegrafista ON (por serial) → Maestro no(s) telemóvel(is) → [2-DEVICES]: poll no
  Supabase (READ-ONLY) entre passos → validação final no banco → cinegrafista OFF.

Saída: resultados-<data>.json (nesta pasta) + resumo em
       .claude/.ai/knowledge/inbox/e2e-resultados-<data>.md

Uso:
    python runner.py --fluxo smoke-login-cliente
    python runner.py --todos
    python runner.py --so-falhados          (re-corre falhados do último resultados-*.json)
    (+ --two-devices para o modo antigo; o DEFAULT é --single-device)

MODO SINGLE-DEVICE (default, Fase 7):
- Tudo corre SEQUENCIAL no MESMO telemóvel (auto-detectado via adb; prefere o serial
  "cliente" do registry se estiver ligado).
- Antes de cada fluxo: comum/reset-role-screen.yaml normaliza para o RoleScreen.
- Fluxos "dois_devices": quando o passo muda de papel (cliente→estafeta), o runner corre
  o logout do papel anterior (flows/<papel>/logout.yaml via registry.logout_flows) e o
  login do novo papel já faz parte do YAML do passo. O pedido espera na fila do dispatch.
- Fluxos "manual_2_devices": EXIGEM 2 telemóveis em tempo real → marcados
  MANUAL-2-DEVICES no relatório e NÃO corridos (não bloqueiam a noite).
- Papel de PARCEIRO nos fluxos = painel admin/web no PC (browser), nunca no telemóvel.

Credenciais DB (read-only): .claude/testes-e2e/.env com SUPABASE_URL e SUPABASE_KEY
(fallback: tenta backend/.env). Sem credenciais → passos poll_db/db_checks = SKIP (avisa).

REGRAS DE SEGURANÇA (missão noturna 2026-07-09):
- Pagamento em teste automático = SEMPRE dinheiro (cash, máx €40). NUNCA confirmar cobrança real.
- NUNCA disparar push a estafetas reais: antes de fluxo [2-DEVICES], verificar (read-only)
  que só o estafeta de teste está online — senão ABORTA o fluxo com PRE-CONDICAO-FALHOU.
- Dados de teste = contas dedicadas; limpeza via limpar-dados-teste.py (por conta de teste).
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time

# Windows: consola cp1252 rebenta com unicode (→, ✅) — forçar utf-8
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent
FLOWS = BASE / "flows"
INBOX = REPO / ".claude" / ".ai" / "knowledge" / "inbox"

sys.path.insert(0, str(BASE))
import importlib.util as _iu
_spec = _iu.spec_from_file_location("cinegrafista", BASE / "cinegrafista.py")
_cine_mod = _iu.module_from_spec(_spec)
_spec.loader.exec_module(_cine_mod)
Cinegrafista = _cine_mod.Cinegrafista

TEST_DRIVER_EMAIL = os.environ.get("E2E_DRIVER_EMAIL", "teste-estafeta@bora.app")
RESET_YAML = "comum/reset-role-screen.yaml"


def _adb_bin() -> str:
    cand = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk/platform-tools/adb.exe"
    if cand.exists():
        return str(cand)
    import shutil
    return shutil.which("adb") or "adb"


def adb_serials() -> list:
    """Serials ligados (estado 'device'). Lista vazia se adb falhar."""
    try:
        out = subprocess.run([_adb_bin(), "devices"], capture_output=True, text=True, timeout=20).stdout or ""
    except Exception:
        return []
    return [l.split("\t")[0] for l in out.splitlines()[1:] if "\tdevice" in l]


def _maestro_bin() -> str:
    cand = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/maestro/maestro/bin/maestro.bat"
    if cand.exists():
        return str(cand)
    import shutil
    exe = shutil.which("maestro") or shutil.which("maestro.bat")
    if exe:
        return exe
    # o loop pode ser lançado por outra conta (ex.: hermes headless) cujo
    # %LOCALAPPDATA% não é o do dono — procura o maestro nos perfis de utilizador.
    users = Path(os.environ.get("SystemDrive", "C:") + "/Users")
    for rel in ("AppData/Local/Programs/maestro/maestro/bin/maestro.bat",
                ".maestro/bin/maestro.bat"):
        for hit in sorted(users.glob(f"*/{rel}")):
            if hit.exists():
                return str(hit)
    raise RuntimeError("maestro não encontrado — reinstala (Fase 2 da missão instalou em %LOCALAPPDATA%\\Programs\\maestro)")


def _load_env() -> dict:
    """SUPABASE_URL/KEY de .env local, fallback backend/.env (só leitura de valores)."""
    env = {}
    for f in [BASE / ".env", REPO / "backend" / ".env"]:
        if f.exists():
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*[\"']?([^\"'#]+)", line)
                if m:
                    env.setdefault(m.group(1), m.group(2).strip())
    url = env.get("SUPABASE_URL") or env.get("SUPABASE_PROJECT_URL")
    key = env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SERVICE_ROLE_KEY") or env.get("SUPABASE_KEY") or env.get("SUPABASE_ANON_KEY")
    return {"url": url, "key": key, "env": env}


DB = _load_env()


def db_get(tabela: str, filtro: str, select: str = "*", limit: int = 5):
    """SELECT read-only via PostgREST. Devolve lista (ou None se sem credenciais)."""
    if not (DB["url"] and DB["key"]):
        return None
    q = f"{DB['url']}/rest/v1/{tabela}?select={urllib.parse.quote(select)}&limit={limit}"
    if filtro:
        q += "&" + filtro
    req = urllib.request.Request(q, headers={"apikey": DB["key"], "Authorization": f"Bearer {DB['key']}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read().decode())


# Contas de DEV do dono (não são estafetas REAIS de produção). A app de driver
# destas contas fica online sozinha via heartbeat e bloqueava o isolamento à toa;
# excluímos por UUID (preciso — nunca mascara um estafeta de terceiro genuíno).
DEV_DRIVER_IDS = {
    "4f61dd31-5e9e-4a7c-a557-7d53d2ceded7",  # Danilo
    "503a2e09-2111-44b5-9852-d6d5897467f1",  # Danilo Fulfaro
    "429efb33-3558-493e-810e-878b73a0b3d1",  # John Doe
    "13db062d-e9f9-4b95-b23a-a87f0b2e8cda",  # Test User
    "ee17553a-65fb-4595-8fd9-540ccc935fd9",  # Test User
}


def so_estafeta_teste_online() -> tuple:
    """Guarda de isolamento: True se APENAS estafetas de teste estão online (read-only)."""
    rows = db_get("drivers", "is_online=eq.true", select="id,email,name", limit=20)
    if rows is None:
        return (None, "sem credenciais DB — verificação de isolamento IMPOSSÍVEL")
    reais = [r for r in rows
             if TEST_DRIVER_EMAIL.split("@")[0] not in str(r.get("email") or "")
             and "teste" not in str(r.get("name") or "").lower()
             and str(r.get("id")) not in DEV_DRIVER_IDS]
    return (len(reais) == 0, f"{len(rows)} online, {len(reais)} reais: {[r.get('email') or r.get('name') for r in reais][:3]}")


def _creds_maestro() -> dict:
    """Credenciais das contas de teste (.env) injetadas em TODOS os flows Maestro.
    Os defaults nos YAML são fallback; a fonte da verdade é o .env (criar-contas-teste.py)."""
    e = DB.get("env", {})
    creds = {}

    def _chunks(pw: str, prefix: str):
        # fix 2026-07-10: obscureText + inputText rápido deixa cair caracteres
        # (Maestro+Flutter, confirmado nos DOIS devices) → digitar em 3 blocos
        # com waitForAnimationToEnd entre eles. Blocos sempre não-vazios.
        n = max(1, len(pw) // 3)
        a, b, c = pw[:n], pw[n:2 * n], pw[2 * n:]
        return {prefix + "_A": a, prefix + "_B": b or a, prefix + "_C": c or (b or a)}

    if e.get("E2E_CLIENT_PASSWORD"):
        creds["CLIENT_EMAIL"] = e.get("E2E_CLIENT_EMAIL", "teste-cliente@bora.app")
        creds["CLIENT_PASSWORD"] = e["E2E_CLIENT_PASSWORD"]
        creds.update(_chunks(e["E2E_CLIENT_PASSWORD"], "CLIENT_PW"))
    if e.get("E2E_DRIVER_PASSWORD"):
        creds["DRIVER_EMAIL"] = e.get("E2E_DRIVER_EMAIL", TEST_DRIVER_EMAIL)
        creds["DRIVER_PASSWORD"] = e["E2E_DRIVER_PASSWORD"]
        creds.update(_chunks(e["E2E_DRIVER_PASSWORD"], "DRIVER_PW"))
    return creds


def corre_maestro(serial: str, yaml_rel: str, env_extra: dict, log_passos: list) -> dict:
    yaml_path = FLOWS / yaml_rel
    cmd = [_maestro_bin(), "--device", serial, "test", str(yaml_path)]
    for k, v in {**_creds_maestro(), **(env_extra or {})}.items():
        cmd += ["--env", f"{k}={v}"]
    # maestro precisa do adb: garantir ANDROID_HOME + platform-tools no PATH
    env_proc = dict(os.environ)
    sdk = Path(os.environ.get("LOCALAPPDATA", "")) / "Android/Sdk"
    env_proc.setdefault("ANDROID_HOME", str(sdk))
    env_proc["PATH"] = f"{sdk / 'platform-tools'};" + env_proc.get("PATH", "")
    # PC com pouca RAM: cap do heap do Maestro (JVM OOM se gradle/analyzer correr em paralelo)
    env_proc.setdefault("JAVA_TOOL_OPTIONS", "-Xmx768m")
    t0 = time.time()
    log_passos.append({"ts": t0, "evento": f"maestro start {yaml_rel} @ {serial}"})
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900, env=env_proc)
    t1 = time.time()
    ok = r.returncode == 0
    # último passo visível no stdout do maestro (para achar o segundo da falha no vídeo)
    tail = "\n".join((r.stdout or "").splitlines()[-25:])
    log_passos.append({"ts": t1, "evento": f"maestro end rc={r.returncode}", "tail": tail})
    return {"ok": ok, "rc": r.returncode, "dur_s": round(t1 - t0, 1), "t_fim": t1, "tail": tail}


def poll_db(passo: dict, contexto: dict, log_passos: list) -> dict:
    t0 = time.time()
    timeout = passo.get("timeout_s", 180)
    tabela, filtro = passo["tabela"], passo.get("filtro", "")
    # janela temporal: só linhas criadas depois do início do fluxo (evita apanhar pedidos velhos)
    inicio_iso = contexto["inicio_iso"]
    filtro_full = (filtro + "&" if filtro else "") + f"created_at=gte.{inicio_iso}&order=created_at.desc"
    while time.time() - t0 < timeout:
        try:
            rows = db_get(tabela, filtro_full, limit=3)
        except Exception as e:
            rows = None
            log_passos.append({"ts": time.time(), "evento": f"poll_db erro: {e}"})
        if rows is None:
            return {"ok": None, "skip": "sem credenciais DB"}
        if rows:
            if passo.get("guarda"):
                contexto[passo["guarda"]] = rows[0]
            log_passos.append({"ts": time.time(), "evento": f"poll_db OK {tabela} ({len(rows)})"})
            return {"ok": True, "row": {k: rows[0].get(k) for k in list(rows[0])[:8]}}
        time.sleep(6)
    log_passos.append({"ts": time.time(), "evento": f"poll_db TIMEOUT {tabela} {filtro}"})
    return {"ok": False, "erro": f"timeout {timeout}s à espera de {tabela}?{filtro}"}


def corre_fluxo(fluxo: dict, devices: dict, single: bool = True, logout_map: dict = None) -> dict:
    fid = fluxo["id"]
    print(f"\n=== FLUXO {fid} ===")

    # fluxos que EXIGEM 2 devices em tempo real (ex.: TVDE com localização ao vivo):
    # em single-device NÃO correm — marcados para execução manual, não bloqueiam a noite.
    if fluxo.get("manual_2_devices") and (single or not fluxo.get("passos")):
        print("  → MANUAL-2-DEVICES (exige 2 telemóveis em tempo real — não corrido)")
        return {"id": fid, "estado": "MANUAL-2-DEVICES", "passos": [], "videos": [], "dur_s": 0,
                "nota": "exige 2 devices em tempo real; correr manualmente com --two-devices"}

    cine = Cinegrafista()
    log_passos = []
    contexto = {"inicio_iso": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S")}
    resultado = {"id": fid, "estado": "PASSOU", "passos": [], "videos": [], "inicio": time.time()}

    # guarda de isolamento para fluxos 2-devices
    if fluxo.get("dois_devices"):
        ok_iso, detalhe = so_estafeta_teste_online()
        if ok_iso is False:
            resultado["estado"] = "PRE-CONDICAO-FALHOU"
            resultado["erro"] = f"estafetas REAIS online — não disparo dispatch de teste ({detalhe})"
            print("  ABORTADO:", resultado["erro"])
            return resultado
        if ok_iso is None:
            resultado["avisos"] = [f"isolamento não verificável: {detalhe}"]

    serials_usados = set()
    papel_atual = None  # último papel a usar o telemóvel (single-device)
    try:
        # SINGLE-DEVICE: normalizar o telemóvel para o RoleScreen antes do fluxo
        if single:
            primeiro = next((p for p in fluxo.get("passos", []) if p["tipo"] == "maestro"), None)
            if primeiro:
                serial0 = devices[primeiro["device"]]
                mp4 = cine.start(serial0, fid)
                resultado["videos"].append(mp4)
                serials_usados.add(serial0)
                r0 = corre_maestro(serial0, RESET_YAML, {}, log_passos)
                resultado["passos"].append({"tipo": "reset", "yaml": RESET_YAML,
                                            **{k: r0[k] for k in ("ok", "rc", "dur_s")}})
                if not r0["ok"]:
                    resultado["estado"] = "FALHOU"
                    resultado["falha"] = {"yaml": RESET_YAML, "serial": serial0,
                                          "t_epoch": r0["t_fim"], "tail": r0["tail"][-1200:]}

        for passo in (fluxo["passos"] if resultado["estado"] == "PASSOU" else []):
            if passo["tipo"] == "maestro":
                serial = devices[passo["device"]]
                if serial not in serials_usados:
                    mp4 = cine.start(serial, fid)
                    resultado["videos"].append(mp4)
                    serials_usados.add(serial)
                # SINGLE-DEVICE: mudou o papel → logout do papel anterior no MESMO telemóvel
                # (o YAML do novo passo começa pelo login.yaml do novo papel)
                if single and papel_atual and papel_atual != passo["device"]:
                    ly = (logout_map or {}).get(papel_atual)
                    if ly:
                        r_lo = corre_maestro(serial, ly, {}, log_passos)
                        resultado["passos"].append({"tipo": "logout", "yaml": ly,
                                                    **{k: r_lo[k] for k in ("ok", "rc", "dur_s")}})
                        if not r_lo["ok"]:
                            resultado["estado"] = "FALHOU"
                            resultado["falha"] = {"yaml": ly, "serial": serial,
                                                  "t_epoch": r_lo["t_fim"], "tail": r_lo["tail"][-1200:]}
                            break
                papel_atual = passo["device"]
                env_extra = {}
                for k, campo in (passo.get("env_de_db") or {}).items():
                    row = contexto.get("order") or {}
                    env_extra[k] = str(row.get(campo, ""))
                r = corre_maestro(serial, passo["yaml"], env_extra, log_passos)
                resultado["passos"].append({"tipo": "maestro", "yaml": passo["yaml"], **{k: r[k] for k in ("ok", "rc", "dur_s")}})
                if not r["ok"]:
                    resultado["estado"] = "FALHOU"
                    resultado["falha"] = {"yaml": passo["yaml"], "serial": serial, "t_epoch": r["t_fim"], "tail": r["tail"][-1200:]}
                    break
            elif passo["tipo"] == "poll_db":
                r = poll_db(passo, contexto, log_passos)
                resultado["passos"].append({"tipo": "poll_db", "tabela": passo["tabela"], "ok": r.get("ok"), "detalhe": r.get("erro") or r.get("skip") or ""})
                if r.get("ok") is False:
                    resultado["estado"] = "FALHOU"
                    resultado["falha"] = {"poll_db": passo["tabela"], "t_epoch": time.time(), "erro": r.get("erro")}
                    break
    finally:
        cine.stop_all()

    # frames automáticos na falha
    if resultado["estado"] == "FALHOU" and resultado["videos"]:
        try:
            t_falha = resultado["falha"]["t_epoch"]
            for mp4 in resultado["videos"]:
                sidecar = Path(mp4).with_suffix(".json")
                if sidecar.exists():
                    ini = json.loads(sidecar.read_text(encoding="utf-8"))["inicio_epoch"]
                    seg = max(1.0, t_falha - ini)
                    subprocess.run([sys.executable, str(BASE / "extrair-frames.py"), "--video", mp4, "--segundo", f"{seg:.1f}"], capture_output=True, timeout=120)
            resultado["frames"] = str(BASE / "frames")
        except Exception as e:
            resultado["frames_erro"] = str(e)

    # db_checks finais (read-only)
    for chk in fluxo.get("db_checks", []):
        try:
            rows = db_get(chk["tabela"], (chk.get("filtro", "") + "&" if chk.get("filtro") else "") + f"created_at=gte.{contexto['inicio_iso']}")
        except Exception as e:
            rows = None
        ok = None if rows is None else len(rows) >= chk.get("espera_min", 1)
        resultado.setdefault("db_checks", []).append({"nome": chk["nome"], "ok": ok})
        if ok is False and resultado["estado"] == "PASSOU":
            resultado["estado"] = "FALHOU-DB-CHECK"

    resultado["log"] = log_passos
    resultado["dur_s"] = round(time.time() - resultado.pop("inicio"), 1)
    print(f"  → {resultado['estado']} ({resultado['dur_s']}s)")
    return resultado


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--fluxo")
    g.add_argument("--todos", action="store_true")
    g.add_argument("--so-falhados", action="store_true")
    ap.add_argument("--single-device", action="store_true",
                    help="(DEFAULT) tudo sequencial no mesmo telemóvel")
    ap.add_argument("--two-devices", action="store_true",
                    help="modo antigo: cada papel no seu telemóvel (registry devices)")
    args = ap.parse_args()
    single = not args.two_devices  # single-device é o PADRÃO

    reg = json.loads((FLOWS / "registry.json").read_text(encoding="utf-8"))
    fluxos = reg["fluxos"]
    if args.fluxo:
        fluxos = [f for f in fluxos if f["id"] == args.fluxo]
        if not fluxos:
            print(f"fluxo '{args.fluxo}' não existe no registry"); sys.exit(2)
    elif args.so_falhados:
        prev = sorted(glob.glob(str(BASE / "resultados-*.json")))
        if prev:
            ultimos = json.loads(Path(prev[-1]).read_text(encoding="utf-8"))
            falhados = {r["id"] for r in ultimos.get("resultados", [])
                        if r["estado"] not in ("PASSOU", "MANUAL-2-DEVICES")}
            fluxos = [f for f in fluxos if f["id"] in falhados]
        print(f"a re-correr {len(fluxos)} falhados")

    if not (DB["url"] and DB["key"]):
        print("AVISO: sem SUPABASE_URL/KEY (.env) — poll_db/db_checks/isolamento em SKIP")

    # mapa papel→serial: single-device = tudo no mesmo telemóvel (auto-detectado)
    if single:
        ligados = adb_serials()
        if not ligados:
            print("ERRO: nenhum telemóvel no adb — liga o telemóvel e volta a correr (run-tudo.cmd)")
            sys.exit(3)
        pref = reg["devices"].get("cliente")
        serial = pref if pref in ligados else ligados[0]
        devices = {papel: serial for papel in reg["devices"]}
        print(f"[single-device] todos os papéis em {serial}")
    else:
        devices = reg["devices"]

    logout_map = reg.get("logout_flows", {})
    resultados = [corre_fluxo(f, devices, single=single, logout_map=logout_map) for f in fluxos]
    dia = datetime.now().strftime("%Y-%m-%d")
    out = {"data": datetime.now().isoformat(timespec="seconds"), "resultados": resultados}
    out_json = BASE / f"resultados-{dia}.json"
    out_json.write_text(json.dumps(out, indent=2, ensure_ascii=False, default=str), encoding="utf-8")

    verdes = sum(1 for r in resultados if r["estado"] == "PASSOU")
    linhas = [f"---", f"id: e2e-resultados-{dia}", f"tipo: relatorio", f"origem: [runner E2E testes-e2e]",
              f"ultima_confirmacao: {dia}", f"zona: verde", f"confianca: auto", f"---", "",
              f"# E2E — {dia}: {verdes}/{len(resultados)} verdes", ""]
    for r in resultados:
        icon = "✅" if r["estado"] == "PASSOU" else ("📱📱" if r["estado"] == "MANUAL-2-DEVICES" else "❌")
        linhas.append(f"- {icon} **{r['id']}** — {r['estado']} ({r.get('dur_s','?')}s)" +
                      (f" · falha: `{json.dumps(r.get('falha',{}), ensure_ascii=False)[:180]}`" if r["estado"].startswith("FALHOU") else ""))
    INBOX.mkdir(parents=True, exist_ok=True)
    (INBOX / f"e2e-resultados-{dia}.md").write_text("\n".join(linhas) + "\n", encoding="utf-8")
    print(f"\n{verdes}/{len(resultados)} verdes → {out_json.name} + inbox/e2e-resultados-{dia}.md")
    sys.exit(0 if all(r["estado"] in ("PASSOU", "MANUAL-2-DEVICES") for r in resultados) else 1)


if __name__ == "__main__":
    main()
