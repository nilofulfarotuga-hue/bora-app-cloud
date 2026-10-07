# Paridade Android / iPhone / web — auditoria só de leitura (07/10/2026)

## Base e condições

- Árvore julgada: `C:\BoraLocal\_auditoria-3p`, commit de produção **`383708b4`** (= `origin/autonomous-night-2026-04-29`,
  "ci: bump versionCode to 655", 07/10 04:16 UTC). A web no ar confirma o mesmo código: `versao.json` devolve
  o commit `4a6dc611` (último commit de código antes do bump).
- **Atenção:** durante a auditoria outra sessão escreveu na mesma árvore 5 commits locais, **não empurrados**, por cima
  de `383708b4` (`e0d01173`, `df745a21`, `570d68cf`, `58032b57`, `a0a69eda`; HEAD destacado, `origin` continua em
  `383708b4`). Todas as linhas citadas abaixo são de `383708b4` (lidas com `git show 383708b4:<ficheiro>`).
  O `58032b57` ("serviço de localização só se liga com a app à frente") corrige o GAP 1 no Android, mas ainda **não
  está em produção**.
- Nada foi editado, nada foi commitado, nenhum build corrido. Leituras: código, `git log/show`, manifesto fundido
  local (`build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`, de 01/10),
  código dos plugins na cache do pub, SELECT na base (`debug_crash_logs`, `*_push_tokens`, `platform_settings`,
  `orders`, `drivers`) e cabeçalhos HTTP reais de `bora-app-web.pages.dev` e `app.boraguarda.com`.
- Memória: medidos **250 MB** disponíveis no arranque (abaixo do portão leve de 400 MB). Avancei porque a ordem só lê
  ficheiros, base e HTTP — nada compila — e não havia playwright/nano-banana a correr para libertar. No fim: 4571 MB.

## Resposta às cinco verificações pedidas

**(a) Serviço em primeiro plano de localização no Android — GAP-REAL (o manifesto está certo; o arranque não).**
O manifesto tem tudo: `FOREGROUND_SERVICE` e `FOREGROUND_SERVICE_LOCATION` (`android/app/src/main/AndroidManifest.xml:7,9`),
e o serviço do geolocator entra no manifesto fundido com `foregroundServiceType="location"`
(`com.baseflow.geolocator.GeolocatorLocationService`, linha 383 do manifesto fundido). O serviço do
`flutter_foreground_task` fica com `dataSync|remoteMessaging` de propósito (`AndroidManifest.xml:150-154`) e as
permissões desses tipos existem (`:12`, `:47`). targetSdk = 36 (manifesto fundido, linha 9).
O erro real, lido na base: 4 vezes (26/09, 27/09, 29/09, 03/10), builds 625 e 639, um só aparelho (Samsung SM-A366B,
Android 16), de um estafeta aprovado `work_mode=everything` que está online hoje. Mensagem completa:
"Starting FGS with type location … requires … ACCESS_COARSE_LOCATION|ACCESS_FINE_LOCATION **and the app must be in the
eligible state/exemptions to access the foreground only permission**", ecrã "while activating platform stream on
channel flutter.baseflow.com/geolocator_updates_android". Ou seja: a permissão "só enquanto se usa" estava dada, mas o
GPS com serviço foi ligado com a app em fundo. Causa no código:
`lib/services/localizacao_online.dart:86-91` e `lib/services/tvde_corrida_localizacao_service.dart:168-174` só verificam
se a permissão existe, nunca se a app está à frente. A home TVDE liga o GPS depois de esperar até 15 s por uma posição
(`tvde_driver_home_screen.dart:630` → `:652`) e volta a ligá-lo quando a corrida devolve o GPS
(`_onCorridaGpsChanged`, `:584-593`) — as duas coisas podem acontecer com a app já em fundo. Pior: no Android o
plugin arranca as posições e só depois rebenta no `enableBackgroundMode` (`StreamHandlerImpl.java` do
geolocator_android 5.1.1+1, linhas ~128-130); o `EventChannel` apanha a excepção, anula o canal e o Flutter só
regista o erro — **o `onError` do `listen` nunca é chamado**. O `_gps` fica preenchido e morto, e o
`didChangeAppLifecycleState` (`:145-159`) não religa o GPS. O motorista continua "online" sem posições em fundo
(o batimento de reserva `heartbeat_service.dart:262-300` também não consegue ler GPS em fundo só com "enquanto se usa").
**Correcção mínima:** só passar `foregroundNotificationConfig` quando `WidgetsBinding.instance.lifecycleState ==
AppLifecycleState.resumed` ou a permissão for `always`; quem abriu o GPS sem serviço religa-o no `resumed`. É
exactamente o que faz o commit local `58032b57` — falta empurrá-lo. **Resto que o `58032b57` não cobre:**
`lib/screens/driver_map_screen.dart:356-370` (mapa da entrega activa) passa o `ForegroundNotificationConfig` sempre,
sem olhar ao ciclo de vida, e não religa no `resumed`; a janela é curta (só `isLocationServiceEnabled`,
`checkPermission` e `getLastKnownPosition` com tempo limite de 5 s antes do `listen`), mas se o estafeta sair da app
nesse intervalo o GPS da entrega fica morto até sair do mapa.

