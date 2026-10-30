#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# rotear.py — poe os caminhos de envio do Hermes para o Danilo a passar pela voz unica (audio-add.sh / voz.py).
# Cada ficheiro: copia .bak-voz-20261030, insercao idempotente (marca "voz-audio-add"), validacao de sintaxe; se falhar, repoe.
import os, re, shutil, subprocess, sys

AA = "/opt/data/voz/audio-add.sh"
M = "  # voz-audio-add"

# (ficheiro, tipo, regex da linha-ancora (a ULTIMA linha da instrucao de envio), linhas a inserir DEPOIS dela)
P = [
 ("/opt/data/scripts/gritar.sh", "sh", r"^\s*\*'\"ok\":true'\*\) exit 0 ;;\s*$",
  None),   # tratado a parte (substituicao)
 ("/opt/data/scripts/social-carrossel.sh", "sh", r'^\s*\[ "\$http" = "200" \] \|\| log "AVISO NAO SAIU',
  ['[ "$http" = "200" ] && %s -f "$TMPD/tg-$CARIMBO.txt"' % AA]),
 ("/opt/data/scripts/social-grupos-resumo.sh", "sh", r'^\s*-F "text=<\$MSG" -F "disable_web_page_preview=true"\)\s*$',
  ['[ "$RC" = "200" ] && %s -f "$MSG"' % AA]),
 ("/opt/data/scripts/social-grupos-plano.sh", "sh", r'^\s*-F "text=<\$MSG" -F "disable_web_page_preview=true"\)\s*$',
  ['[ "$RC" = "200" ] && %s -f "$MSG"' % AA]),
 ("/opt/data/scripts/social-reavaliacao.sh", "sh", r'^\s*-F "text=<\$MSG" -F "disable_web_page_preview=true"\s*$',
  ['%s -f "$MSG"' % AA]),
 ("/opt/data/scripts/prova_do_dia.sh", "sh", r'^\s*--data-urlencode "disable_web_page_preview=true" 2>&1\)\s*$',
  ['%s "$MSG"' % AA]),
 ("/usr/local/bin/hermes-sonda-auth.sh", "sh", r'^\s*--data-urlencode "chat_id=\$TG_CHAT" --data-urlencode "text=\$msg" >/dev/null\s*$',
  ['AUDIO_CHAT="$TG_CHAT" %s "$msg"' % AA]),
 ("/usr/local/bin/hermes-gateway-watchdog.sh", "sh", r'^\s*--data-urlencode "text=Watchdog: gateway do Hermes nao voltou apos restart automatico\. Precisa de ti\." >/dev/null 2>&1\s*$',
  ['AUDIO_CHAT=6731890157 %s "Watchdog: gateway do Hermes nao voltou apos restart automatico. Precisa de ti."' % AA]),
 ("/usr/local/bin/hermes-heartbeat.sh", "sh", r'^\s*--data-urlencode "chat_id=\$CHAT" --data-urlencode "text=\$1" >/dev/null 2>&1\s*$',
  ['_rc=$?; AUDIO_CHAT="$CHAT" %s "$1"; (exit $_rc)' % AA]),
 ("/root/claude-token-watchdog.sh", "sh", r'^\s*--data-urlencode "chat_id=\$CHAT" --data-urlencode "text=\$msg" >/dev/null 2>&1\s*$',
  ['_rc=$?; AUDIO_CHAT="$CHAT" %s "$msg"; (exit $_rc)' % AA]),
 ("/root/em-dia-telegram.sh", "sh", r'^curl -s -X POST "https://api\.telegram\.org/bot\$\{TELEGRAM_BOT_TOKEN\}/sendMessage" "\$\{ARGS\[@\]\}" \|',
  ['_rc=$?; %s "$T"; exit $_rc' % AA]),
 ("/usr/local/bin/hermes-meta-token-vigia.sh", "sh", r'^\s*docker exec -u hermes "\$C" sh -lc "set -a; \. /opt/data/\.env; set \+a; curl -s -m 20 -X POST',
  ['_rc=$?; %s "$1"; (exit $_rc)' % AA]),
 ("/usr/local/bin/hermes-notificar-rotina.sh", "sh", r'^\s*log "fallback: Telegram enviado directo',
  ['AUDIO_CHAT="$chat" %s "$texto"' % AA]),
 ("/usr/local/bin/hermes-voz-guarda.sh", "sh", r'^PYEOF\s*$',
  ['%s "$1"' % AA]),
 ("/opt/data/social/ig_auto_dm.py", "py", r"^\s+ok = b'\"ok\":true' in r\.read\(\)\s*$",
  ['if ok:', '    import subprocess as _sp', '    _sp.Popen(["bash", "%s", texto], env=dict(os.environ, AUDIO_CHAT=str(chat)))' % AA]),
 ("/opt/data/social/resumo_do_dia.py", "py", r'^\s+"https://api\.telegram\.org/bot%s/sendMessage" % token, dados, timeout=30\)\s*$',
  ['import subprocess as _sp', '_sp.Popen(["bash", "%s", texto], env=dict(os.environ, AUDIO_CHAT=str(chat)))' % AA]),
]


def validar(f, tipo):
    if tipo == "sh":
        return subprocess.run(["bash", "-n", f], capture_output=True).returncode == 0
    return subprocess.run([sys.executable, "-m", "py_compile", f], capture_output=True).returncode == 0


def main():
    for f, tipo, ancora, linhas in P:
        if not os.path.exists(f):
            print("SALTADO (nao existe):", f); continue
        txt = open(f, encoding="utf-8").read()
        if "voz-audio-add" in txt:
            print("JA FEITO:", f); continue
        bak = f + ".bak-voz-20261030"
        if not os.path.exists(bak):
            shutil.copy2(f, bak)
        novo = None
        if f.endswith("gritar.sh"):
            velho = "  *'\"ok\":true'*) exit 0 ;;"
            if velho in txt:
                novo = txt.replace(velho, "  *'\"ok\":true'*) AUDIO_CHAT=\"$CHAT\" %s \"Aviso do Bora: $MSG\"; exit 0 ;;%s" % (AA, M), 1)
        else:
            ls = txt.split("\n")
            idx = [i for i, l in enumerate(ls) if re.search(ancora, l)]
            if len(idx) == 1:
                i = idx[0]
                ind = re.match(r"\s*", ls[i]).group(0)
                if f.endswith("resumo_do_dia.py"):          # a linha-ancora e' continuacao; o indent certo e' o do inicio da instrucao
                    ind = re.match(r"\s*", ls[i - 1]).group(0)
                if tipo == "py" and linhas[0].startswith("if ok"):
                    ins = [ind + linhas[0], ind + "    " + linhas[1].strip(), ind + "    " + linhas[2].strip()]
                else:
                    ins = [ind + l for l in linhas]
                ins[-1] = ins[-1] + M
                ls[i + 1:i + 1] = ins
                novo = "\n".join(ls)
            else:
                print("ANCORA %s vezes (esperava 1): %s" % (len(idx), f)); continue
        if novo is None:
            print("NAO APLICADO:", f); continue
        open(f, "w", encoding="utf-8").write(novo)
        if validar(f, tipo):
            print("OK:", f)
        else:
            shutil.copy2(bak, f)
            print("SINTAXE FALHOU, REPOSTO:", f)


main()
