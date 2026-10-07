# Auditoria de ramos e do PR n.º 1 — o que existe fora da produção

Data: 2026-10-07. Auditoria só de leitura (nenhum merge, cherry-pick, checkout, commit, push, reset, stash nem edição de ficheiro rastreado).

## Como se mediu

"Produção" é `origin/autonomous-night-2026-04-29`, que no momento da auditoria apontava para `383708b4` ("ci: bump versionCode to 655"). Depois de um `git fetch --all --prune`, comparei cada ramo remoto com essa referência.

Para cada ramo usei `git cherry` (commits cujo patch já existe na produção aparecem com `-`, os que não têm equivalente com `+`). Para cada commit com `+` comparei o conteúdo real dos ficheiros que ele toca contra o que está na produção, lendo o objeto git da produção (`git show origin/autonomous-night-2026-04-29:<ficheiro>` e `git rev-parse` dos blobs). Um commit só conta como "já em produção" quando o código ou o comportamento está lá, mesmo com texto diferente.

Onde o assunto toca o servidor, confirmei também no ar, só com leitura: SELECTs no Supabase `ojykpzwqrtusfeakzrna` e leitura da função `notify-tvde-driver` e da lista de Edge Functions (versões no ar).

Aviso sobre o ambiente: o worktree `C:\BoraLocal\_auditoria-3p` foi usado por outra sessão durante o trabalho (o HEAD passou a `e0d01173`, um commit à frente da produção, que só mexe em `tvde_ride_active_screen.dart` e num teste; mais tarde a pasta deixou de existir). Nenhuma conclusão deste relatório depende desse ficheiro nem desse worktree; as provas finais foram todas refeitas contra o objeto git `origin/autonomous-night-2026-04-29`.

Não corri compilações nem testes. Nada aqui foi aplicado.

## Resumo em poucas linhas

A produção já tem quase tudo o que vale a pena. O que falta de verdade é pouco e quase tudo é pequeno:

1. Um aviso de paragem para o motorista (`notify-tvde-driver`, ramo `stop_added`) que ainda manda cobrar 8 euros em vez do valor realmente acordado no vale ida-e-volta em dinheiro. É zona de dinheiro, só se propõe.
2. A interface do plano TVDE com preço pela rota (cliente e painel admin). O servidor já está pronto e no ar; a app não usa. É zona de dinheiro e precisa de "vai".
3. Três melhorias pequenas do fluxo "ida ao mercado" do estafeta (rascunho local, tolerância a 2xx no upload do talão, aba do admin) — o essencial do mesmo problema já foi resolvido pela produção por outro caminho.
4. O arranque mais rápido da página web (`web/index.html`: spinner, pré-carregamento, aviso aos 8 s). Opcional, e com um risco pequeno de descarregar duas vezes se não for medido.
5. Higiene: uma migration "PROPOSTA" antiga ainda no repositório de produção, que é pior do que a função que está no ar.

Todo o resto é duplicado (já na produção), experiência, diagnóstico ou documentação.

Fora do pedido, mas importante: existem ramos só locais (nunca enviados) com trabalho que não está em lado nenhum da cloud — ver a secção "Ramos só locais".

---

## 1. Ramo `tvde/reserva-agendada-2026-08-20`

35 commits à frente da produção; 23 já têm patch equivalente na produção (`-`) e 12 não (`+`). O ramo foi aproveitado a 30/08 (cherry-pick); o que ficou sem equivalente divide-se assim.

### Já em produção (os 23 com `-`, e três dos 12 com `+`)

Os 23 com `-` são a reserva agendada, os botões presos, o "A caminho", a regra de ouro do motorista, o pacote mattpocock, etc. Um caso a notar: o commit `26f5d688` apaga `lib/models/tvde_driver_action_error.dart`, mas esse ficheiro continua na produção porque `falha_de_acao.dart` o usa; o resto do commit está lá. Não é falta.

Dos 12 com `+`:

