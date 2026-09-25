#!/usr/bin/env bash
# Autoteste dos 3 perfis no emulador (CI e local). Chamado NUMA LINHA SO pelo
# reactivecircus/android-emulator-runner: esse action corre cada linha do
# `script:` num `sh -c` proprio, e a 13/09/2026 (run #430) a variavel $APK
# chegou vazia ao `adb install` ("filename doesn't end .apk"). Aqui vive tudo
# no mesmo shell.
#
# Portao: o codigo de saida e o do `flutter drive` (sem pipe para o tee, que o
# esconderia). Falhas suaves (zz-falha-*.png) contam-se mas nao bloqueiam: o
# arnes so falha a serio (fail()) em crash ou percurso partido.
set -u
SERIAL="${ANDROID_SERIAL:-emulator-5554}"
APK="${APK:-build/app/outputs/flutter-apk/app-debug.apk}"
LOG="${AUTOTESTE_LOG:-artefactos/autoteste.log}"

[ -f "$APK" ] || { echo "ERRO: APK de teste nao existe em $APK"; exit 2; }
mkdir -p artefactos/capturas

echo "== adb install ($SERIAL)"
adb -s "$SERIAL" install -r "$APK" || { echo "ERRO: adb install falhou"; exit 3; }
PKG=$(adb -s "$SERIAL" shell pm list packages | tr -d '\r' | grep -i 'boraapp' | head -1 | cut -d: -f2)
echo "PKG=$PKG"
[ -n "$PKG" ] || { echo "ERRO: pacote da Bora nao encontrado no emulador"; exit 4; }
for p in android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION \
         android.permission.POST_NOTIFICATIONS android.permission.CAMERA; do
  adb -s "$SERIAL" shell pm grant "$PKG" "$p" 2>/dev/null || true
done

echo "== flutter drive (3 perfis)"
flutter drive \
  --driver=test_driver/capturas_driver.dart \
  --target=integration_test/demo_real_test.dart \
  --use-application-binary="$APK" \
  -d "$SERIAL" > "$LOG" 2>&1
rc=$?
tail -n 120 "$LOG"
echo "DRIVE_EXIT=$rc"
echo "CAPTURAS=$(ls artefactos/capturas 2>/dev/null | wc -l) FALHAS_SUAVES=$(ls artefactos/capturas 2>/dev/null | grep -c 'falha')"
exit $rc
