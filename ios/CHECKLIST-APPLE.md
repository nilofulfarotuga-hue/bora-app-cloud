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

### Capturas — ERAM INVENTADAS, foram deitadas fora (2026-09-08)

> A linha que aqui estava dizia **"As 7 capturas existem e estão certas"**.
> Estavam certas no *tamanho* e erradas no que é que importa: mostravam
> lojas, serviços e preços que **não existem na produção**. O Danilo deu
> por isso ao reparar que não há nenhuma "Lavagem Completa 15 euros".

- [x] **Auditadas uma a uma contra o banco — as sete falharam.** Detalhe
      ecrã a ecrã em `ios/LANCAMENTO-IOS-ESTADO.md` §-2. Resumo: a "Mercado
      da Guarda" e a "Barbearia Central" não existem; a Goola Açaí tem 2
      produtos e não 3; a limpeza é por tipologia e não por hora; a lavagem
      não tem "+ Cera" e o interior está desligado. Prova: id 1503.
- [x] **Arnês apagado**: `lib/screens/capturas/captura_screens.dart` (786
      linhas), `lib/main_capturas.dart`, `integration_test/capturas_loja_test.dart`.
- [x] PNGs e `demo.mp4` arquivados em `ios/video-INVENTADO-NAO-USAR/` com um
      `LEIA-ME.txt`. Ficam **só como prova do erro**.
- [x] **Regra nova, sem excepção:** nenhuma captura e nenhum vídeo mostra
      loja, serviço, produto ou preço que não exista mesmo no banco.
- [ ] **Capturas novas, da app real** — `integration_test/demo_real_test.dart`
      percorre a aplicação a sério ligada ao servidor, com `demo@bora.app`.
      Escrito e publicado (id 1517); **falta a corrida do CI dar imagens**.

### Vídeo — tem de ser a app viva

- [x] O primeiro vídeo (76,2 s, legendas em inglês, publicado no site) foi
      **retirado do ar** por sair das capturas inventadas. `boraguarda.com`
      devolve 404 em `/provas/apple-review/` e no `.mp4`. Ids 1488–1500.
- [x] **YouTube: não se cria canal.** A conta `boraappbora@gmail.com` não
      tem canal (provado em `youtube.com/account`) e criar um obriga a
      aceitar termos e a assumir identidade pública — decisão do Danilo, e
      ele disse não. O vídeo vai para uma página **não listada** do site do
      Bora. Prova: id 1501.
- [x] Desligado o passo dos fluxos web (`e2e_test.dart`): dava sempre `+0 -7`,
      só ficava verde por `continue-on-error`, custava **14 min por corrida** e
      enchia a gravação de ecrã inicial do simulador.
- [x] `ios/tools/montar_video_revisor.py` corrigido e provado: emparelha cada
      fotograma com os PNGs de captura (o detector antigo procurava o verde
      da marca e dava 0 blocos — os 7 PNGs bons pontuavam 0/24 contra ele,
      porque cada ecrã tem cabeçalho de cor diferente). Ids 1489–1490.
- [ ] Cortar 60–120 s **da gravação da app real** e publicar na página não
      listada; guardar o endereço aqui e em `ios/NOTAS-AO-REVISOR.md`.

### Duas frases às Apple que não eram verdade — uma corrigida, outra provada

- [x] *"The demo account has a saved address in Guarda"* — **era falso**.
      `demo@bora.app` não tinha morada nenhuma. Criada "Praça Luís de Camões,
      6300-725 Guarda" — lugar público de propósito. Prova: id 1516.
      **Correcção à minha própria explicação:** escrevi aqui que sem morada o
      guarda do `client_home_screen` teria bloqueado o revisor. Fui ler:
      `_navigateWithAddressGuard` é `=> nav();`, um no-op que não guarda nada.
      A morada faz falta ao **checkout**, não à navegação — o `AutoAddress`
      põe a morada guardada em primeiro na cascata e é dela que sai o endereço
      de entrega. O acto estava certo; a razão não. Prova: id 1527.
- [x] *"Orders from the demo account are never dispatched to real couriers"*
      — **verdade, e agora provado**: gatilho `BEFORE INSERT`
      `a_trg_pedido_demo_caixa_fechada` em `orders`, ligado, faz as
      encomendas demo nascerem em `driverAccepted` no estafeta demo. Nunca
      passam por `callingDriver`. Se o gatilho for desligado, a frase deixa
      de ser verdade. Prova: id 1515.

### 5.2.1 — as lojas reais são quase todas marcas de terceiros

- [x] **Decidido e aplicado (ordem do Danilo, 2026-09-08).** As capturas da
      loja são publicidade pública e não levam nomes nem logótipos em
      destaque das lojas onde a Bora só compra. O interruptor
      `platform_settings.ios_hide_nonpartner_logos` passou de `false` a
      **`true`** (lido de volta), por isso a lista de mercados mostra a loja
      por nome em texto e ícone de categoria. As fichas que entram são de
      marca própria: Goola Açaí, Sabores do Brasil e Barbearia Ouro e Prata.
      O **vídeo** é privado e pode mostrar o supermercado real, porque tem de
      provar uma compra a sério. Prova: id 1524.