- `0116fe7c` (robot-b: destapar falhas e desbloquear o ciclo) — o ficheiro `supabase/functions/robot-b/index.ts` na produção é idêntico ao do commit. Chegou lá pelo espelho das Edge Functions `0bfd6abc` (24/09). A função no ar é a v15 (atualizada a 19/08). JA-EM-PRODUCAO.
- `a0b781a4` (pacote imune ao 16 euros, MB Way sobrevive a app fechada, volta sem dupla compra, mapas Uber/Waze, senha com `token_hash`) — a produção tem o equivalente `10f23a9c` (cherry-pick de 30/08). O patch não é idêntico só num bloco de `tvde-plan-payment` (ver abaixo, `19a88fb5`); os 9 ficheiros restantes batem. Confirmei na produção `token_hash` em `reset_password_screen.dart` (8 ocorrências), Waze em `tvde_ride_tracking_screen.dart`, `tvde_ride_active_screen.dart` e `navigation_service.dart`, e o retomar do MB Way de pacote em `tvde_store.dart`. JA-EM-PRODUCAO.
- `19a88fb5`, parte `tvde-plan-payment` — ver abaixo.

### AINDA-FALTA

**`19a88fb5` — parte `notify-tvde-driver` (ZONA-PROTEGIDA: dinheiro cobrado ao cliente / dito ao motorista).**
O que faz: no aviso `stop_added` (cliente acrescenta uma paragem a meio), quando o vale do pacote ida-e-volta é em dinheiro e a perna é a da ida, o texto manda o motorista cobrar `preço do piso + paragens`. O preço do piso vem da chave `tvde_roundtrip_price_cents` (800 por defeito). O commit muda isso para ler `credit.paid_cents`, ou seja, o que foi acordado naquele vale. Sem valor de confiança, o aviso fala só das paragens.

Provas de que ainda falta: na produção `supabase/functions/notify-tvde-driver/index.ts` ainda tem `let rtPrice = 800` e lê `tvde_roundtrip_price_cents` (uma ocorrência), e não tem `paid_cents`. A função no ar é a v21 e li o código: é igual ao repositório nesse ponto. Na base de dados existe 1 vale em dinheiro com `paid_cents` diferente de 800 (`select count(*) from tvde_roundtrip_credits where payment_intent_id is null and paid_cents<>800` devolveu 1), por isso o erro é real mas raro. O commit foi marcado "NAO DEPLOYADO" pelo próprio autor (lista vermelha, à espera de "vai"). Fica como **proposta**, nunca para aplicar sem "vai" do Danilo.

Parte `tvde-plan-payment` do mesmo commit: JA-EM-PRODUCAO por outro caminho. A produção tem a v7 (no ar a v9) que, quando a app manda `distance_km`, pergunta ao servidor `tvde_roundtrip_price_for_km` (linha 168). A diferença é que a produção, sem `distance_km`, cai no piso de 800 (linha 176), enquanto o commit recusava sem fallback. Esse é um desenho diferente, não uma falta.

**`9bb5cd32` — plano TVDE com preço pela rota (cliente + admin) (ZONA-PROTEGIDA: preços de planos).**
O que faz (relatório `tvde-plano-preco-por-rota-2026-08-25.md`, com `dart analyze` limpo e `flutter test` com 55 testes verdes segundo o próprio relatório): o cliente escolhe a rota antes de ver o preço, vê a conta aberta linha a linha vinda de `tvde_quote_plan`, o cartão "o meu plano" mostra a rota guardada, e o painel admin mostra km incluídos e rota e orça o valor ao conceder. Ficheiros: `lib/models/tvde_plan_quote.dart` (novo), `lib/models/tvde_subscription.dart`, `lib/screens/client/tvde/tvde_plans_screen.dart` (reescrito), `lib/screens/admin/admin_tvde_subscriptions_screen.dart`, `lib/screens/admin/admin_tvde_plan_requests_screen.dart`, `lib/stores/tvde_store.dart`, `test/tvde_plan_quote_test.dart` (novo).

Prova de que falta: na produção `tvde_plan_quote.dart` não existe; `tvde_plans_screen.dart` ainda usa `planPriceCents` (3 ocorrências) e o mapa fixo `_ridesTotal`; `quotePlan` não existe nem no ecrã nem no store. O servidor está pronto e no ar: existem no Supabase as funções `tvde_quote_plan`, `tvde_request_plan`, `tvde_plan_price_cents` e `admin_grant_subscription`, e as colunas `km_included` / `route_origin_label` / `route_dest_label`; a Edge `tvde-plan-payment` v9 já aceita `distance_km`. Mas a app não envia a rota e o preço do plano ainda é o fixo. Uso real: 5 subscrições na base (4 "semanal" de agosto e 1 "especial" de 04/09), nenhuma com rota guardada.

