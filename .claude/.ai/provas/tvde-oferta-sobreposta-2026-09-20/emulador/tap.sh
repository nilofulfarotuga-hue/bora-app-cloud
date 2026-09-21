#!/usr/bin/env bash
# uso: tap.sh x y   (coordenadas no ecrã 1080x2400)
~/AppData/Local/Android/Sdk/platform-tools/adb.exe -s emulator-5554 shell input tap "$1" "$2"
