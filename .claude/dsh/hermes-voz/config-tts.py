#!/usr/bin/env python3
# config-tts.py — poe o TTS do agente do Hermes a falar pelo servidor de voz do host (tts.provider: voz, tipo comando).
# Copia de seguranca primeiro; validacao do YAML depois (e repoe se falhar).
import re, shutil, subprocess, sys

F = "/opt/data/config.yaml"
BAK = F + ".bak-voz-20261030"
txt = open(F, encoding="utf-8").read()
if "voz_cmd.py" in txt:
    print("JA FEITO")
    sys.exit(0)
shutil.copy2(F, BAK)
ls = txt.split("\n")
ini = next(i for i, l in enumerate(ls) if re.match(r"^tts:\s*$", l))
fim = next((i for i in range(ini + 1, len(ls)) if re.match(r"^\S", ls[i])), len(ls))
bloco = ls[ini:fim]
if not any(re.match(r"^  provider: edge\s*$", l) for l in bloco):
    print("tts.provider nao e edge; nada mudado"); sys.exit(1)
novo = []
for l in bloco:
    if re.match(r"^  provider: edge\s*$", l):
        novo.append("  provider: voz   # 30/10/2026: o edge-tts do contentor da 403 (versao fixada 7.2.7); fala-se pelo servidor de voz do host")
    else:
        novo.append(l)
    if re.match(r"^  auto_tts: true\s*$", l):
        novo += ["  providers:",
                 "    voz:",
                 "      type: command",
                 "      command: python3 /opt/data/voz/voz_cmd.py {input_path} {output_path}",
                 "      output_format: ogg",
                 "      timeout: 175",
                 "      max_text_length: 20000"]
ls[ini:fim] = novo
open(F, "w", encoding="utf-8").write("\n".join(ls))
ok = subprocess.run(["docker", "exec", "hermes-agent-fvnc-hermes-agent-1", "/opt/hermes/.venv/bin/python", "-c",
                     "import yaml; d=yaml.safe_load(open('/opt/data/config.yaml')); t=d['tts']; print(t['provider'], t['providers']['voz']['type'], t['providers']['voz']['timeout'])"],
                    capture_output=True, text=True)
print("YAML:", (ok.stdout or ok.stderr).strip()[:200])
if ok.returncode != 0:
    shutil.copy2(BAK, F)
    print("YAML INVALIDO, REPOSTO")
    sys.exit(1)
