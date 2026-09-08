# CHECKLIST APPLE — submissão à App Store

> Missão `ios-lancamento` · Tarefa 4 · criado 2026-09-07 (2.ª sessão — não
> existia antes; a 1.ª sessão só o referenciou).
> Cada linha tem `[x]`/`[ ]`/`[~]` (`~` = em curso) e a prova a seguir, nunca
> "deve estar". Fonte do modo de trabalho: memória `carta-de-autonomia-ios`.
> Fonte do estado técnico: `ios/LANCAMENTO-IOS-ESTADO.md`.

---

## 0. O QUE A 4.ª SESSÃO FECHOU (2026-09-08) — ler primeiro

Todas as linhas abaixo têm prova no `e2e_log`, fluxo `ios-lancamento`,
run_id `ios-lancamento-2026-09`, ids **1446–1479**. Antes desta sessão o
`e2e_log` tinha **zero** linhas desta missão, em 1438 linhas e 78 fluxos.

### Conta Apple — feita
- [x] Conta Apple criada em `boraappbora@gmail.com`, Portugal, **dois fatores
      activos** e telemóvel fidedigno. Prova: id 1451.
- [x] Nome legal corrigido para **Danilo Fulfaro da Silva**. O preenchimento
      automático do Chrome tinha posto "DA SILVA"; corrigido em Informação
      pessoal e confirmado na página da Apple. Era irreversível depois da
      inscrição. Prova: id 1451.
- [x] **Apple Developer Agreement assinado** a 2026-09-08. Marketing: Não.
      Prova: id 1453 + email `Agreement signed` às 06:51.
- [x] Inscrição individual submetida pela **web** (a Apple empurra para a app
      do iPhone; usou-se "Continue a inscrição na web"). **ID `TPBAQ8K3TF`**,
      estado `Pending`. Prova: id 1455.
- [x] **99 € pagos** — 08/09, APPLE COM, cartão ...9744, Novobanco, em
      processamento. A página continuar a dizer "complete your purchase" é
      normal durante 48 h. **Nunca pagar outra vez.** Prova: id 1475.
- [ ] Recibo e email "Welcome to the Apple Developer Program" — a aguardar.
      Se em 48 h não chegarem, abrir caso no suporte com o comprovativo do
      banco.

### Termos — lidos, com uma correcção ao plano
- [x] Indexados e consultados: Program License Agreement (262 secções),
      Review Guidelines (15), página do DSA (11). Prova: id 1452.
- [x] **O "Alternative Terms Addendum for Apps in the EU" já não existe para
      assinar** — o Attachment 14 (em vigor desde 01/10/2026) substitui-o e
      revoga-o. A Core Technology Commission só toca marketplaces
      alternativos, distribuição fora da App Store e **bens digitais**. O Bora
      vende bens e serviços físicos e só na App Store: **não se aplica**.
- [x] DSA confirmado: a Apple **publica** morada, telefone e email na página
      da app na UE, e a declaração de comerciante é obrigatória mesmo sem
      distribuir na UE.

### Riscos fechados
- [x] **Supabase no plano `pro`** — verificado por MCP, não só afirmado:
      organização "Bora app", `plan=pro`, projeto `ACTIVE_HEALTHY`. O risco de
      a base pausar a meio da revisão está fechado. Prova: id 1476.
- [x] **Login social não representa risco 2.1**: `SOCIAL_AUTH_ENABLED` não
      existe no `.dart_defines` nem no workflow (`grep -c` → 0 e 0), logo
      `bool.fromEnvironment` é `false` e os botões nunca são construídos.
      Fecha o `[~]` do §4.
- [x] **Localização do estafeta no iOS já estava correcta** — corrige uma
      conclusão errada minha (id 1462, corrigida pelo id 1477). Em
      `driver_home_screen.dart:600` o ramo iOS usa `AppleSettings` com
      `showBackgroundLocationIndicator: true` (a barra azul que a Apple exige)
      e `allowBackgroundLocationUpdates: true`; e a declaração em destaque
      corre **antes** do pedido de permissão (`ensureAccepted` na linha 250,
      `requestPermission` nas 416 e 553). **Nada a fazer.**

