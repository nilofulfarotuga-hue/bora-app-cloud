# -*- coding: utf-8 -*-
"""Hermes/Emerson e OmniRoute com o porteiro do Claude a frente (missao motor-claude 31/10/2026).

Hermes (/opt/data/config.yaml): modelo principal = Motor Bora perfil:claude-decisao (Sonnet 5.5 pelo porteiro, P2;
  sem credito/parte do dia -> rotacao gratis do proprio Motor). fallback_providers: sai opencode-go e opencode-zen
  (mortos: 401 e so dentro do programa OpenCode) e o gemini-3.6-flash (chave do Hermes em 402) -> lista vazia, igual
  aos perfis (o Motor ja roda os gratis por dentro).
Perfis (/opt/data/profiles/*/config.yaml): perfil:raciocinio -> perfil:claude-agente (Haiku 5.5, P3);
  torre e critico (decisoes) -> Motor Bora perfil:claude-decisao; batedor e vendedor -> Motor Bora perfil:claude-agente.
OmniRoute (/opt/omniroute/or_combos.py): agentes e privado com motor/perfil:claude-decisao a frente; rapido e volume
  com motor/perfil:claude-volume (Haiku) a frente. Depois corre-se `python3 or_combos.py` (PUT /api/combos).
Copias com .bak-claude-20261031 ao lado. --repor repoe os ficheiros (os combos repoem-se correndo or_combos.py da copia).
NAO reinicia o gateway (faz-se a parte, com prova).
"""
import glob
import os
import re
import shutil
import sys

SUF = ".bak-claude-20261031"
CFG = "/opt/data/config.yaml"
PERFIS = sorted(glob.glob("/opt/data/profiles/*/config.yaml"))
COMBOS = "/opt/omniroute/or_combos.py"
TODOS = [CFG, COMBOS] + PERFIS
MOTOR_URL = "http://172.16.1.1:8792/v1"

if "--repor" in sys.argv:
    for p in TODOS:
        if os.path.exists(p + SUF):
            shutil.copy2(p + SUF, p)
            print("reposto", p)
    sys.exit(0)

for p in TODOS:
    if not os.path.exists(p + SUF):
        shutil.copy2(p, p + SUF)       # copy2 guarda dono/permissoes do conteudo; o dono do ficheiro novo e root
        st = os.stat(p)
        os.chown(p + SUF, st.st_uid, st.st_gid)


def gravar(p, t):
    st = os.stat(p)
    with open(p + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(t)
    os.chown(p + ".tmp", st.st_uid, st.st_gid)
    os.chmod(p + ".tmp", st.st_mode & 0o777)
    os.replace(p + ".tmp", p)


BLOCO_OMNI = re.compile(r"(?m)^model:\n  default: (agentes|privado|rapido|volume)\n  provider: custom\n  base_url: http://omniroute:20128/v1\n  api_key: \$\{OMNIROUTE_API_KEY\}\n")

# 1. config principal do Hermes
t = open(CFG, encoding="utf-8").read()
if "perfil:claude-decisao" not in t:
    t2, n = BLOCO_OMNI.subn("model:\n  default: perfil:claude-decisao\n  provider: custom\n  base_url: %s\n" % MOTOR_URL, t, count=1)
    if n != 1:
        raise SystemExit("bloco model: do config.yaml nao encontrado - nada gravado")
    i = t2.index("\nfallback_providers:\n")
    j = i + len("\nfallback_providers:\n")
    while t2[j:].startswith("- provider:") or t2[j:].startswith("  model:"):
        j = t2.index("\n", j) + 1
    t2 = t2[:i] + "\n# 31/10/2026 (missao motor-claude): opencode-go/zen (mortos) e gemini 402 tirados; o Motor Bora roda os gratis\nfallback_providers: []\n" + t2[j:]
    gravar(CFG, t2)
    print("config.yaml: modelo -> Motor Bora perfil:claude-decisao; fallback_providers -> []")
else:
    print("config.yaml: ja aplicado")

# 2. perfis
for p in PERFIS:
    nome = p.split("/")[-2]
    t = open(p, encoding="utf-8").read()
    alvo = "perfil:claude-decisao" if nome in ("torre", "critico") else "perfil:claude-agente"
    novo = t
    if "default: perfil:raciocinio" in novo:
        novo = novo.replace("default: perfil:raciocinio", "default: " + alvo, 1)
    novo, n = BLOCO_OMNI.subn("model:\n  default: %s\n  provider: custom\n  base_url: %s\n" % (alvo, MOTOR_URL), novo, count=1)
    if novo != t:
        gravar(p, novo)
        print("perfil %-18s -> %s" % (nome, alvo))
    else:
        print("perfil %-18s sem bloco de modelo reconhecido (fica como esta)" % nome)

# 3. combos do OmniRoute
t = open(COMBOS, encoding="utf-8").read()
if "perfil:claude-" not in t:
    for combo, perfil in (("agentes", "claude-decisao"), ("privado", "claude-decisao"), ("rapido", "claude-volume"), ("volume", "claude-volume")):
        i = t.index('"%s": {' % combo)
        j = t.index('"models": [', i) + len('"models": [')
        t = t[:j] + ('\n            # 31/10/2026 (missao motor-claude): porteiro do Claude a frente (Claude enquanto houver credito, senao gratis)'
                     '\n            MOTOR + "perfil:%s",' % perfil) + t[j:]
    gravar(COMBOS, t)
    print("or_combos.py: Motor Bora (porteiro) a frente de agentes, privado, rapido, volume")
else:
    print("or_combos.py: ja aplicado")