**(b) Info.plist do iPhone — OK.** Tudo o que a app pede em tempo de execução tem chave: câmara
(`NSCameraUsageDescription`), fotos (`NSPhotoLibraryUsageDescription`), Face ID (`NSFaceIDUsageDescription`),
localização "enquanto se usa" e "sempre" (as três chaves `NSLocation…`), `UIBackgroundModes` com `location`, `fetch`,
`remote-notification`, `processing`, e `BGTaskSchedulerPermittedIdentifiers` para o `processing`. Notificações não
precisam de chave. Não há microfone (nenhum `pickVideo`, nenhuma gravação), nem contactos, calendário ou bluetooth.
Esquemas consultáveis: `tel`, `whatsapp`, `maps`, `comgooglemaps`, `mailto`. Esquema de retorno `pt.boraapp.bora`
em `CFBundleURLTypes`, igual ao `Stripe.urlScheme` (`lib/main.dart:629`) e ao link antigo de recuperação.
O que falta não é do plist, é das *entitlements*: ver GAP 2 (notificações "time-sensitive").

**(c) Web — caminho ou mensagem para o que é só de telemóvel — PARCIAL.**
Cartão: o checkout principal paga pela `web/pay.html` (Stripe Payment Element) e o interruptor
`platform_settings.web_card_payments_enabled` está `true` (SELECT, 22/09); cartões guardados não aparecem na web
(`payment_service.dart:351`) — OK. Limpeza, lavagem e planos TVDE mostram "O pagamento por cartão/do plano está
disponível na app móvel." (`cleaning_payment_flow.dart:48`, `carwash_payment_flow.dart:52`,
`tvde_plans_screen.dart:143`) — mensagem clara, mas paridade incompleta e é zona de dinheiro (ver ZONA-PROTEGIDA).
GPS em fundo: o estafeta de entregas na web vê "Para receberes pedidos sempre, mantém o ecrã ligado e a Bora aberta."
(`widgets/driver_web_cards.dart:101`) — OK. O motorista TVDE na web não tem esse cartão (só `driver_home_screen.dart:1422`
o mostra) — sem motoristas web activos hoje (SELECT: os 4 aprovados activos em 14 dias são todos `android_app`).
Notificações: o estafeta, a limpeza e a lavagem têm push web pelo `firebase-messaging-sw.js`; **o cliente e o
restaurante parceiro na web não têm caminho nenhum** — ver GAP 5. Biometria na web passa à frente de propósito
(`payment_biometric_gate.dart:45`) — NAO-APLICAVEL.

**(d) Chave do Maps no iPhone — OK.** `ios/Runner/Info.plist:131-132` pede `$(GOOGLE_MAPS_API_KEY)`;
`ios/Flutter/Release.xcconfig` e `Debug.xcconfig` fazem `#include? "BoraSecrets.xcconfig"`; o job `release` de
`.github/workflows/build_ios.yml` escreve esse ficheiro a partir de `.dart_defines` (`:554-556`) e **pára o envio com
erro** se a chave faltar (`:559`) antes do `flutter build ipa` (`:632`); o `AppDelegate.swift` entrega a chave ao
`GMSServices` antes do motor arrancar. O `GoogleService-Info.plist` também é escrito no mesmo job (`:545-548`).

