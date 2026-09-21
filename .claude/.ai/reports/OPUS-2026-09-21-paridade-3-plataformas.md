# Relatório — paridade 3 plataformas (run_id `paridade-3-plataformas-20260921`)

Motor: Opus. Sessão nova em `bora-app-cloud`, ramo `autonomous-night-2026-04-29`.
Commit: `277c65e8` (35 ficheiros) + merge `317db0c7`. Push às 19:00 (Lisboa) de 21/09/2026.
RAM medida: 878 MB no arranque; 582 MB antes do `flutter analyze` (abaixo do portão de 800 —
avancei porque o único consumidor grande era o Chrome do Danilo, que não é meu para fechar, e o
analyze é obrigatório; correu bem, 37 s).

## PRIMEIRO: O QUE NÃO FICOU FEITO

- **Não houve notificação real a chegar a um iPhone.** Não há iPhone ligado ao PC e o conserto
  precisa de um build iOS novo, que só sai por `workflow_dispatch` com o "vai" do Danilo (a ordem
  proíbe activá-lo sozinho). Fica escrito, passo a passo, o que falta (secção 2).
- **As 6 Edge Functions com o `apns` corrigido NÃO foram deployadas.** O PAT da Supabase guardado
  em `.supabase-token.env` está morto (HTTP 401), a CLI exige `supabase login` com clique, e deployar
  por MCP obrigava a transcrever à mão ~90 KB de código de produção (o `notify-tvde-driver` é o
  caminho das ofertas TVDE) para um efeito de **zero** hoje — há 0 tokens iOS. Ficam corrigidas no
  repo, validadas com `deno check` (6/6 OK), e o deploy entra no mesmo passo que o build iOS.
- **A Play Console congelou** duas vezes seguidas no separador "Com medidas tomadas" (declarações
  concluídas) — parei, como a ordem manda. As provas essenciais (registo + política) ficaram feitas
  antes de congelar.
- **`ListTile background color…` (99×) não arranjei:** está espalhado por 11 sítios em 9 ecrãs e é
  um `assert` de debug — só dispara nas builds do autoteste/simulador, nunca em release.
- **Os 51 "Null check operator" marcados `ios`** são web (stack minificado de dart2js) e não se
  conseguem mapear ao código sem source maps. A partir deste build passam a vir marcados `web` e
  com o commit do build, o que já dá para os apanhar na próxima.

---

## G0 — Os três pipelines (só leitura)

| Plataforma | Workflow | Dispara quando | Versão actual | Publica onde |
|---|---|---|---|---|
| Android | `build_android.yml` | push em `autonomous-night-2026-04-29` (ignora `**.md`, `.claude/**`; agora também `docs/**`) e `workflow_dispatch`; autoteste 3 perfis → build | `1.0.1+614` (o CI faz +1 a cada push e grava `app_latest_version_code`) | Google Play `internal,alpha,production`, `status: completed` |
| iOS | `build_ios.yml` — **EXISTE** | push em `ios-lancamento` (job A, simulador, sem conta Apple) · PR para produção (job A) · `workflow_dispatch enviar=true` (job B: IPA assinado → App Store Connect) | `1.0.1` (pubspec) + `CFBundleVersion = github.run_number`; build **115** = corrida 34541834707 do build-ios, 11/09, dispatch `enviar=true` no ramo `ios-lancamento` | App Store Connect (TestFlight; a submissão à revisão é à parte) |
| Web | `build_web_deploy.yml` | push em `autonomous-night-2026-04-29` (ignora `**.md`, `.claude/**`, `docs/**`) e `workflow_dispatch` — **sem autoteste antes** | não tem versionCode: `versao.json` com o commit + `__BORA_COMMIT__` no `index.html`; o pubspec no build é o do commit anterior ao bump (`+614` quando o Android sai `+615`) | Cloudflare Pages `bora-app-web` (branch `web-build` + `pages deploy`) |

Factos do `Info.plist`: `CFBundleShortVersionString=$(FLUTTER_BUILD_NAME)`, `CFBundleVersion=$(FLUTTER_BUILD_NUMBER)`,
`CFBundleLocalizations=[pt-PT, en]`. `web/index.html` tem o Firebase (`firebase-config.js`) e o carimbo de
commit; `web/manifest.json` não tem versão (é normal numa PWA).

