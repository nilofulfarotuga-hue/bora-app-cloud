# CONTINUAR — tvde-oferta-fantasma (01/10/2026): falta SÓ a prova no emulador

A correcção está no ar (commit `7df0fc49`, push `753a2131`). O que ficou por fazer é a
prova ao vivo no emulador: aceitar uma oferta de teste a dinheiro com a conta demo,
finalizar, voltar à home e fotografar que não há ecrã nem aviso fantasma.

## Porque não se fez a 01/10

O PC não teve memória. O modelo do Ollama (`qwen2.5:7b-instruct`, 4,3 a 5,5 GB) é usado
pela VPS através do túnel `tunel-ollama-vps.ps1` e volta a carregar sozinho minutos depois
de ser descarregado. Medido: 383, 375, 172 MB disponíveis com o emulador aberto. O Android
do emulador reiniciava serviços (ANR em `com.android.phone`, `system_server` a renascer) e
o `adb install` ficava pendurado. O APK chegou a ficar instalado, mas não se chegou a abrir.

Nenhuma corrida de teste foi pedida em produção. A conta demo não foi alterada.

## Condições para tentar outra vez (medir antes, não assumir)

1. Pelo menos 2,5 GB disponíveis e a ficarem assim durante 3 minutos:
   `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`. Se o
   `ollama ps` mostrar o modelo carregado, a VPS está a usá-lo — escolher outra hora.
2. Nenhum motorista real ligado (o Danilo estava ligado a 01/10 ao meio-dia):
   `select name from drivers where vehicle_type='carro_passageiros' and is_online and
   last_heartbeat_at > now() - interval '10 minutes' and user_id <> 'dede0000-0000-4000-8000-000000000001';`
   tem de dar zero linhas. A janela de sinal do TVDE é de 600 s, não 90.

## Passos

1. `flutter build apk --debug --dart-define-from-file=.dart_defines --android-skip-build-dependency-validation`
   (4 min). O emulador `emdia` já tem espaço: tiraram-se as actualizações das apps Google.
2. Emulador: `emulator -avd emdia -gpu host -memory 3072 -cores 3 -no-snapshot-load`;
   `adb install -g <apk>`; `adb emu geo fix -9.1364 38.7075` (Lisboa, longe da Guarda).
3. Entrar como `demo-estafeta@bora.app`. A conta demo é mota: passar a carro de passageiros
   pela função oficial `admin_update_driver('dede0000-0000-4000-8000-000000000002', 'prova oferta fantasma',
   p_vehicle_type => 'carro_passageiros')` com o JWT de admin simulado (uid c9fccf85…), e
   repor `motorcycle` no fim. Ficar online; confirmar `driver_locations` fresco (< 60 s).
4. Pedir a corrida: `BORA_DEMO_PW=… py .claude/.ai/provas/tvde-oferta-fantasma-2026-10-01/emulador/pedir_corrida_demo.py pedir`.
   O guião pede pela RPC do cliente e VIGIA: cancela sozinho se a oferta não for para o demo
   ou se ninguém aceitar em 28 s (a oferta vive 40 s). Não usar INSERT/UPDATE directo em
   `tvde_rides` (regras de 16/09).
5. Tocar em Aceitar (`emulador/tap.sh`), cheguei, iniciar, finalizar; fotografar cada passo
   com `emulador/shot.sh`. Prova final: home sem "Nova corrida" e
   `adb shell dumpsys notification | grep pt.boraapp` sem aviso da corrida.
6. Registar no `e2e_log`, fluxo `tvde-oferta-fantasma-2026-10-01`, passo `b3-emulador`.

Fica uma corrida demo finalizada a dinheiro em produção (não se apaga). Dizê-lo no relatório.
