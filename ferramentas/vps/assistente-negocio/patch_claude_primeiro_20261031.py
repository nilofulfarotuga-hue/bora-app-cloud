# -*- coding: utf-8 -*-
"""Assistente de negocio (WhatsApp das lojas): Claude primeiro pelo porteiro do Motor Bora (31/10/2026).

- fornecedor novo `porteiro` = Motor Bora local (127.0.0.1:8792); o porteiro decide Claude ou gratis
- toda a cadeia passa a comecar por porteiro:perfil:claude-cliente (CLAUDE_PRIMEIRO=0 no .env desliga)
- classificador: porteiro:perfil:claude-classificar (Haiku 5.5) e depois groq
- timeout 45 s -> 20 s (porteiro 30 s: Claude ate 20 s + gratis) e sem repetir em timeout
- _castigar passa a tratar 401/402/404 (go: e gemini2: deixam de ser tentados em todas as mensagens)
Correr na VPS como root:  python3 patch_claude_primeiro_20261031.py   |   --repor
"""
import os
import py_compile
import shutil
import sys

MOT = "/opt/assistente-negocio/motores.py"
ASS = "/opt/assistente-negocio/assistente.py"
SUF = ".bak-claude-20261031"
MARCA = "missao motor-claude"


def ler(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def gravar(p, t):
    with open(p + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(t)
    os.replace(p + ".tmp", p)


def trocar(t, velho, novo, nome):
    if t.count(velho) != 1:
        raise SystemExit("ANCORA %s encontrada %d vezes - nada gravado" % (nome, t.count(velho)))
    return t.replace(velho, novo)


if "--repor" in sys.argv:
    for p in (MOT, ASS):
        if os.path.exists(p + SUF):
            shutil.copy2(p + SUF, p)
            print("reposto", p)
    sys.exit(0)

for p in (MOT, ASS):
    if not os.path.exists(p + SUF):
        shutil.copy2(p, p + SUF)
        print("copia", p + SUF)

m = ler(MOT)
if MARCA not in m:
    m = trocar(m, '''    "groq": {"url": "https://api.groq.com/openai/v1/chat/completions", "chave": "GROQ_API_KEY", "pago": False},
}''', '''    "groq": {"url": "https://api.groq.com/openai/v1/chat/completions", "chave": "GROQ_API_KEY", "pago": False},
    # 31/10/2026 (missao motor-claude): o Motor Bora local com o PORTEIRO do credito do Claude.
    # porteiro:perfil:claude-cliente -> Claude Sonnet 5.5 enquanto houver credito, senao a rotacao gratis.
    # O credito e do plano do Danilo, nao do cliente: custo 0 para o orcamento do tenant (vai para ia_gastos).
    "porteiro": {"url": "http://127.0.0.1:8792/v1/chat/completions", "chave": None, "pago": False, "porteiro": True,
                 "cabecalhos": {"X-Motor-Origem": "assistente-negocio"}},
}

CLAUDE_PRIMEIRO = os.environ.get("CLAUDE_PRIMEIRO", "1") != "0"
MORTOS = ("go", "gemini2")     # 29/10: go 401 (chave expirada), gemini2 402 (sem creditos)''', "fornecedores")
    m = trocar(m, '''    elif "sem chave" in erro:
        seg = 3600
''', '''    elif "sem chave" in erro:
        seg = 3600
    elif "HTTP 401" in erro or "HTTP 402" in erro or "HTTP 404" in erro:
        seg = 6 * 3600      # 31/10: chave expirada / sem creditos / modelo morto -- nao insistir a cada mensagem
''', "castigar")
    m = trocar(m, "def _chamar(motor, mensagens, ferramentas, timeout=45):", "def _chamar(motor, mensagens, ferramentas, timeout=20):", "timeout")
    m = trocar(m, '''    chave = os.environ.get(f["chave"], "").strip()
    if not chave:''', '''    chave = "motor-bora-local" if f.get("porteiro") else os.environ.get(f["chave"], "").strip()
    if f.get("porteiro"):
        timeout = max(timeout, 30)      # Claude ate 20 s + rotacao gratis
    if not chave:''', "chave")
    m = trocar(m, '''    return j["choices"][0]["message"], {"motor": motor, "tokens_in": tin, "tokens_out": tout,
                                        "custo_eur": custo, "ms": ms, "pago": bool(f.get("pago"))}''', '''    meta = {"motor": motor, "tokens_in": tin, "tokens_out": tout, "custo_eur": custo, "ms": ms, "pago": bool(f.get("pago"))}
    if f.get("porteiro"):
        # quem respondeu de facto (claude:claude-sonnet-5-5 ou groq:...), o que o porteiro decidiu e o custo do credito
        meta["motor"] = j.get("model") or motor
        meta["via"] = motor
        meta["custo_usd_claude"] = float(uso.get("custo_usd") or 0)
        mot = j.get("motor") or {}
        meta["porteiro"] = mot.get("porteiro") or next((t.get("porteiro") for t in (mot.get("tentativas") or []) if isinstance(t, dict) and t.get("porteiro")), None)
    return j["choices"][0]["message"], meta''', "meta")
    m = trocar(m, '''    falhas = []
    for motor in cadeia:
        forn = motor.split(":", 1)[0]''', '''    falhas = []
    cadeia = list(cadeia or [])
    if CLAUDE_PRIMEIRO and not any(str(c).startswith("porteiro:") for c in cadeia):
        cadeia.insert(0, "porteiro:perfil:claude-cliente")
    for motor in cadeia:
        forn = motor.split(":", 1)[0]
        if forn in MORTOS:
            falhas.append(f"{motor}: fornecedor morto (29/10)")
            continue''', "conversar")
    m = trocar(m, '''                if tentativa == 0 and ("HTTP 503" in txt or "HTTP 500" in txt or "timeout" in txt.lower()):''',
               '''                # 31/10: so se repete em 500/503 rapidos; em timeout NAO (o cliente ficava ate ~90 s a espera)
                if tentativa == 0 and ("HTTP 503" in txt or "HTTP 500" in txt) and "timeout" not in txt.lower():''', "repeticao")
    m = m.replace('"""Motores do Assistente de Negocio', '"""[31/10/2026 missao motor-claude: porteiro do Claude a frente]\nMotores do Assistente de Negocio', 1)
    gravar(MOT, m)
    print("motores.py: porteiro, timeout 20 s sem repetir, castigo 401/402/404")
else:
    print("motores.py: ja aplicado")

a = ler(ASS)
if MARCA not in a:
    a = trocar(a, '''        msg, meta = motores.conversar(["groq:openai/gpt-oss-20b", "groq:qwen/qwen3.8-27b",
                                       "gemini:gemini-3.1-flash-lite"], msgs)''', '''        # 31/10/2026 (missao motor-claude): Claude Haiku 5.5 pelo porteiro (P1, so enquanto houver credito), depois groq.
        msg, meta = motores.conversar(["porteiro:perfil:claude-classificar", "groq:openai/gpt-oss-20b", "groq:qwen/qwen3.8-27b",
                                       "groq:openai/gpt-oss-120b", "gemini:gemini-3.1-flash-lite"], msgs)''', "classificar")
    gravar(ASS, a)
    print("assistente.py: classificador com Haiku 5.5 a frente")
else:
    print("assistente.py: ja aplicado")

for p in (MOT, ASS):
    py_compile.compile(p, doraise=True)
print("py_compile OK")