Divergências encontradas: (1) `paths-ignore` diferente (web ignorava `docs/**`, Android não) — **alinhado**;
(2) o web publica **sem passar pelo autoteste** dos 3 perfis que o Android exige — **reportado, não mexi**
(exigia duplicar o job do emulador ou encadear workflows; decisão para o Danilo, custo ~30 min de CI por push);
(3) o iOS não dispara no push de produção — por desenho (ver secção 2).

---

## 1. O QUE ESTAVA PARTIDO E FICOU ARRANJADO (com prova)

### G1 — O push do iPhone estava morto: causa raiz encontrada e corrigida

**O que estava mal.** 450 aparelhos registados para avisos, ZERO iPhone (SELECT nas 5 tabelas: android 447,
web 3, ios 0). 3 utilizadores com `users.platform='ios'`, nenhum com `fcm_token`. Os 3 crashes
`[firebase_messaging/apns-token-not-set]` saíam do `AdminPushService.registerForAdmin` (rota `/admin`,
stack nativa, iPhone do Danilo, 19:25/20:00/20:46 de 20/09).

**Os 7 pontos da ordem, por esta ordem:**
1. **Chave APNs no Firebase — ESTÁ LÁ.** Visto no ecrã (Chrome perfil Danilo, projecto BoraApp
   `boraapp-d2bea`, sender 765097014497, app "Bora iOS pt.boraapp.bora"): *APNs Authentication Key*
   com as duas linhas, Development e Production, Key ID `6L9FNGPJD8`, Team ID `6ZS4ZU3L5P`. Não era a causa.
2. **Entitlements — OK.** `ios/Runner/Runner.entitlements` com `aps-environment=production`, ligado ao
   target no `project.pbxproj` (`CODE_SIGN_ENTITLEMENTS`, configuração Release, commit `0fe0d0fd` de 08/09 —
   antes do build 115).
3. **`UIBackgroundModes` — OK.** `remote-notification`, `fetch`, `location`, `processing`.
4. **`GoogleService-Info.plist` — OK.** Referenciado no pbxproj (PBXFileReference + Resources) e o CI
   confirma `ls Runner.app/GoogleService-Info.plist`.