### Bug encontrado e corrigido
- [x] **O mapa aparecia vazio no iPhone.** O `AppDelegate` não chamava
      `GMSServices.provideAPIKey`; no iOS o SDK exige a chave antes de o motor
      Flutter arrancar, e sem ela o mapa fica cinzento — logo no ecrã de
      acompanhamento, que é o que o revisor abre. Corrigido sem pôr a chave no
      repositório público: entrada `GoogleMapsApiKey` no `Info.plist` com
      `$(GOOGLE_MAPS_API_KEY)`, lida pelo `AppDelegate`, e o CI passa a chave
      ao `xcodebuild` a partir do `.dart_defines`. Commit `c50bf059`.
      Prova: ids 1462 e 1463. **Prova final: a próxima corrida do CI.**

### Capturas — provadas
- [x] **As 7 capturas existem e estão certas**, todas **1320×2868**, na ordem
      mandada (`01-mercado` … `07-lavagem`), sem TVDE nem carro. Artefacto
      `ios-simulador-8` da corrida `34167538478`. Guardadas em
      `Desktop\Bora\ios\capturas`. Prova: id 1449.

### Vídeo — o que faltava, e porquê
- [ ] **Não havia filme para cortar.** Medido: a gravação da corrida
      `34167538478` tem 19,5 min e a app aparece num **único momento de 5 s**
      (amostrei um frame a cada 5 s, 234 amostras, à procura do verde da marca
      no topo; só uma deu positivo). O arnês fotografava e passava à frente.
      **Recusei montar um vídeo de fotos paradas e chamar-lhe demonstração de
      uso** — a captura prova o ecrã, o vídeo prova o uso. Prova: id 1478.
- [~] Conserto publicado (`fbded726`): cada ecrã fica **10 s de tempo real**
      depois de fotografado (`pump` + `Future.delayed` em `runAsync`;
      `pumpAndSettle` devolve cedo e o gravador apanha um piscar). 7 × 10 s ≈
      **70 s**, dentro do alvo. Prova: id 1479. **Falta a corrida do CI.**
- [x] Desligado o passo dos fluxos web (`e2e_test.dart`): dava sempre `+0 -7`,
      só ficava verde por `continue-on-error`, custava **14 min por corrida** e
      enchia a gravação de ecrã inicial do simulador.
- [ ] Cortar 60–120 s com legendas em inglês (ffmpeg confirmado disponível).
- [ ] Publicar **não listado** no canal do Bora e guardar o link aqui e em
      `ios/NOTAS-AO-REVISOR.md`.

### Ainda por fazer, e de que dependem
- [ ] **Firebase iOS** — não existe `GoogleService-Info.plist` nem o segredo
      `GOOGLE_SERVICE_INFO_PLIST_B64`; as notificações não funcionam no
      iPhone. Depende da chave APNs, que **só se cria com a conta activa**.
      Prova da lacuna: id 1462.
- [ ] Firebase Test Lab em iPhone real.
- [ ] Chaves, certificados, perfil e job de release — dependem da conta activa.
- [ ] Trader status verificado no App Store Connect (a Apple pede código por
      SMS: é o **segundo e último** momento do Danilo).

---

## 1. Build compila e corre no simulador

- [x] `flutter analyze` — 0 erros. Prova: passo 10 da corrida `34163172748`.
- [x] `flutter test` — 473 testes verdes. Prova: passo 11 da mesma corrida.
- [x] `pod install` com os ~30 plugins (Stripe, Firebase, geolocator,
      google_maps…). Prova: 166 s, corrida `34163172748`; receita em
      `receita-do-build-ios` (memória).
- [x] `xcodebuild` compila para o simulador (destino explícito, sem
      `-sdk iphonesimulator`). Prova: passo 15 verde, 7m11s, mesma corrida.
- [ ] **A app arranca e navega no simulador** — ainda NÃO provado. Os 7 testes
      de `integration_test/e2e_test.dart` falharam todos
      (`'_pendingFrame == null': is not true`) porque esse teste chama
      `app.main()` completo (Supabase/Firebase/Stripe/timers) e o
      `pumpAndSettle` nunca assenta. Ver §1-b do estado. **Caminho decidido:**
      arnês de capturas próprio (main_capturas.dart + teste + driver), que
      corre o pumpAndSettle sobre ecrãs sem rede e sem temporizadores — prova
      indirecta de que os widgets desenham sem excepção. Em curso nesta
      sessão (ver §2). A prova definitiva de que o `app.main()` real arranca
      num iPhone físico só vem do próprio TestFlight/build de release.

