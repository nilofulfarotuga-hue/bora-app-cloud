# Prova — motorista em fundo com ecrã apagado (emulador, 24/09/2026)

- Emulador: AVD `emdia` (Android 14 / SDK 34) neste PC, `-memory 3072 -gpu host`.
- APK: `build/app/outputs/flutter-apk/app-debug.apk` construído 09:17 (Lisboa) a partir do ramo
  `autonomous-night-2026-04-29` já com o merge dos commits de 23/09 (`80092026` motorista-ofertas).
- Conta: `demo-estafeta@bora.app` (auth uid `dede0000-0000-4000-8000-000000000001`).
- GPS do emulador fixado em 37.4220,-122.0840 (longe da Guarda) para o demo **não** entrar no
  despacho real enquanto esteve online.
- Permissões dadas por `pm grant` antes de abrir: localização (fina, grosseira, em fundo),
  notificações, câmara; `USE_FULL_SCREEN_INTENT: granted=true` (dumpsys package).

## Linha do tempo (UTC = Lisboa − 1h)

| Momento (UTC) | O que aconteceu |
|---|---|
| 08:28:03 | toque no interruptor "Estás offline" → online |
| 08:28:51 | HOME + `KEYCODE_SLEEP`: `mWakefulness=Asleep`, `mCurrentFocus=null` |
| 08:29:01 | `driver_locations.last_updated` (heartbeat 08:29:02) |
| 08:35:35 | `driver_locations.last_updated` = `drivers.last_heartbeat_at` |
| 08:37:20 | `last_updated` (heartbeat 08:37:22) |
| 08:38:16 | `last_updated` = heartbeat |
| 08:39:01 | `last_updated` (heartbeat 08:39:02) — ecrã continuava `Asleep` às 08:37:19 (dumpsys) |

Serviços vivos com a app em fundo (`dumpsys activity services pt.boraapp.bora`):
`com.pravera.flutter_foreground_task.service.ForegroundService` e
`BubbleService isForeground=true` (notificação canal `bora_service` id 1001).

Posição sempre 37.4219983,-122.084 (o emulador não se moveu) e mesmo assim a linha foi
actualizada de minuto a minuto: é o batimento "parado" que a ordem pedia.

## O que NÃO se provou aqui
- A oferta por push a abrir em ecrã inteiro como chamada: exigia uma corrida TVDE real a ser
  oferecida ao demo; ficou confirmada só pelo código (`incoming_job_alert.dart` com
  `fullScreenIntent: true`, permissão concedida no aparelho).

Capturas: `emulador_01_motorista_offline.png`, `emulador_02_motorista_online.png`.
