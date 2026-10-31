#!/usr/bin/env python3
# guarda-degradado.py — o guarda da voz passa a avisar quando a voz esta a funcionar so pelo motor de reserva.
# Antes: qualquer nivel a funcionar contava como "OK" e o Piper tapou durante semanas o edge-tts morto (a Microsoft recusava a versao antiga).
import shutil, subprocess, sys
F = "/usr/local/bin/hermes-voz-guarda.sh"
t = open(F, encoding="utf-8").read()
if "guarda-degradado" in t:
    print("JA FEITO"); sys.exit(0)
shutil.copy2(F, F + ".bak-voz-20261030")
velho = "  NIVEL=*)\n    date -Is > \"$BATIDA\"\n"
if velho not in t:
    print("ancora nao encontrada"); sys.exit(1)
novo = ("  NIVEL=*)\n"
        "    date -Is > \"$BATIDA\"\n"
        "    # 30/10/2026: o edge-tts tinha morrido (403) e o Piper tapou-o durante semanas. Avisar quando so ha reserva.\n"
        "    case \"$r\" in\n"
        "      *DEGRADADO*)\n"
        "        registar \"DEGRADADO $r\"\n"
        "        if [ ! -f \"$VOZ/.guarda-degradado\" ]; then touch \"$VOZ/.guarda-degradado\"; avisar_telegram \"A voz do Hermes esta a funcionar so pelo motor de reserva (o edge-tts nao serve). $r\"; fi ;;\n"
        "      *) rm -f \"$VOZ/.guarda-degradado\" ;;   # guarda-degradado\n"
        "    esac\n")
open(F, "w", encoding="utf-8").write(t.replace(velho, novo, 1))
ok = subprocess.run(["bash", "-n", F]).returncode == 0
if not ok:
    shutil.copy2(F + ".bak-voz-20261030", F); print("SINTAXE FALHOU, REPOSTO"); sys.exit(1)
print("OK:", F)
