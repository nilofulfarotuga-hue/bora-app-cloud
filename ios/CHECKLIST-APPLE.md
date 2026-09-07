# CHECKLIST APPLE — submissão à App Store

> Missão `ios-lancamento` · Tarefa 4 · criado 2026-09-07 (2.ª sessão — não
> existia antes; a 1.ª sessão só o referenciou).
> Cada linha tem `[x]`/`[ ]`/`[~]` (`~` = em curso) e a prova a seguir, nunca
> "deve estar". Fonte do modo de trabalho: memória `carta-de-autonomia-ios`.
> Fonte do estado técnico: `ios/LANCAMENTO-IOS-ESTADO.md`.

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
- [ ] **`register_client_screen.dart` tem botões "Continuar com Apple" e
      "Continuar com Google"** atrás da flag `_socialAuthEnabled =
      bool.fromEnvironment('SOCIAL_AUTH_ENABLED')` (default `false` — os
      botões não aparecem a menos que o build passe
      `--dart-define=SOCIAL_AUTH_ENABLED=true`). **Confirmar antes de gerar o
      IPA de release que o `.dart_defines` gerado a partir do segredo
      `DART_DEFINES_FILE_B64` NÃO contém essa linha** — não dá para ler o
      segredo a partir daqui. Se algum dia esses botões aparecerem no ar sem
      as três integrações reais (Apple/Google/Supabase) ligadas, tocar neles
      só mostra um SnackBar "em configuração" — isso é reprovação 2.1 na
      certa (app aparenta funcionalidade que não existe).
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
- [ ] **Bloqueio encontrado nesta sessão:** não há credencial de escrita para
      o GitHub disponível (`git push`, `git credential fill` e
      `cmdkey /list` confirmam — ver RESULTADO desta sessão). O script
      `publicar.py` referido na ordem não existe no repo nem no
      `.scratch/`. Os commits desta sessão ficam **só localmente**, prontos a
      publicar assim que houver credencial (token da API do GitHub ou GCM
      interactivo com a sessão do Danilo). Não é dinheiro nem zona vermelha —
      é infraestrutura de publicação.
- [ ] Confirmar, no momento em que a publicação for possível, que
      `autonomous-night-2026-04-29` (produção) continua exactamente onde
      estava antes desta missão.

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