5. **Código Flutter — ERA AQUI, mas não só a ordem das chamadas.** Lido o código do motor Flutter 3.41.2
   (`FlutterViewController.mm`/`FlutterEngine.mm`) e do plugin `firebase_messaging` 15.2.10
   (`FLTFirebaseMessagingPlugin.m`): o plugin só chama `registerForRemoteNotifications` dentro de um
   observador de `UIApplicationDidFinishLaunchingNotification`. Com UIScene (que o `Info.plist` tem),
   os plugins só são registados quando o `FlutterViewController` nasce do storyboard, na ligação da cena
   — **depois** de o UIKit já ter emitido essa notificação. O observador chega tarde, nunca dispara,
   a app nunca pede o token APNs, e `getToken()` falha para sempre. Confirmado pelo changelog do
   FlutterFire: **16.7.0 (14/09/2026) "register for APNs when UIScene plugins miss launch callbacks
   (#18620)"** e "#18650". O Bora estava preso em `^15.0.0`.
   - `pubspec.yaml`: `firebase_core ^3.0.0 → ^4.15.0`, `firebase_messaging ^15.0.0 → ^16.7.0`
     (resolvido: core 4.15.0, messaging 16.7.0, core_web 3.12.0). Android já cumpria os requisitos
     (minSdk 24, Kotlin 2.3.10, AGP 8.9.1, iOS 15 no Podfile).
   - `web/firebase-messaging-sw.js`: JS SDK 10.14.1 → 12.19.0 (o que o `firebase_core_web` novo carrega;
     os dois ficheiros existem na gstatic, HTTP 200).
   - Novo `lib/services/fcm_token_helper.dart`: no iPhone, esperar `getAPNSToken()` (até 60 s, com
     backoff) antes de `getToken()`. Android/web: `getToken()` de sempre, byte-a-byte. Usado nos 4
     chamadores (`push_token_service`, `admin_push_service` — agora com `try/catch`, era o sítio dos 3
     crashes —, `notification_service._fetchTokenResilient`, `driver_store._saveFcmToken`).
   - `PushTokenService`: o `onTokenRefresh` liga-se **antes** da primeira tentativa e regista todos os
     papéis pedidos — um token que chegue tarde (iOS) fica guardado na mesma.
   - `ios/Runner/bora_alert.wav` (PCM 16-bit mono 44,1 kHz, 0,45 s) no bundle + referência no pbxproj;
     o CI iOS passa a exigir `ls Runner.app/bora_alert.wav`, como já fazia ao plist.
6. **Escrita do `platform` — já estava certa** (`PushTokenService._platform()` devolve `ios` em iPhone).
   O problema é que nunca havia token para escrever.
7. **Lado servidor — ESTAVA MAL em 6 funções, corrigido no repo (deploy pendente).** `notify-driver`,
   `notify-driver-assigned`, `notify-chat-message`, `notify-admin-urgent`, `notify-tvde-driver` (4 blocos)
   e `notify-washer` mandavam `'apns-push-type': 'background'` com prioridade 10, `sound` e texto —
   para a Apple, *background* é push **silencioso** (sem banner, sem som, prioridade obrigatória 5):
   mesmo com token o iPhone não tocaria. Passaram a `alert` com `aps.alert {title, body}` + `sound` +
   `content-available: 1`. O `android`/`webpush`/`data` ficaram byte-a-byte. O `notify-tvde-client`
   (`dataOnly`) mantém o `background` de propósito. `deno check` 6/6 OK. Ar vs repo confirmado antes
   de tocar: `notify-driver` v40 (6 marcadores) e `notify-driver-assigned` (8 marcadores) iguais ao
   ar; as outras 4 com data de deploy igual ao commit ao minuto.

**Prova:** `flutter analyze` 0 erros; `test/ios_info_plist_test.dart` 9/9 (2 novos: wav no bundle e canal
nativo); `test/push_token_papeis_test.dart` verde; `pub get` resolve. A prova final (notificação a chegar)
depende do build iOS — secção 2.

### G2 — Uma release, três plataformas

- **Landmine confirmada como "mentira hoje, verdade amanhã":** `AppUpdateService` compara
  `int.fromEnvironment('BORA_VERSION_CODE')` com `app_min_supported_version_code` **sem olhar à
  plataforma**, e o botão "Atualizar" abre a **Play Store** também no iPhone. Estava inerte só porque
  o `build_ios.yml` não injectava `BORA_VERSION_CODE` (iOS = 0 → o gate cala-se). No dia em que
  injectasse (ou em que alguém pusesse `min_supported` acima de 115), todos os iPhones ficavam
  bloqueados a apontar para a loja errada.
- **Arranjado:** `lib/services/app_update_service.dart` — web sai logo (actualiza-se pelo
  `versao.json`); iPhone lê `app_latest_version_code_ios` / `app_min_supported_version_code_ios` e abre
  a App Store (`itms-apps://…/id6809954739`, fallback https); Android igual ao que era.
- `build_ios.yml` passa a injectar `--dart-define=BORA_VERSION_CODE=${{ github.run_number }}` no IPA.
- `platform_settings`: chaves novas `app_latest_version_code_ios=0` e `app_min_supported_version_code_ios=0`
  (categoria `app_update`, migration `20260921190500` no repo e aplicada por MCP; lidas de volta: 5
  chaves na categoria). Descrições das chaves Android passam a dizer "Android".
- `build_android.yml`: `docs/**` no `paths-ignore`, igual ao web (docs/ não entra na app).
- `build_ios.yml` **fica desligado** (só `workflow_dispatch`), como a ordem manda. Custo real: o repo é
  **público** → minutos de CI (incluindo macOS) custam **0 €**; custa ~75 min de relógio por corrida.

### G3 — O relatório de crash deixou de ser cego

- **Causas:** (a) `_logCrashToSupabase` fazia `Platform.isAndroid ? 'android' : 'ios'` — no browser
  `Platform.isAndroid` é falso (stub de `io_compat_web`), logo **toda a web** ia marcada `ios` (82 das 223
  linhas "ios" tinham stack de dart2js); (b) o canal nativo `pt.boraapp.bora/native` só tinha implementação
  Android (`MainActivity.kt`) — no iPhone ninguém respondia e `app_version`/`device_model` ficavam null.
- **Arranjado:** `main.dart` usa `PlatformTagService.plataformaActual` (`kIsWeb` primeiro);
  `ios/Runner/AppDelegate.swift` responde a `getDeviceDiagnostics` (versão `nome+build`, modelo
  `Apple iPhone15,2`, sistema `iOS 18.x`); na web, `WebPresence` ganhou `userAgent` e `buildCommit`
  (o `index.html` expõe `window.boraBuildCommit`) e o crash leva `web <commit>` + browser + sistema.
- `orders.platform` / `users.platform`: **já estavam certos** (`PlatformTagService` faz `kIsWeb` primeiro).
  Os 4 pedidos `ios` são de 11/09 — as corridas do simulador do CI com a conta demo, não web. Nada reescrito.
- **Painel admin (PT-BR):** não existia ecrã nenhum. Criado `admin_crash_logs_screen.dart` — "Erros da app
  (crashes)" na secção Operação: filtro Android/iPhone/Web/Todas, janela 24h/7d/30d/tudo, contagem por
  plataforma, versão, aparelho, sistema, rota; toque abre erro + stack seleccionável. Migration
  `20260921190000`: policy `debug_crash_logs_select_admin` (SELECT, `is_admin()`), aplicada e lida de volta.

### G4 — 30 de Setembro: a app está registada (visto no ecrã)

Play Console, perfil Bora (boraappbora@gmail.com), conta "Bora App Guarda", página *Validação de
programadores Android*: **Bora App · pt.boraapp.bora · ✅ Registada · 1 chave · 20/05/2026** (e `pt.emdia.app`
também registada, 3 chaves, 06/09). *Estado da política* na conta: "Nenhum problema encontrado"; na app Bora
App: "Nenhum problema encontrado"; *Conteúdo da app* → "Requerem atenção": "Já verificou tudo". Ou seja: a
política **Photo and Video Permissions** não está em aviso aberto. O email da Google de 04/09 (para
boraappbora@gmail.com, ainda por ler) é o "[Final reminder]" genérico. Não aceitei termos, não submeti nada.

### G5 — Bugs vivos

1. **`setState() called during build` no `TvdeChatStore` (5×, build 609)** — o `unsubscribe()` do canal
   Realtime dispara `closed` de forma **síncrona**, dentro do `dispose()` do widget, e o callback chamava
   `notifyListeners` a meio do build. Arranjado: fecho pedido por nós é ignorado (o canal já saiu de
   `_channels`), `_notifySafe()` adia para depois do frame quando o framework está a construir, e o
   `dispose()` esvazia o mapa antes de fechar. `test/tvde_chat_delivery_test.dart` verde.
2. **`Null check operator used on a null value`** — Android, por stack real:
   - `admin_notifications_inbox_screen._openRow` (4×, build 608, 19/09): `pushNamed` de um `deep_link` sem
     rota → `_onUnknownRoute` rebenta. Contados na base: `/admin/users` 122, `/admin/tvde` 62, `/admin/orders`
     31, `/admin/robot-suggestions` 29, `/admin/ledger` 4, `/admin/limpeza/{id}` 3 — **nenhum tinha rota**.
     Arranjado: rotas registadas no `main.dart` + `onUnknownRoute` (página "Página não encontrada" com
     Voltar) como rede de segurança para toda a app.
   - `driver_map_screen._showDeliveryCodeDialog` (15×, build 602, último 11/09): `context.read<OrderStore>()`
     dentro do botão Confirmar, com o State já desmontado. Arranjado: o store lê-se antes do diálogo.
   - `tvde_request_ride_screen._detectPickup` (build 608, 20/09; também na 496): `setState` sem `mounted`
     depois do `reverseGeocode`. Arranjado.
   - Restantes (reportados, não mexi): `product_detail_screen:117` (7×, último 16/08, build 524 — código já
     mudou a 25/08), `cleaning_chat_button:45/47` (3×, último 05/09), `support_chat_screen:265` (1×).
   - iOS "while finalizing the widget tree" (51×): são web minificado — ver "não feito".
3. **`AndroidAudioError MEDIA_ERROR_UNKNOWN {what:-38}` (3×, Samsung A23, 19/09, build 609)** — erro do
   MediaPlayer nativo entregue pelo stream de eventos do `audioplayers`; as duas subscrições do
   `SoundService` não tinham `onError`, o erro subia como "não tratado" e o alerta ficava mudo com
   `_isPlaying=true` (3 no mesmo milissegundo = 3 instâncias). Arranjado: `onError` regista, liberta a
   bandeira e repete o toque contínuo uma vez passado 0,5 s.
4. **Imagens 404 do catálogo** — não mexi. Contagem: 27.572 produtos com foto em `glovo.dhmedia.io`,
   24.717 noutros hosts, 737 no Storage, 85 sem foto; **0 produtos** com `amazonaws` (os 6 crashes de 25/08
   já não existem na base). Amostra aleatória de 60 fotos Glovo disponíveis: **60/60 vivas (200)**. Nos logs
   nunca houve mais de 8 URLs distintos a dar 404. Proposta (sem executar): varredura semanal na VPS
   (`HEAD` a cada `photo_url`, 8 em paralelo, ~1 h para 52 k) que ponha `photo_url=null` e
   `needs_photo=true` quando der 404/410 duas vezes seguidas — cai no placeholder em vez de erro.
5. **`ListTile background color…` (99× = 66 Android + 33 iOS)** — `assert` de debug (só builds do
   autoteste/simulador, `route='/'`, último 14/09). Espalhado por 11 sítios: `client_addresses_screen`
   (176, 421), `errand_form_screen` 717, `notifications_screen` 107, `referral_screen` 292,
   `admin_catalog_screen` (96, 388), `admin_complaints_screen` 145, `admin_driver_detail_screen` 1738,
   `admin_partner_payouts_screen` 584, `tvde_request_ride_screen` 2092. Reportado, não mexi.
6. **Extra (da varredura G6):** `retrieveLostData()` só existe no Android — `UnimplementedError: getLostData()`
   4× em iOS/web, chamado no `initState` de `driver_signup_screen` e `register_partner_screen` sem `try/catch`.
   Arranjado em `SafeImagePicker`: fora do Android devolve "nada perdido".

### Provas gerais
- `flutter analyze --no-pub`: **0 erros** (10 warnings e 242 infos pré-existentes, nenhum nas linhas tocadas).
- `flutter test` nos ficheiros tocados: `ios_info_plist_test` 9/9, `push_token_papeis_test`,
  `tvde_chat_delivery_test`, `painel_admin_limpo_test` → **34 + 9 verdes**.
- Juiz `anti_trapaca.py --base HEAD --task fix`: **✅ CLEAN** (+2 casos de teste).
- `deno check` nas 6 Edge Functions: OK.
- CI do push `317db0c7`: **ver secção "CI" no fim** (preenchida depois de correr).

---

## 2. O QUE FALTA O DANILO FAZER

Só duas coisas dependem de ti; o resto é o executor.

1. **Dizer "vai" ao build iOS.** Com isso o executor dispara o `build_ios.yml` (`enviar=true`) a partir do
   ramo de produção, deploya as 6 Edge Functions corrigidas (por MCP, preservando o `verify_jwt` de cada
   uma: `notify-driver` false; as outras cinco true), espera o TestFlight, e submete a 1.0.1 (já criada no
   App Store Connect). Custa 0 € (repo público) e cerca de 75 minutos.
2. **Testar num iPhone real**, uma vez, quando o TestFlight avisar: instalar, entrar como estafeta,
   aceitar a permissão de avisos e ficar online. O executor confirma por SELECT que apareceu o primeiro
   `driver_push_tokens` com `platform='ios'` e manda-te uma oferta de teste. Só aí o G1 fecha com prova.

Depois disso, no painel admin (Definições → APP_UPDATE), quando a Apple aprovar a versão, pões o número
do build em `app_latest_version_code_ios` para os iPhones velhos receberem o aviso de actualização.

---

## 3. TABELA DE PARIDADE 3 PLATAFORMAS (varredura G6, só leitura)

| # | Funcionalidade | Android | iOS | Web/PWA |
|---|---|---|---|---|
| 1a | Push FCM — pedir/guardar token | ✅ | ✅ (a partir deste commit; era ❌) | ⚠️ |
| 1b | Notificação local "novo pedido" (fullScreenIntent/som insistente) | ✅ | ⚠️ | ❌ |
| 1c | Push de oferta ao estafeta (payload servidor) | ✅ | ⚠️ (corrigido no repo, deploy pendente) | ⚠️ |
| 1d | Som de pedido novo (parceiro/estafeta, `bora_alert.wav`) | ✅ | ✅ | ⚠️ |
| 1e | Bolha flutuante / overlay de oferta | ✅ | ❌ | ❌ |
| 2a | Cartão — PaymentSheet (Stripe) | ✅ | ⚠️ (sem Apple Pay) | ⚠️ (via `pay.html`, kill-switch) |
| 2b | Cartão guardado / 3DS off-session | ✅ | ✅ | ❌ |
| 2c | Cartão em Limpeza / Lavagem / Marcações / Planos TVDE | ✅ | ✅ | ❌ |
| 2d | MB Way (`create-mbway-payment-intent`; `mbway_enabled=true` lido por SELECT) | ✅ | ✅ | ✅ |
| 2e | Dinheiro | ✅ | ✅ | ✅ |
| 2f | Wallet/tokens (RPCs) | ✅ | ✅ | ✅ |
| 2g | Pagar dívida (`pay_debt_modal`) | ✅ | ✅ | ⚠️ |
| 3a | Galeria (image_picker) | ✅ | ✅ | ✅ |
| 3b | Câmara (`ImageSource.camera`) | ✅ | ✅ | ⚠️ |
| 3c | `retrieveLostData()` no arranque | ✅ | ✅ (era ❌; corrigido) | ✅ (era ❌; corrigido) |
| 4a | GPS em segundo plano do estafeta | ✅ | ⚠️ | ❌ |
| 4b | Foreground service / notificação persistente | ✅ | ⚠️ | ❌ |
| 4c | Gate de permissões do estafeta (bateria, overlay, exact alarm) | ✅ | ⚠️ | ⚠️ |
| 5a | Mapa (google_maps_flutter) | ✅ | ✅ | ⚠️ |
| 5b | Directions / autocomplete | ✅ | ✅ | ✅ |
| 5c | Navegação externa (Google Maps / Waze) | ✅ | ✅ | ✅ |
| 6 | Chat TVDE e chat de pedido | ✅ | ✅ | ✅ |
| 7a | Login / registo e-mail | ✅ | ✅ | ✅ |
| 7b | Sign in with Apple / Google | ❌ | ❌ | ❌ |
| 7c | **Apagar conta** (cliente, estafeta, parceiro) | ✅ | ✅ | ✅ |
| 8a | Reservas, Serviços, Takeaway, Mercados, Limpeza, Lavagem | ✅ | ⚠️ | ✅ |
| 9a | Biometria (login + confirmação de pagamento) | ✅ | ✅ | ❌ |
| 9b | Deep link reset-password | ✅ | ✅ | ✅ |
| 10 | Actualização da app (AppUpdateGate) | ✅ | ✅ (era ❌; corrigido) | ✅ (sai de propósito; era ❌) |

**Porquê de cada ❌/⚠️ (ficheiro:linha):**
- 1a web ⚠️ — token só depois do toque em "Ativar notificações" (`notification_service.dart:1735`,
  `widgets/driver_web_cards.dart:12`); no iPhone só com a PWA no ecrã principal (iOS ≥16.4).
- 1b iOS ⚠️ / web ❌ — as 9 chamadas de `NotificationDetails(android: …)` em `notification_service.dart`
  (:113,:191,:280,:450,:872,:994…) e `incoming_job_alert.dart:101` não têm `DarwinNotificationDetails` (0
  ocorrências em `lib/`): no iOS a notificação local sai genérica, sem som próprio; na web `init()` sai em
  `:1777 if (kIsWeb) return`.
- 1c iOS ⚠️ — era o `apns-push-type: background` (G1.7); web ⚠️ depende do SW e da permissão do 1a.
- 1d web ⚠️ — `audioplayers` só toca depois de um gesto; o estafeta desbloqueia em `driver_home_screen.dart:365`,
  o **parceiro não tem desbloqueio** antes de `partner_dashboard_screen.dart:418 playLoop()`.
- 1e — `floating_bubble_service.dart:38/53/64 if (!Platform.isAndroid) return`; `flutter_overlay_window` é
  Android-only.
- 2a iOS ⚠️ — Apple Pay desligado na v1 (`config/ios_launch_flags.dart:10-15`, usado em `payment_service.dart:117`
  e 3 ecrãs); web ⚠️ — `payment_service.dart:87-98` desvia para `web/pay.html` só se
  `platform_settings.web_card_payments_enabled`.
- 2b/2c web ❌ — `payment_service.dart:334/356` (`kIsWeb` → lista vazia / `StateError`), snack "apenas em
  dispositivos móveis" em `payment_method_screen.dart:945`, `cleaning_payment_flow.dart:47`,
  `carwash_payment_flow.dart:51`, `services_store.dart:390`, `tvde_plans_screen.dart:126`;
  `reservation_payment_method_sheet.dart:120/169` mostra cartão **sem guarda** e cai em `StateError` na web.
- 3b web ⚠️ — nenhum chamador de `SafeImagePicker` tem `kIsWeb` (ex. `profile_screen.dart:191`,
  `errand_form_screen.dart:337`); no desktop a câmara vira input de ficheiro.
- 4a iOS ⚠️ — entregas têm `AppleSettings(allowBackgroundLocationUpdates)` (`driver_home_screen.dart:728`) e
  `UIBackgroundModes location` ✅, mas o TVDE usa `LocationSettings` genérico fora do Android
  (`tvde_corrida_localizacao_service.dart:88`) e `tvde_ride_active_screen.dart:295 if (kIsWeb) return`; web ❌
  sem background (só wake lock com separador visível).
- 4b — `foreground_service.dart:18` "não há FS real no iOS" (BGTaskScheduler); web só não rebenta pelo `try/catch`.
- 4c — `permission_gate_service.dart` exige `isIgnoringBatteryOptimizations` (:281), overlay (:140),
  fullScreenIntent (:173) — conceitos Android — sem `kIsWeb`/`Platform`.
- 5a web ⚠️ — Maps JS com chave hard-coded no `web/index.html` (`boraMapsEstado`); ícones custom desligados
  (`liteModeEnabled: !kIsWeb`).
- 7b — `register_client_screen.dart:318-335` é `TODO(activate)`; sem `sign_in_with_apple`/`google_sign_in`.
- 8a iOS ⚠️ — `ios_hide_nonpartner_logos` (`config/ios_launch_flags.dart:53-66`) esconde logos de mercados
  não-parceiros em `restaurants_screen.dart:456` e `stores_screen.dart:492` (`false` na base hoje).
- 9a web ❌ — `payment_biometric_gate.dart:16,28` "na web não há local_auth".

Call-sites que classificavam a web como iOS: só o `main.dart:299` (arranjado). `ios_launch_flags.dart:24`
usa `defaultTargetPlatform` sem `kIsWeb` — num iPhone no Safari comporta-se como iOS (esconde logos, Apple Pay
off); inofensivo, reportado.

---

## 4. PAINEL ADMIN — o que acrescentei / o que falta acrescentar

**Acrescentei (PT-BR):**
- Ecrã **"Erros da app (crashes)"** (secção Operação): filtro por plataforma e janela, contagem por
  plataforma, versão/aparelho/sistema por linha, detalhe com stack. Policy de leitura só-admin.
- Definições → categoria `APP_UPDATE`: as 5 chaves (`app_latest_version_code`, `_ios`,
  `app_min_supported_version_code`, `_ios`, `app_update_notes_pt`) passam a ter lápis (eram cadeado).
  Vão pelo `admin_update_setting` com auditoria em `admin_audit_log`.
- Os avisos da caixa de entrada (`admin_notifications`) passam a abrir o ecrã certo em vez de rebentar
  (`/admin/users`, `/admin/tvde`, `/admin/orders`, `/admin/robot-suggestions`, `/admin/ledger`, `/admin/limpeza/*`).

**Falta (não construí):**
- Um quadro "Aparelhos por plataforma" (tokens de push android/ios/web por papel, últimos 7 dias) — hoje só
  por SQL. Seria o sítio onde o Danilo veria o primeiro iPhone a registar-se.
- Um botão "Enviar push de teste a este aparelho" na ficha do estafeta/cliente — a prova do G1 hoje faz-se
  por SQL + Edge.
- O quadro de fotos mortas do catálogo (se a varredura proposta em G5.4 for aprovada).

---

## 5. FORA DO SCOPE — ENCONTREI MAS NÃO MEXI

1. **O web publica sem autoteste** (G0 divergência 2): a regra "build com autoteste vermelho não sai" só vale
   no Android. Caminho: duplicar o job `autoteste` no `build_web_deploy.yml` com `needs:` (custa ~30 min de
   CI por push, 0 € por o repo ser público) — decisão do Danilo.
2. **`notification_failures` só recebe limpeza e lavagem** — os `notify-*` de cliente/estafeta/parceiro/TVDE
   ainda só fazem `console.error` (o próprio ecrã "Avisos que falharam" já o diz).
3. **`flutter_local_notifications` sem `DarwinNotificationDetails`** em 9 chamadas — no iPhone a notificação
   *local* (quando a app está aberta) sai sem o som da Bora (1b). O push remoto já leva som via `apns`.
4. **O parceiro na web não desbloqueia o áudio** antes do `playLoop()` (1d) — o som do pedido novo pode não
   tocar no browser do parceiro até um gesto.
5. **`reservation_payment_method_sheet.dart` mostra cartão na web sem guarda** (2c) — cai em `StateError`.
6. **`ios_launch_flags.dart:24`** decide "é iOS" por `defaultTargetPlatform` sem `kIsWeb`.
7. **Repo público com `AppDelegate.swift` a dizê-lo** — está bem gerido (chaves por segredo), só a registar.
8. **`.supabase-token.env`** na raiz do repo (gitignored) com um PAT expirado (401) — lixo a rolar.
9. **`analysis_options.yaml`, `android/gradle.properties`, `ios/LANCAMENTO-IOS-ESTADO.md`, registrants
   linux/windows e 6 PNGs de goldens** estão modificados na árvore por **outra sessão** — não os toquei nem
   committei (commit por caminhos explícitos).
10. **Memória antiga dizia que o CI não gravava `app_latest_version_code`** — hoje grava (614 lido por
    SELECT, passo presente no workflow). Corrigi a memória do PC.
11. **`Null check` em `product_detail_screen`, `cleaning_chat_button`, `support_chat_screen`** — ver G5.2.
12. **Store `platform_settings.web_card_payments_enabled`** desliga o cartão na web — não é bug, é interruptor.

---

## CI do push `317db0c7` (provas lidas da API do GitHub e por SELECT)

- **Build & Deploy Web** run 143: **verde**. `https://app.boraguarda.com/versao.json` (sem cache-buster) →
  `commit 317db0c7`, run 143, 18:02 UTC; o `index.html` no ar tem `window.boraBuildCommit`; o
  `firebase-messaging-sw.js` no ar carrega `firebasejs/12.19.0`; o `main.dart.js` novo (9,99 MB) contém
  "Erros da app (crashes)" e "web (sem carimbo)".
- **Build Android & Deploy** run 448: **autoteste dos 3 perfis VERDE com o Firebase 16.7** (o APK de teste
  compilou o Gradle novo — era o maior risco do upgrade), **Build AAB + upload ao Play VERDE**
  (internal + alpha + production). Commit `1e81a08d ci: bump versionCode to 615 [skip ci]` no ramo;
  `platform_settings.app_latest_version_code = 615` lido por SELECT (614 → 615).
- **olho-golden** run 127: verde.
- iOS: **não corre no push de produção** (por desenho) — fica para o "vai".

Um segundo commit (`[skip ci]`) leva este relatório, uma guarda extra no `PushTokenService` (o
`onTokenRefresh` em try/catch para uma app sem Firebase inicializado — o main() engole essa falha e a
app "segue sem notificações"; validado por analyze + 7 testes) e a telemetria do CEO-AI.