**(e) Cache da web — OK em `bora-app-web.pages.dev`, GAP-REAL em `app.boraguarda.com`.** O `web/_headers` está certo
e é servido em pages.dev: `/`, `/main.dart.js`, `/flutter_bootstrap.js`, `/flutter_service_worker.js`,
`/firebase-messaging-sw.js`, `/firebase-config.js` com `no-cache`, `/versao.json` com `no-store` (medido hoje).
No domínio próprio, que é o canónico da app (`lib/config/auth_links.dart`: `boraWebBaseUrl =
'https://app.boraguarda.com'`), o mesmo build (mesmo ETag) sai com **`cache-control: max-age=14400`** em
`/main.dart.js`, `/flutter_bootstrap.js`, `/flutter_service_worker.js`, `/firebase-config.js` e
`/firebase-messaging-sw.js` (e `cf-cache-status` presente) — o `/` continua `no-cache`. É uma regra da zona Cloudflare
de `boraguarda.com`, não do repositório. Ver GAP 3.

## GAP-REAL, do mais sentido pelos utilizadores para o menos

1. **Android — GPS do motorista/estafeta online morre em fundo (Android 14+ com permissão "enquanto se usa").**
   `lib/services/localizacao_online.dart:86-91` + `:71`, `lib/services/tvde_corrida_localizacao_service.dart:168-174` + `:100`,
   `lib/screens/driver/tvde/tvde_driver_home_screen.dart:630-652` e `:584-593` (arranque em fundo), `:145-159` (não religa).
   Cenário: o motorista fica online e passa para a Uber/Bolt antes de chegar a primeira posição, ou termina uma corrida
   com a app em fundo; o GPS fica calado até reabrir/voltar a ficar online; sai do despacho sem saber. Provado 4× na base
   num estafeta activo. Correcção mínima: a do commit local `58032b57` (serviço só com app à frente ou "sempre", religar
   no `resumed`) — empurrar; e aplicar a mesma regra ao `lib/screens/driver_map_screen.dart:356-370`, que esse commit
   não toca.

2. **iPhone — as ofertas e pedidos novos não furam o modo Foco/Condução.** Os servidores pedem
   `interruption-level: time-sensitive` em `notify-driver`, `notify-partner`, `notify-driver-assigned` e
   `notify-tvde-driver` (ex.: `supabase/functions/notify-tvde-driver/index.ts:461,589,682`), mas
   `ios/Runner/Runner.entitlements` só tem `aps-environment`; sem a entitlement
   `com.apple.developer.usernotifications.time-sensitive` o iOS trata-as como notificação normal. Cenário: motorista
   ou estafeta no iPhone com o Foco "A conduzir" (liga-se sozinho no carro) ou "Não incomodar", e o restaurante parceiro
   com iPhone em Foco: a oferta/pedido chega calado. O som `bora_alert.wav` está no bundle (pbxproj, Resources) — isso está
   bem. Correcção mínima: activar a capacidade "Time Sensitive Notifications" no App ID `pt.boraapp.bora` (portal da
   Apple, regenerar o perfil) e acrescentar `<key>com.apple.developer.usernotifications.time-sensitive</key><true/>`
   ao `Runner.entitlements`. Hoje: 2 tokens iOS de estafeta e 1 de parceiro activos.

3. **Web (domínio canónico) — quem abre `app.boraguarda.com` pode correr código com até 4 horas.** Cabeçalhos medidos
   hoje (acima). O `index.html` vem fresco e o carimbo `COMMIT` dele bate com o `versao.json`, por isso a verificação de
   versão (`web/index.html:98-140`) não recarrega — mas o `flutter_bootstrap.js` e o `main.dart.js` (carregados pelo nome
   simples, sem hash) saem da cache do navegador. Cenário: corrige-se um bug às 10h, o cliente que abriu a app às 9h e
   volta às 11h continua com o bug. Correcção mínima: na zona `boraguarda.com` da Cloudflare, Caching → Browser Cache TTL
   = "Respect Existing Headers" (ou uma Cache Rule para `app.boraguarda.com` com Browser TTL "respeitar a origem").
   Não precisa de código.

