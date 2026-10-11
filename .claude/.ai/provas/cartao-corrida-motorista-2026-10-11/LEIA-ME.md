# Prova — cartão da corrida do motorista por fases (11/10/2026)

Missão `cartao-corrida-motorista`, sessão "PC do Danilo".

## O que está aqui

- `capturar.ps1` — instala o APK de prova no emulador (`emdia35`), põe o GPS na
  Guarda e tira uma captura por adb a cada `[prova] PRONTO <nome>` do log.
- `capturas_android_tres_botoes/` — o ecrã VERDADEIRO da corrida
  (`TvdeRideActiveScreen`) no Android 15 com a barra de 3 botões, nas fases
  a caminho / chegou / em viagem / em viagem com paragem, com a gaveta
  recolhida e aberta.

## Como se repete

```powershell
flutter build apk --debug --dart-define-from-file=.dart_defines `
  --android-skip-build-dependency-validation `
  --target=integration_test/tvde_corrida_fases_prova_test.dart
powershell -File .claude\.ai\provas\cartao-corrida-motorista-2026-10-11\capturar.ps1
```

## Sem escrever no banco

A corrida é de exemplo, num store falso (`integration_test/tvde_corrida_fases_prova_test.dart`).
O ecrã chama sozinho `driver_update_location` e `tvde_ride_passenger_card`; as
duas estão fechadas a `anon` (verificado por SELECT a 11/10: `anon_exec=false`,
ambas com `auth.uid()` obrigatório) — sem sessão falham e não gravam nada. Por
isso o título aparece sem nome ("o passageiro").

Fotos em memória dos mesmos widgets (3 fases × recolhida/aberta × 390 e 320 px):
`test/golden/_fotos/tvde_corrida_motorista_*.png`.
