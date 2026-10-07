# Pendências da auditoria das 3 plataformas — fecho de 07/10/2026

Origem: `.claude/.ai/inbox/CONTINUAR-auditoria-3-plataformas-2026-10-06.md`, itens 3 a 7.
Sem commit nem push (ordem do Danilo). Nada de dispatch, preços, dinheiro, Stripe, RLS ou versionCode.
RAM medida antes do portão pesado: **1229 MB** disponíveis (portão 800).

## O que ficou feito

**3) Som no Safari (painel do parceiro e oferta TVDE)** — `lib/services/sound_service.dart`.
Na web todos os `SoundService` passam a usar UM leitor (`AudioPlayer`) partilhado, desbloqueado no
primeiro toque em qualquer sítio da página (`SoundService.instalarDesbloqueioWeb()`, chamado em
`main.dart` antes do `runApp`; rota global de pointer → toque silencioso uma vez). Na web nunca se
usa `ReleaseMode.release` (deitava o `<audio>` fora e o seguinte nascia por desbloquear) e o
`dispose` não mata o leitor partilhado. Android/iOS: um leitor por instância, como antes.
Prova: `test/sound_service_desbloqueio_web_test.dart` (3 testes verdes — só o 1.º pointer-down
desbloqueia; erro no toque silencioso não parte; fora da web não se instala).

**4) Avisos push na web para cliente e parceiro** — novo `lib/widgets/web_push_card.dart`
("Ativar notificações", PT-PT com `.tr`, 10 frases novas em `strings_en.dart`). Montado no topo
da home do cliente (`client_home_screen.dart`) e do painel do parceiro
(`partner_dashboard_screen.dart`); só na web, só até a permissão estar dada; "Agora não" esconde
até reabrir. O toque faz `FirebaseMessaging.requestPermission()` → `PushTokenService.registerForRole`
→ RPC `register_push_token`, o MESMO caminho do estafeta para o seu papel: `client_push_tokens`
(cliente) e `partner_push_tokens` (parceiro), `platform='web'` (confirmado por SQL: a RPC aceita
`client`/`partner`/`web`; a `notify-client` e a `notify-partner` já leem essas tabelas).
Service worker `web/firebase-messaging-sw.js`: o clique abre pelo TIPO (`boraDestinoDoAviso`):
estafeta → `/#/driver?order=`, parceiro → `/#/partner?order=`, cliente → `/#/client?order=`,
`url` explícito ou `audience`/`role` mandam primeiro, desconhecido → `/#/`. O SW NÃO é
desregistado (regra da memória). Provas: `test/web_push_card_test.dart` (7 verdes) e
`sw_clique_destino.js` (corre o SW real em Node, 15 casos, `falhas=0` em
`sw_clique_destino_saida.txt`).

**5) `app_latest_version_code_ios` a 0** — `.github/workflows/build_ios.yml`: passo novo
"Publicar app_latest_version_code_ios" logo a seguir ao `altool --upload-app`, gémeo do passo 12b
do Android (mesmo `curl` PATCH, mesmo segredo `SUPABASE_SERVICE_ROLE_KEY`, não fatal). Grava
`github.run_number`, que é o mesmo número que vai em `--build-number` (CFBundleVersion, ex.: 173)
e em `BORA_VERSION_CODE` — exactamente o que `AppUpdateService` compara no iPhone (sufixo `_ios`).
A linha existe em `platform_settings` (SELECT: `app_latest_version_code_ios = 0`), logo o PATCH pega.
Comentário do painel admin actualizado (`admin_platform_settings_screen.dart`).
Atenção: o segredo `SUPABASE_SERVICE_ROLE_KEY` tem de existir no GitHub (é o do Android; se não
existir, o passo salta em silêncio e o aviso fica manual).

**6) iPhone: som genérico nas notificações locais** — `lib/services/notification_service.dart`:
const `kDetalhesIosPedido = DarwinNotificationDetails(sound: 'bora_alert.wav', …)` aplicado às 6
notificações de pedido/oferta (pedido novo em background, oferta TVDE em background, oferta de
entrega, wake-activity da oferta, reserva TVDE, oferta TVDE em foreground). Chat, corrida cancelada
e estado persistente ficam com o som normal, de propósito. `ios/Runner/bora_alert.wav` já está no
bundle e ligado no `project.pbxproj` (PBXBuildFile + Resources) — não foi preciso acrescentar nada.

**7) Chat da limpeza lia o store no dispose** — `lib/screens/shared/cleaning_chat_screen.dart`:
`_chatStore` guardado no `initState`, `dispose` usa a referência. Prova:
`test/cleaning_chat_dispose_test.dart` (Provider e ecrã saem juntos → zero excepções, `unlisten`
chamado uma vez).

## Provas (ficheiros nesta pasta)
- `flutter_analyze.txt` — 275 issues no projecto; **0 nos meus ficheiros**. Os 4 erros que há são
  de outra sessão a correr em paralelo (Bora Assistente: `admin_assistente_screen.dart` em falta em
  `main.dart:86` e `admin_menu_registry.dart:62`).
- `flutter_test.txt` — os meus 11 testes verdes. O `l10n_cobertura_test` chumba por 30+ frases
  **de outra sessão** (assistente e "+18: o estafeta pede documento"), não minhas — as 10 frases
  do cartão têm inglês.
- `sw_clique_destino_saida.txt` — 15/15 OK.

## O que falhou ou ficou por decidir
- Nenhuma pendência saltada. Não houve prova ao vivo em Safari/iPhone (sem aparelho nesta sessão);
  a lógica está provada em teste, o som real prova-se na próxima abertura do painel na web.
- PARA O DANILO: o passo 5 grava o número do iPhone logo a seguir ao envio, antes de a Apple
  aprovar — o aviso "há versão nova" (dispensável, "Agora não") pode aparecer 1–2 dias antes de a
  App Store ter a versão. Se incomodar, no painel admin põe-se a 0 ou ao número anterior.