4. **iPhone — GPS da entrega activa e da corrida TVDE pára quando a app vai para fundo.**
   `lib/screens/driver_map_screen.dart:372-377` (ramo não-Android usa `LocationSettings` simples) e
   `lib/services/tvde_corrida_localizacao_service.dart:88-93` (idem). No `geolocator_apple 2.3.14` o
   `allowBackgroundLocationUpdates` só é ligado se vier nos argumentos (`PositionStreamHandler.m:52,61`); o
   `LocationSettings` simples não o manda → `NO`. Como a stream da home (que tinha `AppleSettings` com fundo) é cancelada
   ao abrir o mapa (`driver_home_screen.dart:831-834`) e ao a corrida assumir o GPS, não fica nenhuma stream com fundo:
   o iOS suspende a app, as posições e o batimento param. Cenário: estafeta ou motorista com iPhone abre o Waze/Google
   Maps a meio da entrega/corrida — o cliente vê o carro parado e o servidor marca-o offline aos 90 s. Hoje 0 motoristas
   iOS activos (SELECT `drivers`), mas é o que o Danilo quer igual. Correcção mínima: no iOS usar
   `AppleSettings(accuracy: bestForNavigation, distanceFilter: 5 (mapa) / 3 (TVDE), activityType:
   ActivityType.automotiveNavigation, pauseLocationUpdatesAutomatically: false, allowBackgroundLocationUpdates: true,
   showBackgroundLocationIndicator: true)` nesses dois sítios, mantendo o `LocationSettings` simples só para a web.
   (O commit local `58032b57` diz "iPhone e web sem mudança" — não resolve isto.)

5. **Web — cliente e restaurante parceiro não recebem push nenhum.** `lib/services/notification_service.dart:2715-2719`
   (`saveTokenForClient`) e `:2764` (`saveTokenForPartner`) saem se `_fcmToken` for nulo; na web `init()` sai logo
   (`:2052`) e o `initWeb()` (`:2010`) só preenche o token no `onTokenRefresh` e só o grava para o estafeta (`:2043`).
   Base: `client_push_tokens` web = 1 token em toda a história (Android 443, iOS 26); `partner_push_tokens` web = 0.
   E o `web/firebase-messaging-sw.js:54-55,73` manda qualquer clique para `/#/driver`. Cenário: cliente que pediu pelo
   site (4 dos 34 pedidos dos últimos 30 dias) fecha o separador e não sabe que o estafeta está a caminho; restaurante
   no navegador com a página fechada não sabe do pedido novo. Correcção mínima: botão "Ativar notificações" para o
   cliente (depois de fazer o pedido) e para o parceiro, que chama `PushTokenService.registerForRole('client'|'partner')`
   no toque (igual ao `DriverStore.registarPushAposToque`); no SW, escolher o URL do clique pelo `type`/`role` do payload.

6. **Web — cada publicação apaga a subscrição de push de quem abrir a app a seguir.** `web/index.html:124-126`
   desregista **todos** os service workers, incluindo o `firebase-messaging-sw.js`, quando há versão nova (várias vezes
   por dia). Já provado a 02/10 (memória `prova-web-nao-apagar-service-worker-do-firebase`): desregistar o SW do Firebase
   mata o token e o envio seguinte dá `UNREGISTERED` com HTTP 200. Estafeta/limpeza/lavagem voltam a registar token ao
   abrir (`tvde_driver_home_screen.dart:130`, `cleaner_home_screen.dart:51`, `washer_home_screen.dart:54`), mas fica um
   token morto `active=true` na base a cada publicação, e no iPhone (PWA) não está provado que o novo registo sem toque
   funcione. Correcção mínima: no `index.html`, só desregistar os SW cujo `active.scriptURL` não contenha
   `firebase-messaging-sw.js` (a mesma regra que a memória pede para o arnês de provas).

7. **iPhone — o aviso "há versão nova" está desligado.** `platform_settings.app_latest_version_code_ios = 0`
   (SELECT; o CI não a escreve, `admin_platform_settings_screen.dart:303-304` diz que é à mão). O Android é avisado
   sozinho (`app_latest_version_code = 655`, escrito pelo `build_android.yml:330-344`). Cenário: os iPhones nos logs
   de erro ainda correm 648/649 enquanto os consertos vão até 655; o iPhone é a plataforma com mais pedidos
   (13 de 34 em 30 dias). Correcção mínima: quando a Apple aprovar uma versão, pôr no painel o número de build que está
   na loja (chave operacional, não é dinheiro).

8. **Web no Safari (iPhone/iPad) — o som do pedido novo do restaurante e da oferta TVDE não toca.** O áudio só se
   desbloqueia no toque "Ficar online" do estafeta de entregas (`driver_home_screen.dart:406` →
   `sound_service.dart:93`). O painel do parceiro chama `playLoop()` sem desbloqueio (`partner_dashboard_screen.dart:553`)
   e a oferta TVDE também (`tvde_offer_screen.dart:86`); o Safari só deixa tocar som a um elemento que já tocou dentro
   de um toque. Correcção mínima: chamar `desbloquearAudioAposToque()` no primeiro toque do painel do parceiro (abrir
   loja) e no "Ficar online" do TVDE quando `kIsWeb`.

