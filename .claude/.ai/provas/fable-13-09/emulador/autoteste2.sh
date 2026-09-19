#!/usr/bin/env bash
# Segunda corrida (so APK + permissoes + drive); analyze/test ja verdes na 1.a.
cd /c/BoraLocal/projetosflutter/bora_app || exit 9
L=.claude/.ai/provas/fable-13-09/emulador
echo "INICIO2 $(date +%H:%M:%S) HEAD=$(git rev-parse --short HEAD) jdk=$(flutter config 2>/dev/null | grep -i 'jdk-dir' | head -1)" > "$L/autoteste2.log"

flutter build apk --debug --target=integration_test/demo_real_test.dart \
  --dart-define-from-file=.dart_defines --android-skip-build-dependency-validation > "$L/build_apk2.log" 2>&1
echo "BUILD_EXIT=$? $(date +%H:%M:%S)" >> "$L/autoteste2.log"
APK=build/app/outputs/flutter-apk/app-debug.apk
ls -la "$APK" >> "$L/autoteste2.log" 2>&1 || { echo "SEM APK" >> "$L/autoteste2.log"; exit 1; }

adb -s emulator-5554 install -r "$APK" >> "$L/autoteste2.log" 2>&1
PKG=$(adb -s emulator-5554 shell pm list packages | tr -d '\r' | grep -i 'boraapp' | head -1 | cut -d: -f2)
echo "PKG=$PKG" >> "$L/autoteste2.log"
for p in android.permission.ACCESS_FINE_LOCATION android.permission.ACCESS_COARSE_LOCATION \
         android.permission.POST_NOTIFICATIONS android.permission.CAMERA; do
  adb -s emulator-5554 shell pm grant "$PKG" "$p" >> "$L/autoteste2.log" 2>&1 || true
done

mkdir -p artefactos/capturas
flutter drive --driver=test_driver/capturas_driver.dart \
  --target=integration_test/demo_real_test.dart \
  --use-application-binary="$APK" -d emulator-5554 > "$L/drive2.log" 2>&1
echo "DRIVE_EXIT=$? $(date +%H:%M:%S)" >> "$L/autoteste2.log"
ls artefactos/capturas 2>/dev/null | wc -l | sed 's/^/CAPTURAS=/' >> "$L/autoteste2.log"
ls artefactos/capturas 2>/dev/null | grep -c 'falha' | sed 's/^/FALHAS=/' >> "$L/autoteste2.log"
echo "FIM2 $(date +%H:%M:%S)" >> "$L/autoteste2.log"