Nota importante: o ficheiro `tvde_plans_screen.dart` e o `tvde_store.dart` mudaram muito depois de 25/08 (por exemplo `5617c001` de 23/09 e `168246ea` de 04/10; o "plano à medida" da cliente Vina de 13/09). Não aplica limpo; seria preciso refazer em cima da produção. Como mexe em preço de plano, é só proposta e precisa do "vai". Não recomendo aplicar sem o Danilo confirmar que o plano por rota ainda é o desenho que quer, porque desde então ele passou a tratar casos por cliente (`tvde_client_fare_overrides`).

**`a09164cd` — ida ao mercado a prova de duplo toque, talão que não repete, rascunho local (parcial; sensível, não é zona vermelha mas liga ao fecho da compra).**
Caso real de 25/08 (Continente): lista gravada duas vezes, talão pedido 3 vezes, progresso perdido ao sair da app.

O que a produção já resolveu por outro caminho (mudança de 13/09, commit `a07b6ef4`): uma só função no servidor `finalizar_talao_nao_parceiro`, idempotente (a migration `20260913193234_talao_nao_parceiro_uma_so_funcao.sql` tem o ramo "já finalizada: só o talão e o valor pago" e devolve `idempotent`); a foto do talão fica retida (`_talaoGuardado` e `_caminhoTalaoGuardado` em `driver_map_screen.dart`) e não volta à câmara; o botão de confirmar tem trava (`_aConfirmar`, 6 ocorrências).

O que continua a faltar (ficheiros ausentes na produção): `lib/services/store_shopping_draft_service.dart` (rascunho local do progresso, expira em 12 h, para quando o telemóvel mata a app com 4 GB de RAM), `lib/services/store_shopping_finalize_guard.dart` (já em grande parte coberto pela função idempotente, só continua útil no caminho das lojas parceiras, que ainda usa `finalizePurchaseV2`), `lib/screens/admin/admin_order_purchase_tab.dart` (aba "Ida ao mercado" no detalhe do pedido, com linhas repetidas destacadas, botão de apagar e "marcar revisto"), e a tolerância de `ReceiptUploadService` a qualquer 2xx com uma repetição em erro de rede (na produção ainda decide por `data['success']`, linha única). O `driver_map_screen.dart` mudou muito desde 25/08, por isso estas três peças teriam de ser portadas à mão, não aplicadas.

Valor: baixo a médio. O botão "apagar linha repetida" da aba admin mexe em linhas de compra, por isso tratar com cuidado (não toca `pricing_service`, `dispatch_engine`, `finalizePurchase` nem tokens, mas altera dados que alimentam o total do talão).

**`b832071f` — apagar a migration PROPOSTA de cancelamento de reserva (higiene).**
A produção ainda tem `supabase/migrations/20260821010000_PROPOSTA_admin_cancel_reserva_ativada.sql` ("PROPOSTA — NÃO APLICADA"). A função que está no ar `admin_tvde_reservation_cancel` é melhor do que a proposta (cobre cinco estados incluindo `motorista_chegou` e fixa `cancel_fee_cents`; confirmei por `pg_get_functiondef`) e a versão `20260821010000` não está registada em `supabase_migrations.schema_migrations`. Se alguém correr uma sincronização de migrations, esse ficheiro seria aplicado e substituía a função boa pela pior. Apagar o ficheiro é seguro. Atenção: a pasta `supabase/` não está no `paths-ignore` do CI, por isso um commit que apague o ficheiro dispara build Android e deploy web; juntar a outro commit que já vá sair.

### NAO-FAZ-SENTIDO (documentação e relatórios)

`557d35ad` e `6616c618` (proposta de corte `bora_cut` do pacote): a proposta está superada. A produção tem `bora_cut_raw_cents` nas migrations `20260913193128`, `20260913193545` e `20260930129000`, e a função no ar `tvde_finish_ride` contém `bora_cut_raw_cents`. Na base resta 1 corrida de pacote histórica com corte negativo (de 01/08). Zona de dinheiro, não recomendar aplicar.
`b878f75e` e `79cf48ac` (hand-off e fecho da "sistema-redondo", 21/08): relatórios históricos.
`ace6576b` (verificação independente do plano por rota): só documentação; vale se o plano por rota voltar a ser feito.
`f80961c2` (PADRAO_BORA.md na outra branch): a produção já tem o ficheiro.