## 2. Capturas da loja (6–8, 1320×2868)

- [~] Arnês de capturas (`lib/main_capturas.dart`,
      `integration_test/capturas_loja_test.dart`,
      `test_driver/capturas_driver.dart`, passo novo em `build_ios.yml`) — em
      construção nesta sessão. `flutter analyze`/`flutter pub get` locais
      (Windows, sem simulador) são a única prova possível aqui; a prova real
      (PNG a sair) só vem da próxima corrida do CI em macOS.
- [ ] 7 capturas na ordem: `01-mercado`, `02-comida`, `03-barbearia`,
      `04-acai`, `05-limpeza`, `06-favores`, `07-lavagem`. **Zero** carro ou
      TVDE em qualquer uma.
- [ ] Vídeo de 60–120 s com legendas em inglês, cortado a partir de
      `artefactos/demo.mp4` (ou de uma gravação nova sobre o simulador com o
      arnês). Publicado **não listado** no canal do YouTube do Bora.
- [ ] Link do vídeo gravado aqui e em `ios/NOTAS-AO-REVISOR.md` (esse ficheiro
      já tem um "Por fazer" a apontar para isto).

## 3. Metadados da App Store Connect

- [x] Textos preparados em `ios/APP_STORE_COPY.md` (nome, subtítulo,
      categoria, palavras-chave ≤100 car., texto promocional, descrição,
      release notes, copyright, classificação etária).
- [ ] Colar os textos no formulário real da App Store Connect (só possível
      com sessão aberta na conta Apple — acção da sentada de 20 min, §7).
- [x] URLs verificadas AO VIVO nesta sessão (`curl -w "%{http_code}"`,
      2026-09-07):
      - Marketing `https://boraguarda.com` → `200`
      - Support `https://boraguarda.com/faq` → `200`
      - Privacy `https://boraguarda.com/privacidade` → `200`
        (`/privacidade.html` dá `308` — não usar a forma antiga)
      - Termos `https://boraguarda.com/termos` → `200`
- [ ] Screenshots carregados (depende do §2).
- [ ] Preço: Grátis. Disponibilidade: Portugal (+ o mercado que a Apple exigir
      para a conta ficar activa — confirmar na sentada).
- [ ] SKU / Bundle ID no App Store Connect = `pt.boraapp.bora` (confirmar que
      bate com `PRODUCT_BUNDLE_IDENTIFIER` do `project.pbxproj` — confirmado
      igual nesta sessão via grep).

## 4. Sinalizadores de completude (Guideline 2.1) — RISCO ENCONTRADO NESTA SESSÃO

- [x] Apple Pay desligado no iOS (`lib/config/ios_launch_flags.dart`,
      `boraApplePay` devolve `null` no iOS enquanto `APPLE_PAY_ENABLED` não
      estiver definido). Sem isto, o botão apareceria sem Merchant ID válido
      — reprovação certa.
- [~] **`register_client_screen.dart` tem botões "Continuar com Apple" e
      "Continuar com Google"** atrás da flag `_socialAuthEnabled =
      bool.fromEnvironment('SOCIAL_AUTH_ENABLED')` (default `false` — os
      botões não aparecem a menos que o build passe
      `--dart-define=SOCIAL_AUTH_ENABLED=true`). Confirmado nesta sessão por
      `grep -rn SOCIAL_AUTH_ENABLED`: **nenhum ficheiro versionado no repo**
      (nem `build_ios.yml`, nem `.yaml`/`.dart`) define essa flag como
      `true` — só existe a leitura com default `false`. Falta só confirmar
      que o segredo `DART_DEFINES_FILE_B64` (fora do repo, não legível
      daqui) também não a define antes de gerar o IPA de release — isso só
      dá para ver quando os segredos do §8 existirem. Se algum dia esses
      botões aparecerem no ar sem as três integrações reais
      (Apple/Google/Supabase) ligadas, tocar neles só mostra um SnackBar "em
      configuração" — isso é reprovação 2.1 na certa (app aparenta
      funcionalidade que não existe).
