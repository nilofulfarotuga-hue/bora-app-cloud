# -*- coding: utf-8 -*-
"""Aplica o porteiro do credito do Claude ao Motor Bora (missao motor-claude 31/10/2026).

Correr na VPS como root, com o porteiro.py ja copiado para /tmp/porteiro.py:
    python3 patch_porteiro_20261031.py            # aplica (com copias .bak-porteiro-20261031 ao lado)
    python3 patch_porteiro_20261031.py --repor    # repoe as copias
Idempotente: se ja estiver aplicado, nao repete. NAO reinicia o servico (isso faz-se a parte, com prova).
"""
import os
import py_compile
import re
import shutil
import sys

BASE = "/opt/motor-bora"
CAT = BASE + "/motor_bora/catalogo.py"
ROT = BASE + "/motor_bora/roteador.py"
SRV = BASE + "/servidor_motor.py"
POR = BASE + "/motor_bora/porteiro.py"
SUF = ".bak-porteiro-20261031"
MARCA = "missao motor-claude"


def ler(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def gravar(p, t):
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(t)
    os.replace(tmp, p)


def trocar(t, velho, novo, nome):
    if t.count(velho) != 1:
        raise SystemExit("ANCORA %s encontrada %d vezes (esperava 1) - nada gravado" % (nome, t.count(velho)))
    return t.replace(velho, novo)


if "--repor" in sys.argv:
    for p in (CAT, ROT, SRV):
        if os.path.exists(p + SUF):
            shutil.copy2(p + SUF, p)
            print("reposto", p)
    if os.path.exists(POR):
        os.remove(POR)
        print("removido", POR)
    sys.exit(0)

for p in (CAT, ROT, SRV):
    if not os.path.exists(p + SUF):
        shutil.copy2(p, p + SUF)
        print("copia", p + SUF)

shutil.copy2("/tmp/porteiro.py", POR)
print("porteiro.py ->", POR)

# 1. catalogo: tirar os mortos (go, zen por API, ollama local) e criar os perfis claude-*
cat = ler(CAT)
if MARCA not in cat:
    i = cat.index("PERFIS = {")
    j = cat.index("PERGUNTAS_TESTE", i) if "PERGUNTAS_TESTE" in cat[i:] else len(cat)
    bloco = cat[i:j]
    novo_bloco, n = re.subn(r'\(\s*"(?:go|zen|ollama|gemini2)"\s*,\s*"[^"]*"\s*\)\s*,?[ \t]*', "", bloco)
    cat = cat[:i] + novo_bloco + cat[j:]
    cat += '''

# ---------------------------------------------------------------------------------------------------
# 31/10/2026 (missao motor-claude): perfis com o PORTEIRO do credito do Claude a frente (porteiro.py).
# O roteador pergunta ao porteiro primeiro; se ele disser "gratis" (sem chave, sem credito, parte do dia
# esgotada, erro ou mais de 20 s) desce esta cadeia gratis. Ordem gratis medida a 29/10 (pagina
# motores-rotacao-2026-10-29). Mortos retirados de todos os perfis: go (401), zen por API (429), ollama.
_GRATIS_VIVOS = [("groq", "openai/gpt-oss-120b"), ("gemini", "gemini-3.1-flash-lite"), ("groq", "qwen/qwen3.8-27b"),
                 ("gemini", "gemini-3.5-flash-lite"), ("groq", "openai/gpt-oss-20b"), ("gemini", "gemini-3-flash-preview")]


def _com_resto(base):
    return list(_GRATIS_VIVOS) + [x for x in (PERFIS.get(base) or {}).get("candidatos", []) if x not in _GRATIS_VIVOS]


PERFIS["claude-cliente"] = dict(PERFIS["chat-rapido"], modo="cadeia", orcamento=25, max_tokens=600, candidatos=_com_resto("chat-rapido"))
PERFIS["claude-classificar"] = dict(PERFIS["chat-rapido"], modo="cadeia", max_tokens=60, candidatos=[
    ("groq", "openai/gpt-oss-20b"), ("groq", "qwen/qwen3.8-27b"), ("groq", "openai/gpt-oss-120b"), ("gemini", "gemini-3.1-flash-lite")])
PERFIS["claude-decisao"] = dict(PERFIS["raciocinio"], modo="cadeia", candidatos=_com_resto("raciocinio"))
PERFIS["claude-agente"] = dict(PERFIS["raciocinio"], modo="cadeia", candidatos=_com_resto("raciocinio"))
PERFIS["claude-volume"] = dict(PERFIS["volume"], candidatos=_com_resto("volume"))
PRECO_POR_MILHAO["claude"] = 2.0   # so para o custo estimado do motor_chamadas; o custo real esta em ia_gastos
'''
    gravar(CAT, cat)
    print("catalogo: %d candidatos mortos tirados; perfis claude-* criados" % n)
else:
    print("catalogo: ja aplicado")

# 2. roteador: o porteiro decide primeiro nos perfis claude-*
rot = ler(ROT)
if MARCA not in rot:
    rot = trocar(rot, '''        p = C.PERFIS.get(perfil or "chat-rapido")
''', '''        p = C.PERFIS.get(perfil or "chat-rapido")
        # 31/10/2026 (missao motor-claude): o PORTEIRO do credito decide primeiro se vai ao Claude.
        # None = rotacao gratis abaixo, sem erro para ninguem. O porteiro nunca pode partir o motor.
        info_porteiro = None
        if getattr(self, "porteiro", None) is not None and (perfil or "").startswith("claude-"):
            try:
                r_cl, info_porteiro = self.porteiro.tentar(perfil, mensagens, tools, max_tokens, origem)
            except Exception as e:  # noqa: BLE001
                r_cl, info_porteiro = None, {"decisao": "gratis", "porque": "erro no porteiro: %s" % str(e)[:160]}
            if r_cl is not None:
                tok = int((r_cl.get("usage") or {}).get("total_tokens") or 0)
                self._registar_chamada(perfil, "claude", info_porteiro.get("modelo"), True, info_porteiro.get("ms") or 0, tok, None, origem)
                r_cl["motor"].update(maquina=self.maquina, tentativas=[])
                return r_cl
''', "perfil")
    rot = trocar(rot, '''        t_ini = time.time()
        tentativas = []
        falhas_seguidas = 0
''', '''        t_ini = time.time()
        tentativas = [{"porteiro": info_porteiro}] if info_porteiro else []
        falhas_seguidas = 0
''', "tentativas")
    gravar(ROT, rot)
    print("roteador: porteiro ligado")
else:
    print("roteador: ja aplicado")

# 3. servidor: chave em /opt/segredos/claude.env, porteiro, /porteiro e laco de fundo
srv = ler(SRV)
if MARCA not in srv:
    srv = trocar(srv, 'ENV_FILES = [os.path.join(AQUI, ".env"),', 'ENV_FILES = ["/opt/segredos/claude.env", os.path.join(AQUI, ".env"),', "env")
    srv = trocar(srv, '''R = Roteador(ler_env(), maquina=MAQUINA, estado_path=ESTADO, avisar=avisar, registar=registar, supa=SUPA)
''', '''R = Roteador(ler_env(), maquina=MAQUINA, estado_path=ESTADO, avisar=avisar, registar=registar, supa=SUPA)
# 31/10/2026 (missao motor-claude): porteiro do credito do Claude (Claude primeiro, gratis depois)
from motor_bora.porteiro import Porteiro  # noqa: E402
R.porteiro = Porteiro(R.env, AQUI, registar=registar, supa=SUPA)
''', "R")
    srv = trocar(srv, '''        if p in ("/v1/models", "/models"):
''', '''        if p == "/porteiro":
            return self._json(200, R.porteiro.estado())
        if p in ("/v1/models", "/models"):
''', "models")
    srv = trocar(srv, '''            if p == "/pausar":
''', '''            if p == "/porteiro/simular":
                # so para provas: muda a MEMORIA do porteiro, nada na Console. Um reinicio repoe tudo.
                if "sem_saldo" in d:
                    R.porteiro.simular["sem_saldo"] = bool(d["sem_saldo"])
                if "gasto_hoje_extra_usd" in d:
                    R.porteiro.simular["gasto_hoje_extra_usd"] = float(d["gasto_hoje_extra_usd"] or 0)
                registar({"evento": "porteiro-simular", "simular": dict(R.porteiro.simular)})
                return self._json(200, {"ok": True, "simular": R.porteiro.simular, "decisoes": R.porteiro.estado()["decisoes"]})
            if p == "/porteiro/recarregar":
                R.porteiro.recarregar_config(d.get("config") if isinstance(d.get("config"), dict) else None)
                return self._json(200, {"ok": True, "contas": R.porteiro.contas()})
            if p == "/pausar":
''', "pausar")
    srv = trocar(srv, '''            if agora - ultimo_md > 600:
''', '''            if agora - getattr(R.porteiro, "_ult_sync", 0) > 60:      # livro de gastos -> ia_gastos
                R.porteiro._ult_sync = agora
                R.porteiro.sincronizar()
            if agora - getattr(R.porteiro, "_ult_painel", 0) > 600:   # painel (platform_settings claude_*)
                R.porteiro._ult_painel = agora
                R.porteiro.ler_painel()
            if agora - getattr(R.porteiro, "_ult_acordar", 0) > 3600:  # dia do credito novo: volta sozinho
                R.porteiro._ult_acordar = agora
                R.porteiro.talvez_acordar()
            if agora - ultimo_md > 600:
''', "laco")
    srv = srv.replace('"""servidor_motor.py', '"""servidor_motor.py  [31/10/2026 missao motor-claude: porteiro do Claude]', 1)
    gravar(SRV, srv)
    print("servidor: porteiro, /porteiro e laco de fundo ligados")
else:
    print("servidor: ja aplicado")

for p in (CAT, ROT, SRV, POR):
    py_compile.compile(p, doraise=True)
print("py_compile OK nos 4 ficheiros")