---

## 2. Ramo `festas-preview`

20 commits; 5 já com patch equivalente na produção (`-`: `d705629c`, `ff7066ba`, `f1fcd53c`, `98ac3297`, `70f7d3df`) e 15 sem (`+`).

Veredito do ramo: a categoria Festas foi lançada na produção por outro caminho (`24c9a2d2` "categoria Festas ponta-a-ponta — lançamento Sabores do Brasil", e `85da574b`, `dc66cf25`, etc.). O ramo `festas-preview` era uma pré-visualização web pública com encomenda simulada, sem login, e isso não faz sentido manter.

Provas na produção:
- `festas_screen.dart` e `festas_quando_screen.dart` existem; `restaurant_model.dart:404` devolve "Aceita encomendas" para a categoria Festas (é o `5c845d12`); `kFestasAvisoDias = 1` (a regra final de "1 dia", que substituiu a de "1/3 dias" do `3f47f5db`); o carrinho tem `_vendorIsFestas` e a isenção do saco; `order_model.dart` tem `takeawayPrepMinutes` ("fica pronto em X min").
- `ee9739a0` (loja "Em breve" enchia o snackbar mas não o carrinho): `cart_store.dart` da produção já não tem a guarda órfã de "Em breve" em `addItem` (a que existe agora, "BLOQUEADO … fechada", é a de loja fechada, que é deliberada; o commit `c541de97` só acrescentou os avisos na interface). JA-EM-PRODUCAO.
- `4c0cea9c` e `37100936` (imagens de 1,7 MB e de 1024 px): os ficheiros são idênticos na produção.
- `36b9006e` (proxy de imagens): `lib/utils/image_proxy.dart`, `web/functions/img.js` e `test/image_proxy_test.dart` iguais na produção (commit `85da574b`).

NAO-FAZ-SENTIDO (só serviam à pré-visualização): `b3ef5de1` (parte `festas_preview.dart`, `festas_preview_entrada.dart`), `42925601`, `39aa7a45`, `c0f96522`, `641f3eb6` (demo), `69ed684e` (CI da preview), `lib/screens/festas_demo_pedido_screen.dart`, `lib/screens/festas_painel_loja_screen.dart`, `lib/stores/festas_demo_store.dart`, e o workflow `build_web_preview.yml`. Todos ausentes na produção e assim devem ficar.

### AINDA-FALTA (opcional, risco baixo-médio)

`ca83c0ae` e `91c5319e` — só o ficheiro `web/index.html`: o splash do arranque passa de barra a roda com "A carregar…", aparece o aviso "A primeira abertura demora um pouco" aos 8 s, `preload` do ícone do logo e de `flutter_bootstrap.js` e `main.dart.js`, `preconnect` ao `www.gstatic.com`. Na produção `web/index.html` não tem nenhum `rel="preload"` (conferido: 0 ocorrências). Serve o arranque a frio em 3G. Cuidado: o `preload` de `main.dart.js` só ajuda se o URL for igual ao que o bootstrap pede; se o Flutter acrescentar um parâmetro de versão, o browser descarrega duas vezes. Recomendo, se se quiser, trazer só o spinner/aviso e o `preload` do logo, e medir antes de pôr o `preload` do JS. Não é zona protegida. Mexe em `web/`, por isso dispara o deploy web.

---

## 3. Ramo `autonomous-night/fase2-cortex-tasks`

4 commits; 3 sem equivalente: `557d35ad`, `6616c618` (relatório da proposta `bora_cut`, superada) e `0116fe7c` (robot-b, idêntico na produção). O quarto, `dea9b5db` (ecrã admin para trocar os modelos Gemini), tem equivalente (`-`).
Veredito: nada a trazer. JA-EM-PRODUCAO / NAO-FAZ-SENTIDO.

## 4. Ramo `main`