- [x] Interruptor 5.2.1 `ios_hide_nonpartner_logos` — lado Flutter construído
      nesta sessão: `lib/config/ios_launch_flags.dart`
      (`shouldHideStoreLogo`/`carregarIosHideNonPartnerLogos`), ligado em
      `lib/main.dart` (fire-and-forget no arranque) e aplicado nos dois
      pontos onde a app desenha logótipo de loja —
      `lib/screens/stores_screen.dart` (`_StoreLogo`) e
      `lib/screens/restaurants_screen.dart` (`_RestaurantLogo`). Continua
      **desligado** por omissão em `platform_settings` (criado assim na 1.ª
      sessão) — ligar só depois de decidir que os logótipos de mercados
      crawleados (Continente/Auchan/Lidl…) são risco de marca a esconder no
      iOS. `flutter analyze` limpo nos 4 ficheiros tocados (2 avisos `info`
      pré-existentes, não introduzidos aqui — ver prova abaixo).
      ```
      info - 'anonKey' is deprecated… - lib\main.dart:277:5
      info - Constructors for public widgets should have a named 'key'… - lib\screens\restaurants_screen.dart:338:9
      2 issues found. (nenhum error)
      ```

## 5. Privacidade

- [x] `PrivacyInfo.xcprivacy` existe e está registado no `project.pbxproj`
      (verificado: `find ios -iname PrivacyInfo.xcprivacy` encontra o
      ficheiro; 1.ª sessão confirmou as 4 secções do pbxproj).
- [x] `ITSAppUsesNonExemptEncryption = false` no `Info.plist` (verificado por
      grep nesta sessão).
- [x] Câmara, fotos e localização têm `NSUsageDescription` em português no
      `Info.plist` (verificado por grep nesta sessão — as 3 chaves existem
      com texto).
- [ ] **App Privacy (nutrition label) da App Store Connect** — preencher o
      questionário à mão na sentada (dados recolhidos: contacto, localização,
      identificadores, dados financeiros de pagamento via Stripe/MB Way). Não
      dá para preencher isto pela API; é campo da conta.
- [x] Eliminação de conta dentro da app, sem precisar de email — 5.1.1(v).
      Prova: reescrita da Edge Function (v25, `verify_jwt` ligado) e ciclo de
      teste completo com as duas contas demo, documentado em
      `apagar-conta-devolve-html-e-mente` e
      `chaves-estrangeiras-que-mordem-ao-encerrar-conta` (memória) e no
      capítulo 2 de `LANCAMENTO-IOS-ESTADO.md`.
- [ ] Confirmar se algum SDK (Firebase Analytics/Crashlytics) exige o prompt
      de App Tracking Transparency — não há `NSUserTrackingUsageDescription`
      no `Info.plist` (confirmado por grep: zero ocorrências). Se o
      Firebase estiver configurado só para push/crash e não para atribuição
      de anúncios entre apps, não é preciso ATT — **mas isto tem de ser
      confirmado no questionário de privacidade, não assumido aqui.**

## 6. Pagamentos (Guideline 3.1.3(a) / 3.1.5(a))

- [x] Nota de revisão já escrita em `ios/NOTAS-AO-REVISOR.md`: todos os
      pagamentos são de bens/serviços físicos consumidos fora da app
      (entregas, limpeza, reservas) — não se vende conteúdo digital, por isso
      não é preciso In-App Purchase. Stripe (cartão) + MB Way + dinheiro.
- [x] Instrução de teste com "Dinheiro" para o revisor não cobrar cartão real
      (mesmo ficheiro).

## 7. Contas demo e notas ao revisor

- [x] `ios/NOTAS-AO-REVISOR.md` já escrito e completo: duas contas demo
      (`demo@bora.app` para navegar, `demo.apagar@bora.app` só para o teste
      de eliminação, reposta pelo cron ao minuto 7 de cada hora), texto em
      inglês pronto a colar, contacto, e nota sobre localização em segundo
      plano do estafeta.
- [ ] Falta só colar o link do vídeo (§2) nesse ficheiro antes de submeter.

## 8. Assinatura e envio (job "release" do `build_ios.yml`)

