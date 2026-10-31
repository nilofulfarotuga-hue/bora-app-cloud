# -*- coding: utf-8 -*-
"""Cerebro do WhatsApp da Bora: Claude a frente pelo porteiro do Motor Bora (31/10/2026).
- modelos.py: os perfis pedidos ao Motor passam a claude-* (chat-rapido -> claude-cliente, raciocinio -> claude-agente,
  volume -> claude-volume); CLAUDE_PRIMEIRO=0 no ambiente desliga. Timeouts dao para Claude (20 s) + gratis.
- cadeia.txt (cadeia directa, so quando o Motor cai): sai ollama e zen:nemotron-3-ultra-free (mortos a 29/10).
O ENVIO do WhatsApp nao muda (continua desligado em whatsapp_settings.envio_ligado).
Correr na VPS como root:  python3 patch_cerebro_claude_20261031.py   |   --repor
"""
import os
import py_compile
import shutil
import sys

MOD = "/opt/whatsapp-bora/cerebro/modelos.py"
CAD = "/opt/whatsapp-bora/cerebro/cadeia.txt"
SUF = ".bak-claude-20261031"
MARCA = "missao motor-claude"

if "--repor" in sys.argv:
    for p in (MOD, CAD):
        if os.path.exists(p + SUF):
            shutil.copy2(p + SUF, p)
            print("reposto", p)
    sys.exit(0)

for p in (MOD, CAD):
    if not os.path.exists(p + SUF):
        shutil.copy2(p, p + SUF)
        print("copia", p + SUF)

t = open(MOD, encoding="utf-8").read()
if MARCA not in t:
    velho = 'TIMEOUT_PERFIL = {"chat-rapido": 18, "raciocinio": 75, "volume": 90, "visao": 40}\n'
    if t.count(velho) != 1:
        raise SystemExit("ancora TIMEOUT_PERFIL nao encontrada")
    t = t.replace(velho, velho + '''# 31/10/2026 (missao motor-claude): Claude primeiro pelo PORTEIRO do Motor Bora (credito da API do plano do Danilo);
# sem credito/parte do dia/erro, o proprio Motor desce a rotacao gratis. CLAUDE_PRIMEIRO=0 volta ao antigo.
CLAUDE_PRIMEIRO = os.environ.get("CLAUDE_PRIMEIRO", "1") != "0"
PERFIL_CLAUDE = {"chat-rapido": "claude-cliente", "raciocinio": "claude-agente", "volume": "claude-volume"}
TIMEOUT_PERFIL.update({"claude-cliente": 45, "claude-agente": 90, "claude-volume": 100})
''')
    velho2 = '    corpo = {"model": "perfil:" + perfil, "messages": mensagens, "max_tokens": max_tokens, "temperature": temperatura, "stream": False}\n'
    if t.count(velho2) != 1:
        raise SystemExit("ancora corpo nao encontrada")
    t = t.replace(velho2, '    if CLAUDE_PRIMEIRO:\n        perfil = PERFIL_CLAUDE.get(perfil, perfil)\n' + velho2)
    with open(MOD + ".tmp", "w", encoding="utf-8") as fh:
        fh.write(t)
    os.replace(MOD + ".tmp", MOD)
    print("modelos.py: perfis claude-* pelo Motor Bora")
else:
    print("modelos.py: ja aplicado")

c = open(CAD, encoding="utf-8").read().strip()
partes = [x.strip() for x in c.split(",") if x.strip()]
vivos = [x for x in partes if x != "ollama" and not x.startswith("zen:")]
if vivos != partes:
    with open(CAD, "w", encoding="utf-8") as fh:
        fh.write(",".join(vivos) + "\n")
    print("cadeia.txt:", ",".join(vivos))
else:
    print("cadeia.txt: ja sem mortos")
py_compile.compile(MOD, doraise=True)
print("py_compile OK")