9. **Android — o botão de e-mail do suporte não faz nada.** `lib/screens/support_screen.dart:129`
   (`if (await canLaunchUrl(mailto)) launchUrl`). O manifesto fundido só torna visíveis navegadores (`VIEW http`),
   Chrome, Google Maps e marcador (`DIAL tel`); sem `<queries>` para `mailto`/`SENDTO`, o `canLaunchUrl` dá falso no
   Android 11+ (README do `url_launcher`, e o próprio código já o reconhece em `legal_info_screen.dart:287`). No iPhone
   (`mailto` está em `LSApplicationQueriesSchemes`) e na web funciona. Correcção mínima: tirar o `canLaunchUrl` e
   apanhar o erro do `launchUrl` como em `legal_info_screen.dart`, ou acrescentar `<intent><action
   android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>` ao `<queries>`.
   (Os `tel:` funcionam: o marcador é visível pela query `DIAL tel`; o `https://www.google.com/maps/dir` do
   `botao_rota.dart:46` também, porque Maps e navegadores são visíveis.)

10. **iPhone — notificações locais saem com som e apresentação de origem.** As 11 chamadas `NotificationDetails(android:
    …)` sem `iOS:` (`notification_service.dart:114,192,288,469,899,1202,1476,1782,3061`, `incoming_job_alert.dart:101`,
    `tvde_arriving_notice.dart:49`; 0 `DarwinNotificationDetails` em `lib/`). Só pesa com a app aberta (em fundo o
    iPhone recebe o push do servidor, que já leva `bora_alert.wav`). Correcção mínima: acrescentar
    `iOS: DarwinNotificationDetails(sound: 'bora_alert.wav', interruptionLevel: InterruptionLevel.timeSensitive)` nas
    de pedido/oferta. Baixo impacto.

## Consertos desde 01/09 que tocam código de plataforma (186 commits em lib/ios/android/web; 48 tocam APIs de plataforma)

| Commit | O quê | Android | iPhone | Web |
|---|---|---|---|---|
| 85329cbf, 172a2734, a9ad9b26 (07/09) | Projecto iOS, plist, privacidade, esquema de retorno 3DS | n/a | OK | n/a |
| c50bf059 (08/09) + build_ios.yml | Chave do Maps no iOS | OK (manifesto) | OK (xcconfig + CI que pára sem chave) | OK (index.html) |
| db3de1fc, c3443c90, bcd09aa4, 6fe5c690 (10/09) | Face ID no plist, Firebase plist empacotado, notificações locais e permissão no iOS | OK | OK (GAP 10 menor) | n/a |
| 39578eb5 (10/09) | Pedido de permissão de localização nunca lança | OK | OK | OK |
| c2f54047 (07/09) | Plataforma do pedido gravada | OK | OK | OK (sem nulos desde 22/09) |
| d90ea319, 80cc1e20 (05/09) | Uma só stream de GPS na corrida TVDE com serviço | GAP 1 (arranque em fundo) | **GAP 4** | OK (fica a stream da home) |
| 52ba6154 (17/09) | Estafeta no navegador: presença, push, wake lock | n/a | n/a | OK para estafeta; **GAP 5, 6** |
| 277c65e8, e53a914d (21/09) | Push iOS, crash log 3 plataformas, aviso de versão por plataforma | OK | OK (push); **GAP 7** (aviso a 0) | OK |
| 7f7f5e92 (21/09) | Oferta TVDE por cima de tudo + botões na notificação | OK | Botões só no Android (iOS abre a app e o cartão aparece) — NAO-APLICAVEL | OK (cartão) |
| 8e7c91e3 (22/09), 1d731b65 (03/10) | Cartão no iPhone (folha Stripe, janela UIScene) | OK | OK | pay.html — ZONA-PROTEGIDA, não re-testado |
| 80092026, 5617c001 (23/09) | GPS online com serviço + batimento com posição | **GAP 1** | OK (AppleSettings com fundo) | OK |
| 75143a93 (30/09) | Fiscalização TVDE, SOS com partilha | OK | OK | OK (`/fiscalizacao` 200) |
| 136fff32 (29/09) | Extrato mensal do parceiro em PDF | OK | OK | OK (printing na web) |
| e02c8db0 (04/10) | Sair pára o serviço, um só batimento, foto à porta | OK | OK | OK (foto pelo `io_compat`) |
| a40db532, 2adfca36 (04/10) | Partilhar viagem / partilhar seguimento | OK | OK | OK (ver "por provar") |
| ac638cff, 2b6f4bd2 (04/10) | Pacote TVDE pago na web cria a ida | n/a | n/a | OK (zona de pagamento) |
| 168246ea (04/10) | Lojas por telefone (`tel:`) | OK | OK | OK |
| bcb474f9, b7e529be, 13aed4ff (06/10) | Cartão "Nova corrida" preso | mesmo código nas três | | |
| `web/_headers` (31/08, 16/09) | Cache da web | n/a | n/a | OK em pages.dev; **GAP 3** no domínio próprio |

