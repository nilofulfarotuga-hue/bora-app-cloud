# CI Web — Fundação das "Cabines de Browser" (2026-07-17)

Pedido original do Danilo (15/07 manhã): 10-20 "navegadores" abertos ao mesmo tempo, cada um
fingindo ser uma pessoa diferente (clientes, estafetas, parceiros, limpeza), testando todas as
categorias de uma vez. Fora de escopo: o que é nativo do telemóvel (GPS, push, câmara KYC) —
isso continua a ser testado no device físico.

**Esta ordem é só a fundação.** Playwright e as cabines em si ficam para a próxima ordem, só
depois de o build web provar que corre no runner do GitHub Actions.

Onde correr: decidido por investigação anterior — nem VPS (1 core/4GB, insuficiente, provado no
run recon-20260715-1) nem PC (4GB Celeron, já é o executor). GitHub Actions, runner
`ubuntu-latest` (2 cores / 7GB), grátis, já usado todos os dias para o build Android.

---

## 1. O que o `build_android.yml` já faz (reaproveitado, sem alterar o ficheiro)

- **Checkout:** `actions/checkout@v4`. O build Android usa `fetch-depth: 0` + `token:
  secrets.GITHUB_TOKEN` porque precisa de fazer `git push` de volta (bump do versionCode). O
  `e2e-web.yml` não faz push nenhum, por isso o checkout novo é simples (sem esses dois extras).
- **Flutter:** acção `subosito/flutter-action@v2`, `flutter-version: 3.41.2` (PIN — há um
  comentário explícito no `build_android.yml` a avisar para não subir a versão sem re-testar o
  login, porque uma versão mais recente do parser de `--dart-define-from-file` já causou um bug
  de credenciais inválidas). `channel: stable`, `cache: true`.
- **Configuração (variável protegida):** o secret chama-se **`DART_DEFINES_FILE_B64`** — um
  `.dart_defines` inteiro (Supabase/Maps/Stripe) codificado em base64. O passo decodifica com
  `base64 --decode` para um ficheiro `.dart_defines` na raiz do repo e falha explicitamente
  (`exit 1`) se sair vazio. Nenhum valor foi copiado para este relatório.

O `e2e-web.yml` novo reaproveita exactamente estes três mecanismos (checkout, Flutter pinado,
secret `DART_DEFINES_FILE_B64`) — não inventa nenhum novo.

---

## 2. Ficheiro novo: `.github/workflows/e2e-web.yml`

- Trigger: **só `workflow_dispatch`** (nunca `on: push`) — não gasta minutos a cada commit.
- Não toca em `build_android.yml` nem em nenhum workflow existente.
- Passos: checkout → Setup Flutter (mesma acção/versão) → decode `.dart_defines` (mesmo secret)
  → `flutter pub get` → `flutter build web --release --dart-define-from-file=.dart_defines`
  (medindo a duração com `date +%s` antes/depois) → mede o tamanho de `build/web` com `du -sh` →
  escreve os dois números no `$GITHUB_STEP_SUMMARY`.
- Sintaxe validada com `npx js-yaml` (parse + dump para JSON, sem erros) antes do commit.
- **Nota:** não consegui *disparar* este workflow no GitHub Actions a partir deste executor — não
  há `gh auth` nem token configurado neste sandbox (só a deploy key SSH usada para `git push`).
  Por isso os números da secção 4 são de um build **local**, não de uma corrida real do runner
  `ubuntu-latest`. Fica registado para não inventar prova de uma corrida CI que não aconteceu
  (ver memória `feedback_nunca_inventar_prova_commit`). Quando o Danilo (ou outro fluxo com `gh`
  autenticado) disparar o `workflow_dispatch` manualmente, os números reais aparecem no
  `$GITHUB_STEP_SUMMARY` dessa run.

---

## 3. A peça crítica: como o Playwright vai conseguir tocar nos elementos

**Confirmado nesta máquina, Flutter 3.41.2 (a mesma versão usada no build Android):**

```
$ flutter build web --help | grep -i renderer
(nenhum resultado — a flag --web-renderer não existe mais)
```

O build local gerado (`build/web/flutter.js`, `flutter_bootstrap.js`) só contém referências a
`CanvasKit` / `canvaskit` / `skwasm` — **zero** menções a um renderer HTML. Ou seja: o renderer
HTML foi **removido** do Flutter há várias versões (a remoção aconteceu bem antes da 3.41.2); não
é uma opção disponível para contornar o problema. **Esta via está fechada — documentado para não
ser reinvestigada na próxima ordem.**