1 commit à frente: `0b41efcb` "ci(em-dia): ficha da App Store do Em Dia verificada de 6 em 6 h [skip ci]", ficheiro `.github/workflows/ios_ficha_emdia.yml` (cron `17 */6 * * *`). Não está na produção, e é de propósito: o `main` é o ramo por defeito do repositório e o GitHub só corre workflows agendados a partir dele (o próprio `2deb36cf` diz "cron corre do main"). Trazê-lo para a produção não faria correr o cron. Não toca a ficha do Bora. NAO-FAZ-SENTIDO levá-lo. (O mesmo commit existe num ramo local `worktree-agent-ac1d61e05b6561422`.)

O `main` está muito atrás da produção: não tem os workflows de build. Isso é conhecido e o PR n.º 1 (abaixo) diz o mesmo.

## 5. Ramos `analise-*` (04/10) e `diag-*` (30/09)

Todos os `analise-*` têm um só commit: o workflow `.github/workflows/analise_rapida.yml` (analyze + testes em `analise-**`, sem publicar). As variantes do ficheiro são só duas (a "estrita" do hash `14017a2f`, usada em 10 ramos; a original `ef2b170e` em `analise-missao-04-10`). Nenhum tem código de produto.

Exceções que carregam mais do que o workflow:

- `analise-missao-04-10` e `analise-admin-geral-provaci` levam o commit `62811741` "feat(missao-04-10): gorjetas, travas de toque duplo, lojas por telefone e secretário virtual". Já está na produção por outro caminho (`168246ea`, 04/10): dos 37 ficheiros de código e dados que o commit toca, 22 são idênticos ao commit, 14 apenas evoluíram depois (por exemplo `a40db532`, `e02c8db0`, `5efd2d96`); inclui `supabase/functions/charge-tip/index.ts` (no ar, v1), as migrations `20261004*` e as provas SQL. O único ficheiro ausente é `ferramentas/secretario-virtual/cacar_secretario_20261004.csv` (dados de uma caça, sem valor para o código). JA-EM-PRODUCAO. O commit extra `4243a589` de `analise-admin-geral-provaci` ("workflow estrito + ficheiro com erro, tem de ficar VERMELHO; apagar") é um teste do próprio workflow: NAO-FAZ-SENTIDO.
- `diag-analyze-2026-09-30` tem `e484b922` (workflow temporário `diag_analyze.yml`) e o `4c9f5800` (TextStyle sem `const` no PDF do extrato), que já tem equivalente `-`; conferi `partner_monthly_statement_card.dart` na produção (já sem `const` nas linhas 102, 118 e 124). NAO-FAZ-SENTIDO.
- `diag-autoteste-2026-09-30` (`46848483`): anotações `::error::` do autoteste. A produção já tem esse bloco em `tool/ci/autoteste_emulador.sh` (linhas 42-43). NAO-FAZ-SENTIDO.

Sobre `analise_rapida.yml`: não está na produção, e não precisa de estar (corre nos ramos `analise-*`, onde o ficheiro vive). Se o Danilo quiser uma análise sem publicar a partir do GitHub (o PC de 4 GB rebenta com `flutter analyze`), o workflow já existe e pode ser reaproveitado; é decisão de produto, não falta. Estes 12 ramos remotos são candidatos a apagar depois de o Danilo confirmar; não apaguei nada.

## 6. Outros ramos remotos

- `motor-conhecimento-2026-07-20`: 1 commit com equivalente na produção (`-`). Nada.
- `agente-cliente-app`, `agente-tvde`, `integra-ronda-04-10`, `codex/fix-incidentes-2026-09-12`, `fix/digest-enderecos-mortos`, `ios-lancamento`, `ci/codemagic-android`, `tvde-categoria-por-descobrir-2026-10-06`: 0 commits à frente da produção. Tudo já está na produção.
- `web-build`: ramo órfão de 1 commit, o artefacto de build web (`aa748a51`, "Bora CI build web de 4a6dc611, run 199"). Não é código fonte; é saída do deploy. NAO-FAZ-SENTIDO.
- `origin` (alias do `main`): ver ponto 4.

Nenhum outro ramo remoto tem commits sem equivalente em `lib/`, `supabase/`, `ios/`, `android/` ou `web/`.

---

## 7. Ramos só locais (não pedidos, mas relevantes)

Estes ramos existem só no PC (`git for-each-ref refs/heads`), nunca foram enviados para o GitHub. Se o PC avariar, este trabalho perde-se. Não os toquei.

