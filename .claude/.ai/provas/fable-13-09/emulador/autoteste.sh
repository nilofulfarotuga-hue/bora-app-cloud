#!/usr/bin/env bash
# Portoes do Juiz + autoteste dos 3 perfis no emulador Android (fable-13-09).
# Corre em segundo plano; cada passo deixa o seu log ao lado.
cd /c/BoraLocal/projetosflutter/bora_app || exit 9
L=.claude/.ai/provas/fable-13-09/emulador
echo "INICIO $(date +%H:%M:%S) HEAD=$(git rev-parse --short HEAD)" > "$L/autoteste.log"

flutter analyze --no-pub > "$L/analyze_merged.log" 2>&1; echo "ANALYZE_EXIT=$? $(tail -1 "$L/analyze_merged.log")" >> "$L/autoteste.log"
flutter test --no-pub > "$L/test_merged.log" 2>&1;    echo "TEST_EXIT=$? $(tail -1 "$L/test_merged.log")" >> "$L/autoteste.log"

flutter build apk --debug --target=integration_test/demo_real_test.dart \
  --dart-define-from-file=.dart_defines > "$L/build_apk.log" 2>&1
echo "BUILD_EXIT=$? $(date +%H:%M:%S)" >> "$L/autoteste.log"
APK=build/app/outputs/flutter-apk/app-debug.apk
ls -la "$APK" >> "$L/autoteste.log" 2>&1

adb -s emulator-5554 install -r "$APK" >> "$L/autoteste.log" 2>&1
PKG=$(adb -s emulator-5554 shell pm list packages | tr -d '\r' | grep -i 'boraapp' | head -1 | cut -d: -f2)
echo "PKG=$PKG" >> "$L/autoteste.log"
for p in android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION \
         android.permission.POST_NOTIFICATIONS android.permission.CAMERA; do
  adb -s emulator-5554 shell pm grant "$PKG" "$p" >> "$L/autoteste.log" 2>&1 || true
done

mkdir -p artefactos/capturas
flutter drive --driver=test_driver/capturas_driver.dart \
  --target=integration_test/demo_real_test.dart \
  --use-application-binary="$APK" -d emulator-5554 > "$L/drive.log" 2>&1
echo "DRIVE_EXIT=$? $(date +%H:%M:%S)" >> "$L/autoteste.log"
ls artefactos/capturas 2>/dev/null | wc -l | sed 's/^/CAPTURAS=/' >> "$L/autoteste.log"
echo "FIM $(date +%H:%M:%S)" >> "$L/autoteste.log"