Isto confirma o problema que o Danilo já esperava: CanvasKit desenha tudo num único `<canvas>`.
Um Playwright a tentar `page.click("button:has-text('Entrar')")` no sentido normal (procurar um
`<button>` real no DOM) não encontra nada — não há elementos HTML por trás dos widgets.

**A via que resolve isto: a árvore de semântica/acessibilidade do Flutter (`flt-semantics`).**

Quando a acessibilidade está activa, o motor do Flutter Web injecta, por cima do `<canvas>`, uma
árvore paralela de elementos DOM invisíveis (`<flt-semantics>`, com atributos `role`,
`aria-label`, posicionados em `absolute` exactamente sobre cada widget clicável/legível). Cliques
reais nesses elementos são reencaminhados pelo motor para o widget certo — é o mesmo mecanismo
que um leitor de ecrã (NVDA/VoiceOver) usa, e é a via oficial que ferramentas de automação de apps
Flutter Web já usam.

Por defeito essa árvore **não** existe até a acessibilidade ser activada. Há duas formas:

1. **Runtime, sem tocar no código do Bora:** o Flutter Web mostra um botão-armadilha invisível
   (`flt-semantics-placeholder`) no canto superior esquerdo, full-screen, que qualquer leitor de
   ecrã foca automaticamente. Um script de automação pode simular esse foco/clique inicial para
   activar a árvore antes de interagir com o resto da app.
2. **Melhor para automação em massa (recomendado para a próxima ordem):** o próprio pacote
   `integration_test` do Flutter já activa semântica permanentemente ao arrancar, chamando
   `SemanticsBinding.instance.ensureSemantics()`. Dá para replicar isto no Bora com um dart-define
   só-de-teste (ex.: `ENABLE_SEMANTICS_FOR_E2E=true`, lido uma vez no arranque do `main.dart`) —
   assim a árvore `flt-semantics` já está pronta no primeiro frame, sem depender do
   click-no-placeholder, o que é bem mais fiável com 10-20 cabines a correr ao mesmo tempo.

**Alternativa a manter em mente (não é Playwright, mas é a via mais robusta tecnicamente):**
`flutter drive -d web-server` com `integration_test` conduz a app directamente pelo lado Dart
(`WidgetTester`), sem depender de cliques de pixel nem da árvore de semântica — é o que a própria
Flutter usa nos seus testes oficiais de Web. Fica anotado como plano B se a via
Playwright+flt-semantics se mostrar frágil com muitas cabines em paralelo.

**Sem isto resolvido as cabines não funcionavam — está resolvido nesta ordem: a via é
`flt-semantics` (opção 2 acima), a implementar como dart-define de teste na próxima ordem, junto
com o próprio Playwright.**

---

## 4. Resultado do build (medição local — ver nota da secção 2)

```
flutter build web --release --dart-define-from-file=.dart_defines
EXIT_CODE=0
DURATION_SECONDS=462   (≈ 7 min 42 s)
Tamanho build/web: 50M  (55 ficheiros)
```

Build passou sem erros. Avisos normais e não-bloqueantes: tree-shaking de ícones (redução de
~96%) e avisos de incompatibilidade Wasm em `flutter_secure_storage_web`, `audioplayers_web` e
`geolocator_web` (usam `dart:html`/`dart:js_util` — só relevantes para `--wasm`, que não estamos a
usar; build normal em CanvasKit/JS não é afectado).

`build/web/` está em `.gitignore` (`/build/`) — não foi commitado, só medido.

---

## 5. Próxima ordem (fora de escopo aqui)

1. Adicionar o dart-define `ENABLE_SEMANTICS_FOR_E2E` (ou nome equivalente) ao `main.dart`,
   chamando `SemanticsBinding.instance.ensureSemantics()` só quando presente.
2. Instalar Playwright no `e2e-web.yml` (novo job ou extensão deste), servir `build/web` local
   (`python -m http.server` ou `dhttpd`), e escrever o primeiro script de 1 "cabine" a fazer
   login como cliente demo via selectors `flt-semantics[aria-label=...]`.
2b. Confirmar disparo real do `workflow_dispatch` via `gh` autenticado (este executor não tem —
    ver secção 2) para obter os números reais do runner `ubuntu-latest`, não só os locais.
3. Só depois de 1 cabine funcionar de forma fiável, escalar para as 10-20 em paralelo (matriz de
   jobs ou processos Playwright concorrentes dentro do mesmo job).