- `empresa-agentes-2026-09-07` (20 commits, 10 sem equivalente, 07 e 08/09): organograma, despachante, "relatório da manhã", lançador que retoma a sessão, 25 agentes, em `docs/agentes/` e `orquestracao/agentes/*.py` (ausentes na produção). Dois commits mexem em código: `cc50094c` ("de onde vem cada pedido: android, ios ou web") — `lib/services/platform_tag_service.dart` é idêntico na produção, portanto já lá está (por outro caminho) —, e `ea03ae1a` que toca `admin_motores_screen.dart`. O resto é infraestrutura de agentes que o modelo "uma porta só / skill distribuir-trabalho" de 17/09 substituiu. NAO-FAZ-SENTIDO levar para a produção; se o Danilo quiser guardar a história, copiar para um ramo remoto de arquivo (decisão dele).
- `ios-lancamento` (local, 6bb12dc8): diverge do remoto `origin/ios-lancamento` (d47ab4b2, 0 commits à frente da produção). Os 11 commits sem equivalente são os 10 da empresa-agentes mais `799e9523` (taxa de pedido pequeno visível para o cliente; `small_order_fee.dart` idêntico na produção, portanto já lá).
- `ios-lancamento-trabalho` (7 commits só-documentação sobre as respostas à Apple, 2.1, corridas de auditoria): NAO-FAZ-SENTIDO para a produção. A app foi aprovada a 12/09.
- `ficha-loja-fechada-05-10` (`c541de97`): os 6 ficheiros de `lib/` e o `integration_test` são idênticos na produção. JA-EM-PRODUCAO.
- `draft/01-jwt-vault`, `draft/02-restaurants-uuid`, `draft/03-partner-open-dispatch` (29/04): planos antigos. O cutover do JWT para o vault existe na produção (`20260430200000_s2_jwt_vault_cutover.sql`); `draft/03` mexe em `dispatch-engine/index.ts` (ZONA-PROTEGIDA) contra uma versão de há seis meses (hoje v62 no ar). NAO-FAZ-SENTIDO; nunca recomendar aplicar.
- Ramo local `autonomous-night-2026-04-29` (o da produção): 6 à frente, 18 atrás da origem; 2 dos 6 já têm equivalente na produção (`bcb474f9`, `13aed4ff`) e 4 são documentação não enviada (`9205fa77`, `32a9e171`, `4ef7efde`, `1c055f24`: diagnóstico do PC e relatórios das quatro missões de 06/10).

---

## 8. Pull request n.º 1 de `nilofulfarotuga-hue/bora-app-cloud`

Lido pela API REST do GitHub (credencial do Git, só em memória; o script fica em `scratchpad\pr1.js`, que lê a credencial da variável de ambiente e não contém segredo). Estado: aberto, não é rascunho, sem comentários, `mergeable: true` / `mergeable_state: clean`.

Dados: título "fix(notificacoes): push admin data-only + canais fantasma + track de producao"; criado a 31/07/2026; base `main` (`2deb36cf`); **o ramo de origem (head) é `autonomous-night-2026-04-29`, ou seja, a própria produção** (head SHA `383708b4`, igual à produção de hoje). Por isso o PR mostra 2420 commits e 4970 ficheiros alterados (+584 978 / −240 385 linhas): é uma comparação de toda a produção contra o `main`, que está parado desde agosto. O próprio texto do PR diz que serve só como superfície de revisão e "não é para fazer merge sem decisão sobre o que fazer à main". Os três commits da sessão são `be8c193`, `fb19ad3` e `63dd147`; confirmei que os três são ancestrais da produção.

As três partes, uma a uma, contra o código da produção:

1. Push do admin só com dados (`notify-admin-urgent` v15): JA-EM-PRODUCAO. `supabase/functions/notify-admin-urgent/index.ts` na produção tem o cabeçalho "v15 (2026-07-31) — DATA-ONLY: removido o bloco `notification`", e a montagem da mensagem (linhas 343-395) só leva `data` (com `title`, `body` e `persistent`), sem bloco `notification`. No ar a função está na v19 (≥ v15). No Dart, `notification_service.dart` lê `data['title']` e `data['body']` com `notif?.*` só como fallback (linhas ~1595-1613), e usa `channelOverride: 'bora_admin_urgent'` (parâmetro `channelOverride` na linha 1731, `Importance.max` na linha 1739).
2. Canais fantasma: JA-EM-PRODUCAO. `lib/main.dart` cria `bora_admin_urgent` (linha 255), `bora_orders` no arranque (linha 279) e `bora_partner_ratings` (linha 290), com o comentário que explica que antes não existia.
3. Track de produção no CI: JA-EM-PRODUCAO. `.github/workflows/build_android.yml` tem `tracks: internal,alpha,production` e `status: completed` (linhas 323-324), com a nota sobre o rollout faseado por fazer (linhas 304-313).