### Ainda por fazer, e de que dependem
- [x] **Firebase iOS — FEITO, e não dependia da conta Apple.** Esta linha
      dizia que dependia da chave APNs, "que só se cria com a conta
      activa". Estava errada: registar a app iOS no Firebase só precisa do
      **bundle ID**; é a chave APNs (`.p8`) que precisa da conta. App Apple
      criada a 2026-09-08 no projecto `boraapp-d2bea` — bundle
      `pt.boraapp.bora`, apelido "Bora iOS", Swift, sem App Store ID.
      `GoogleService-Info.plist` (873 bytes) validado com `plistlib`:
      `BUNDLE_ID` certo, `PROJECT_ID=boraapp-d2bea`,
      `GCM_SENDER_ID=765097014497` (igual ao Android), `GOOGLE_APP_ID` de
      plataforma **ios**, `IS_GCM_ENABLED=true`. Guardado no cofre local e
      em `ios/Runner/` (confirmado ignorado pelo git, `.gitignore:119`).
      Segredo `GOOGLE_SERVICE_INFO_PLIST_B64` criado por API com caixa
      selada — **HTTP 201**, confirmado na listagem de segredos do repo. O
      valor nunca passou pelo chat nem pelo repositório. Prova: id 1525.
- [ ] Chave APNs (`.p8`) e ligação ao Firebase — **esta sim** depende da
      conta Apple activa. É o que falta para as notificações chegarem ao
      iPhone.
- [ ] ⚠️ **Um serviço do projecto Firebase está pausado por tecto de
      gastos** ("a spend cap was enforced"). Saber qual antes de contar com
      push. Visto no console a 2026-09-08. Prova: id 1526.
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
- [x] **A app NÃO arrancava no simulador — encontrado e corrigido.**
      Esta era a linha mais importante da lista e esteve por provar
      desde o início. Provado agora, e o resultado foi mau: na
      corrida `34209823345` a app liga o VMService, imprime
      `[BoraForegroundService] initialised` e **morre** com
      `[core/not-initialized] Firebase has not been correctly
      initialized` (`main.dart:467`), porque no iOS não havia
      `GoogleService-Info.plist`. Medida: **937 s** de gravação com o
      ecrã inicial do iOS do princípio ao fim e **zero** capturas —
      nem a fotografia de falha, porque morreu antes da primeira.
      Confirmado por amostragem de 6 fotogramas do `demo.mp4`.
      **Com o plist em falta ou corrompido no IPA, isto era a app a
      fechar-se na cara do revisor: reprovação 2.1 à primeira.**
      Corrigido em `lib/main.dart`: o `Firebase.initializeApp()`
      estava cru dentro de um `Future.wait` e qualquer erro derrubava
      o `main()`; passa a falhar em silêncio e a app corre sem
      notificações. Ids 1522 e 1523.
- [ ] Falta a corrida verde a provar que, além de arrancar, **navega**
      e deixa capturas no artefacto.
## 2. Capturas da loja (6–8, 1320×2868) — da APP REAL, nada de ecrãs desenhados

> Regra da casa desde 2026-09-08: nenhuma captura e nenhum vídeo mostra
> loja, serviço, produto ou preço que não exista mesmo no banco de
> produção. Ver §0 para o que correu mal e como se apanhou.

- [x] Arnês novo: `integration_test/demo_real_test.dart` + o driver que já
      existia (`test_driver/capturas_driver.dart`) + passo
      "Percorrer a app real e capturar" no `build_ios.yml`. Abre `app.main()`
      a sério, entra com `demo@bora.app`, e fotografa início →
      supermercados → loja → produto → carrinho → pagamento em dinheiro.
      **Zero `pumpAndSettle`** (era o que dava `+0 -7`): bombeia em passos de
      200 ms com `runAsync` para o relógio real andar. `flutter analyze`
      limpo; YAML validado. Prova: id 1517.
- [x] A encomenda a sério está atrás de `--dart-define=FAZER_ENCOMENDA_REAL`
      (input `encomenda_real` no `workflow_dispatch`), e a caixa fechada
      garante que nunca chama estafetas reais. Prova: id 1515.
- [ ] **Capturas a sair da corrida do CI** — é a prova que falta. Sem PNG no
      artefacto, isto não está feito.
- [ ] Escolher 6–8 capturas de entre as que saírem, **decidindo antes** o que
      fazer com as marcas de terceiros (§0, 5.2.1). **Zero** carro ou TVDE.
- [ ] Vídeo de 60–120 s com legendas em inglês, cortado da gravação da app
      real com `ios/tools/montar_video_revisor.py`, publicado numa página
      **não listada do site do Bora** (o YouTube saiu — §0).
- [ ] Endereço do vídeo gravado aqui e em `ios/NOTAS-AO-REVISOR.md`.