## OK confirmado (sem acção)

Manifesto Android (tipos e permissões de serviço, `POST_NOTIFICATIONS`, `CAMERA`, `READ_EXTERNAL_STORAGE` só até 32,
biometria; `MainActivity : FlutterFragmentActivity`, que o `local_auth` exige). Info.plist completo. Maps no iPhone.
Recuperação de palavra-passe vai sempre para a página https da web (`auth_links.dart`), igual nas três; o link antigo
`pt.boraapp.bora://reset-password` está declarado no Android e no iPhone. `Platform.is*` não rebenta na web (shim
`utils/io_compat_web.dart`). Exportações do admin na web descarregam (`admin_export_service.dart:52,86,159`). Fotos na
web lêem-se pelo `File` do `io_compat` (blob URL). Cache em `bora-app-web.pages.dev`. `/viagem`, `/fiscalizacao` e
`/pay` respondem 200 no domínio próprio.

## NAO-APLICAVEL

Bolha flutuante e janela por cima de outras apps (`floating_bubble_service.dart:38,53,64`, `flutter_overlay_window`)
só existem no Android. Serviço em primeiro plano não existe no iPhone nem na web (`foreground_service.dart` cai no
`try/catch`). Biometria na web. Botões de aceitar/recusar dentro da notificação no iPhone (o toque abre a app e o
cartão global mostra a oferta).

## ZONA-PROTEGIDA (não proponho mexer)

Cartão na web para limpeza, lavagem e planos TVDE: mensagem clara "disponível na app móvel", mas sem caminho de
pagamento na web (`cleaning_payment_flow.dart:48`, `carwash_payment_flow.dart:52`, `tvde_plans_screen.dart:143`).
É Stripe/pagamentos (lista vermelha): fica registado, não se propõe código.

## POR PROVAR (código concreto, efeito não medido num aparelho)

- **Android 15/16 — limite de 6 h do tipo `dataSync`.** O serviço do `flutter_foreground_task` corre com
  `dataSync|remoteMessaging` (`AndroidManifest.xml:154`), targetSdk 36, e o plugin 8.17.0 não implementa `onTimeout`
  (procurei no código do plugin: 0 ocorrências). Se o limite do `dataSync` se aplicar a um serviço com os dois tipos,
  um turno online de mais de 6 h termina com o sistema a matar o serviço/app. Os erros nativos não chegam ao
  `debug_crash_logs`; provar com um turno real de 6 h+ num Android 15/16 e ver o `adb logcat`.
- **Web no Safari — partilhar depois de esperar pela rede/GPS.** `tvde_partilha_service.dart:31-33` chama `Share.share`
  depois do `await criarLink(...)`, e o SOS (`tvde_sos_button.dart:111-116`) depois do `await _posicaoRapida()`. O
  `navigator.share` exige o toque "fresco"; se o Safari o recusar, o utilizador vê "Não foi possível criar o link da
  viagem" (mensagem errada). Provar num iPhone pelo navegador.

## PARA O DANILO

1. GAP 2: activar "Time Sensitive Notifications" no App ID `pt.boraapp.bora` no portal da Apple (é uma caixa no
   portal; depois o executor põe a entitlement e o CI gera o perfil novo).
2. GAP 3: na Cloudflare (zona `boraguarda.com`), Browser Cache TTL = "Respect Existing Headers". Pode ser o executor
   pelo perfil Bora do Chrome (a Cloudflare está nesse perfil).
3. GAP 7: quando a Apple aprovar a próxima versão, pôr o número de build no painel em `app_latest_version_code_ios`.
4. GAP 1: o conserto já existe como commit local `58032b57` na árvore `_auditoria-3p`, por empurrar.