Resta o que o PR listou em "Por fechar". Não é parte dos três itens, mas convém saber: das cinco Edge Functions com o mesmo defeito do bloco `notification`, a produção ainda tem esse bloco em `notify-cleaner` (1), `notify-purchase-finalized` (1) e `notify-partner-low-rating` (2). `notify-admin-reimbursement` não tem a linha `notification:`; `notify-tvde-client` já tem marcas de "data-only" e ainda uma linha `notification:`. Contagem por `grep` de linhas, serve de indício, não de prova de comportamento. O ponto do `notify-service-provider` (ficheiro local divergente) também já está dito no PR; a função no ar é a v5 e o ficheiro de produção tem marcas de data-only.

Recomendação (só recomendo, não comentei nem fechei): **fechar o PR n.º 1**, sem merge, com uma nota do género: "As três partes (push do admin só com dados, canais criados no arranque, track de produção) estão na branch de produção e no ar (be8c193, fb19ad3, 63dd147; notify-admin-urgent v19; build_android.yml com tracks internal,alpha,production). Este PR compara toda a produção com um `main` parado desde agosto, não é para fazer merge. O que ficou por fazer (notify-cleaner, notify-purchase-finalized, notify-partner-low-rating, rollout faseado do track de produção) passa a ser acompanhado no Córtex, não aqui." Se se quiser guardar os itens abertos, passá-los a uma ordem do Córtex antes de fechar. Nada em falta nas três partes.

---

## 9. Lista final do que ainda falta (por prioridade)

1. `notify-tvde-driver`, ramo `stop_added`, usar `credit.paid_cents` em vez de 800 (de `19a88fb5`). ZONA-PROTEGIDA (dinheiro). Só propor, esperar "vai". Evidência: produção ainda tem `let rtPrice = 800`; a v21 no ar também; 1 vale em dinheiro com valor diferente de 800 na base.
2. Plano TVDE com preço pela rota na app e no admin (de `9bb5cd32`, `ace6576b`). ZONA-PROTEGIDA (preço de plano). Servidor pronto, app não usa; refazer em cima da produção, só se o Danilo confirmar o desenho. Uso real baixo (5 subscrições, nenhuma com rota).
3. Ida ao mercado: rascunho local, tolerância a 2xx no upload do talão e aba do admin "Ida ao mercado" (de `a09164cd`). Valor baixo a médio; portar à mão para `driver_map_screen.dart` atual; atenção ao botão de apagar linhas.
4. Arranque web (de `ca83c0ae` e `91c5319e`): só `web/index.html`; opcional; medir o `preload` do JS antes.
5. Higiene: apagar `supabase/migrations/20260821010000_PROPOSTA_admin_cancel_reserva_ativada.sql` (de `b832071f`); juntar a um push que já tenha de sair, porque `supabase/` dispara o CI.
6. Local só: salvar ou arquivar `empresa-agentes-2026-09-07` e os quatro commits de documentação por enviar do ramo local da produção, se o Danilo os quiser (não tocar sem ele).

Fica sem ação: todos os `analise-*`, `diag-*`, `web-build`, `main` (workflow do Em Dia), `fase2-cortex-tasks`, a pré-visualização `festas-preview`, e os `draft/*`.

## 10. O que não ficou provado

- Não corri `flutter analyze` nem testes: as conclusões vêm de comparar ficheiros e de leituras no ar.
- "Código ou comportamento já na produção" para `a09164cd` e `9bb5cd32` foi decidido por leitura do código e do relatório do próprio commit; não reproduzi o caso do Continente de 25/08 nem a compra de plano.
- Os números de `grep` das cinco Edge Functions do PR são contagens de linhas, não leitura função a função.