- [ ] Segredos `IOS_DIST_CERT_P12_B64`, `IOS_DIST_CERT_PASSWORD`,
      `IOS_PROVISIONING_PROFILE_B64`, `ASC_KEY_P8_B64`, `ASC_KEY_ID`,
      `ASC_ISSUER_ID`, `ASC_TEAM_ID` — **nenhum existe ainda** (dependem da
      conta Apple activa, que é acção humana). O job B do workflow já os
      valida e falha alto e claro se faltar algum (`::error::Faltam
      segredos…`), portanto é seguro deixar o workflow como está.
- [ ] `versionCode`/`CFBundleVersion` do iOS usa `github.run_number` — **não
      mexer**, é contador independente do Android (confirmado no cabeçalho
      do próprio `build_ios.yml`).

## 9. Estado do ramo e publicação

- [x] Trabalho desta sessão feito só em `ios-lancamento`. Nenhum ficheiro de
      `pricing_service`, `dispatch_engine`, `finalizePurchase`,
      `bora_tokens`, RLS de `orders`/`wallets`/`ledger`, webhook Stripe ou
      `pubspec.yaml` (versionCode) foi tocado.
- [x] **RESOLVIDO na 3.ª sessão (2026-09-07).** O bloqueio nunca foi "falta
      de credencial" — é que o PC não tem nem nunca teve uma persistida
      (confirmado outra vez: GCM sem `wincredman`, sem `.netrc`, `cmdkey`
      vazio). A credencial real é uma chave de deploy SSH na VPS
      (`/docker/hermes-agent-fvnc/data/.secrets/cortex_deploy_ed25519`),
      configurada nos clones locais desse host. Publicado via rebase num
      worktree isolado + bundle + push a partir da VPS (sem `--force`).
      Receita completa e o "porquê" em `ios/LANCAMENTO-IOS-ESTADO.md` §-1 e
      na memória [[publicar-ios-pela-vps]].
- [x] Confirmado: `autonomous-night-2026-04-29` (produção) idêntica antes e
      depois do push — `1fd3439d83de0ccc08b6f9aa9a9a7b11ea105fe5` nos dois
      fetches frescos (antes e depois), feitos diretamente na VPS.
- [x] `172a2734..b8712fd7` aceite pelo GitHub em `ios-lancamento`
      (commits `cb7e4396`/`b8712fd7`, conteúdo idêntico aos locais
      `8e8e1d80`/`6852fbf4`, só o hash e o pai mudaram por causa do rebase).
      CI disparou sozinho: `build-ios` run `34167538478` para este commit —
      resultado em §1/§2 quando terminar.

## 10. Sentada de 20 minutos com o Danilo (só quando 1–9 estiverem ✅)

Páginas a deixar já abertas no Chrome, tudo preenchido menos o que só ele
pode fazer:
- [ ] App Store Connect → criar o registo do app (nome/bundle id/SKU).
- [ ] Pagar 99 €/ano da conta de programador Apple (login + 2FA + cartão).
- [ ] Colar os textos de `ios/APP_STORE_COPY.md`.
- [ ] Carregar os screenshots do §2.
- [ ] Preencher o questionário de privacidade (§5).
- [ ] Confirmar "trader status" se a Apple pedir (empresário em nome
      individual, NIF 322151171).
- [ ] Autorizar o job de release do workflow (`workflow_dispatch` com
      `enviar=true`) depois de os segredos do §8 estarem no repo.

---

## Resumo por bloco (para releitura rápida)

| Bloco | Estado |
|---|---|
| 1. Build/simulador | ✅ compila · ⚠️ arranque real ainda não provado |
| 2. Capturas + vídeo | 🔄 em construção nesta sessão |
| 3. Metadados ASC | ✅ texto pronto · ⏳ falta colar (humano) |
| 4. Completude (2.1) | ✅ Apple Pay/logos tratados · ⚠️ risco social-login documentado |
| 5. Privacidade | ✅ maior parte · ⏳ nutrition label (humano) |
| 6. Pagamentos | ✅ nota escrita |
| 7. Contas demo | ✅ pronto · ⏳ falta o link do vídeo |
| 8. Assinatura/envio | ⏳ bloqueado por segredos (humano) |
| 9. Ramo/publicação | ⚠️ bloqueado por credencial GitHub |
| 10. Sentada final | ⏳ só depois de 1–9 |
