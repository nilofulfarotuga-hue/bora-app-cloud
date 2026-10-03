#!/usr/bin/env bash
# Instala o NDK 28.2.13676358 (r28c) no SDK a partir do zip descarregado directamente
# (o descarregador do Gradle encravou nos 51 MB) e lanca a corrida do autoteste.
set -u
SDK="/c/Users/danil/AppData/Local/Android/Sdk"
ZIP="/c/Users/danil/ndk-r28c.zip"
L=/c/BoraLocal/projetosflutter/bora_app/.claude/.ai/provas/fable-13-09/emulador
TAR=/c/Windows/System32/tar.exe   # bsdtar do Windows: extrai zip (o tar do Git Bash nao)

echo "NDK-INSTALL $(date +%H:%M:%S) zip_bytes=$(stat -c %s "$ZIP")" > "$L/ndk_install.log"
rm -rf "$SDK/ndk/28.2.13676358" "$SDK/.temp/PackageOperation01"
mkdir -p "$SDK/ndk" && cd "$SDK/ndk" || exit 9
"$TAR" -xf "$ZIP" >> "$L/ndk_install.log" 2>&1
echo "TAR_EXIT=$?" >> "$L/ndk_install.log"
d=$(ls -d android-ndk-* 2>/dev/null | head -1)
[ -n "$d" ] && mv "$d" 28.2.13676358
grep -i 'Pkg.Revision' "$SDK/ndk/28.2.13676358/source.properties" >> "$L/ndk_install.log" 2>&1
du -sm "$SDK/ndk/28.2.13676358" >> "$L/ndk_install.log" 2>&1
echo "NDK-FIM $(date +%H:%M:%S)" >> "$L/ndk_install.log"
cat "$L/ndk_install.log"

bash "$L/autoteste2.sh"
