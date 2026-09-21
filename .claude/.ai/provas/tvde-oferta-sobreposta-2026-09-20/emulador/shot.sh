#!/usr/bin/env bash
# uso: shot.sh <nome>  → captura do emulador para a pasta de provas
P=/c/BoraLocal/projetosflutter/bora_app/.claude/.ai/provas/tvde-oferta-sobreposta-2026-09-20/emulador
A=~/AppData/Local/Android/Sdk/platform-tools/adb.exe
MSYS_NO_PATHCONV=1 $A -s emulator-5554 exec-out screencap -p > "$P/$1.png" && echo "$P/$1.png $(stat -c %s "$P/$1.png")"