## 3. Metadados da App Store Connect

- [x] Textos preparados em `ios/APP_STORE_COPY.md` (nome, subtítulo,
      categoria, palavras-chave ≤100 car., texto promocional, descrição,
      release notes, copyright, classificação etária).
- [x] **Textos prontos a colar**, com todos os limites CONTADOS por script e
      não estimados: nome 26/30, subtítulo 26/30, promocional 118/170,
      descrição 1590/4000, novidades 164/4000, palavras-chave **80 dos 100
      bytes** (bytes, por isso sem acentos) e nenhuma palavra com 2 ou menos
      caracteres. Em `ios/APP_STORE_COPY.md`. Prova: id 1538.
- [ ] Colar no formulário real — depende da conta activa.
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
- [x] **Bundle ID confirmado no projecto**: `PRODUCT_BUNDLE_IDENTIFIER =
      pt.boraapp.bora` em `ios/Runner.xcodeproj/project.pbxproj` (o
      `pt.boraapp.bora.RunnerTests` ao lado é o alvo de testes, normal).
      Igual ao pacote Android, como deve ser.
- [ ] Criar o registo com esse SKU/Bundle ID na App Store Connect — depende da
      conta activa.
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
- [x] **Etiqueta de privacidade respondida em rascunho** — cada resposta com a
      página da Apple de onde saiu, em `ios/CLASSIFICACAO-E-PRIVACIDADE.md`.
      Mapeada do `PrivacyInfo.xcprivacy` lido com `plistlib`: 8 tipos, todos
      com fim *App Functionality*, nenhum para rastreio, só `Crash Data` não
      ligado à pessoa. Prova: id 1539.
- [ ] ⚠️ **Duas lacunas a corrigir antes de submeter**: falta `Payment Info`
      (a folha da Stripe recolhe o cartão dentro da app, e a Apple manda
      declarar o que os SDK de terceiros fazem) e falta o conteúdo do chat.
- [ ] Preencher o formulário na App Store Connect — depende da conta activa.
- [x] Eliminação de conta dentro da app, sem precisar de email — 5.1.1(v).
      Prova: reescrita da Edge Function (v25, `verify_jwt` ligado) e ciclo de
      teste completo com as duas contas demo, documentado em
      `apagar-conta-devolve-html-e-mente` e
      `chaves-estrangeiras-que-mordem-ao-encerrar-conta` (memória) e no
      capítulo 2 de `LANCAMENTO-IOS-ESTADO.md`.
- [x] **Nenhum prompt de rastreio (ATT) é preciso — verificado, não assumido.**
      `pubspec.yaml` não tem `firebase_analytics`, `google_mobile_ads`,
      `facebook_*`, `appsflyer`, `adjust`, `amplitude`, `mixpanel`,
      `app_tracking_transparency` nem `branch_io` — nenhum SDK de rastreio ou
      de publicidade. O `Info.plist` não tem `NSUserTrackingUsageDescription`
      (0 ocorrências), e o `PrivacyInfo.xcprivacy` declara
      `NSPrivacyTracking: false` com lista de domínios vazia. As três coisas
      dizem o mesmo, que é o que se queria confirmar.
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
- [x] **A promessa de que a conta de apagar se repõe sozinha é verdadeira.**
      As notas dizem à Apple que `demo.apagar@bora.app` é "automatically
      recreated every hour". Não bastava estar agendado: o `pg_cron` tem o job
      `repor-demo-apagar` com `schedule = 7 * * * *`, activo, e o histórico de
      24 h mostra **15 execuções, todas `succeeded`**, a última às 11:07 UTC de
      2026-09-08, sem uma única falha. (O `mover-pedidos-demo`, de minuto a
      minuto, leva 830 execuções e também zero falhas.)
- [ ] Falta só colar o link do vídeo (§2) nesse ficheiro antes de submeter.

## 8. Assinatura e envio (job "release" do `build_ios.yml`)

- [ ] Segredos `IOS_DIST_CERT_P12_B64`, `IOS_DIST_CERT_PASSWORD`,
      `IOS_PROVISIONING_PROFILE_B64`, `ASC_KEY_P8_B64`, `ASC_KEY_ID`,
      `ASC_ISSUER_ID`, `ASC_TEAM_ID` — **nenhum existe ainda** (dependem da
      conta Apple activa, que é acção humana). O job B do workflow já os
      valida e falha alto e claro se faltar algum (`::error::Faltam
      segredos…`), portanto é seguro deixar o workflow como está.
- [x] **Contadores separados, e a cadeia está provada.**
      `ios/Runner/Info.plist` tem `CFBundleVersion = $(FLUTTER_BUILD_NUMBER)`,
      e o job de release passa `--build-number=${{ github.run_number }}`
      (`build_ios.yml`, passo do `flutter build ipa`). Ou seja
      `run_number` → `FLUTTER_BUILD_NUMBER` → `CFBundleVersion`. O
      `versionCode` do Android continua com o contador dele e **não se toca**.
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
