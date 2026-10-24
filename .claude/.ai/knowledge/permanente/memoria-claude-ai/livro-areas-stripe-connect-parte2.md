---
id: memoria-claude-ai-livro-areas-stripe-connect-parte2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-24
zona: verde
confianca: alta
estado: atual
---

# Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata por preencher, repasse automático ainda desligado), como gerar o link de cadastro, taxas por parceiro e plano por fases (parte 2 de 3)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-stripe-connect-parte2`, origem `claude-ai`, atualizada em 2026-10-24T10:15:08.344117+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas stripe connect parte2 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/stripe-connect.md), copiada a 24/10/2026 11:13 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

- [stated] TOKENS NÃO DESCONTAM no cartão/MB Way: a RPC `tvde_request_ride` TEM o parâmetro `p_tokens_to_apply` (1 token = 5 cêntimos, tecto 50% da tarifa, desconta também bora_cut_cents), mas a Edge Fn `tvde-payment` (v8) NÃO o passa — nem em `charge` nem em `charge_roundtrip`. Prova: evento da corrida com `"tokens_requested": 0` apesar de o Danilo ter escolhido usar tokens. As colunas `tokens_applied_count`/`tokens_applied_value_cents` ficam sempre 0.
- [stated] `tvde_ride_charge_cents(p_ride_id)` devolve só `COALESCE(final_fare_cents, est_fare_cents, 0)` — não subtrai tokens. Cuidado ao corrigir para não descontar a dobrar.
- [stated] TAXA DE CANCELAMENTO INJUSTA: `tvde_cancel_ride` com `tvde_cancel_full_after_grace`=true e graça de 180s cobra 100% da tarifa passados 3 min SEM verificar se algum motorista chegou a ser oferecido. Danilo cancelou às 19:05 (elapsed 219s) e levou `cancel_fee_cents`=500 numa corrida que nunca teve motorista.
- [stated] PIOR: a acção `refund` do tvde-payment calcula refund = max(0, min(pago−taxa, pago)) = 0, não chama a Stripe, e MESMO ASSIM grava `payment_status='refunded'`. O registo mente — diz reembolsado e não voltou nada. Os €5 do Danilo das 19:01 provavelmente ficaram retidos.
- [stated] Definições relevantes: tvde_offer_ttl_seconds=40, tvde_reoffer_pause_seconds=35, tvde_retry_window_seconds=120, tvde_heartbeat_window_seconds=90, tvde_noshow_driver_fee_cents=350, tvde_cancel_fee_cents=0.
- [stated] A ordem prop-98c2fc14 ficou presa na aprovação; Danilo pediu o prompt pelo chat para colar à mão. Entregue como ficheiro PROMPT_tvde_pagamento_tokens_despacho.md (MOTOR OPUS 4.7), cobrindo os 5 bugs + comparação com o fluxo de entregas + painel admin.

REVISÃO DO TRABALHO DO EXECUTOR (2026-08-13, commit b7d2d94) — verificada por MCP
- [stated] CONFIRMADO por MCP que NADA foi aplicado em produção: `stripe-webhook` continua v32, `tvde-payment` continua v8, e as assinaturas de tvde_request_ride/tvde_cancel_ride/tvde_ride_charge_cents estão iguais. A palavra do executor bateu certo neste ponto.
- [stated] O EXECUTOR TINHA RAZÃO NO BUG 3 e eu estava errada no briefing: `est_fare_cents` JÁ NASCE LÍQUIDO de tokens (a subtracção acontece dentro de tvde_request_ride antes do INSERT). Se `tvde_ride_charge_cents` também subtraísse, descontava a dobrar (€5 → €3 → €1). NÃO MEXER nessa função. Guardar isto para nunca repetir o erro.
- [stated] ACHADO DE SEGURANÇA REAL (confirmado por mim na leitura do código v8): a acção `refund` do `tvde-payment` não verifica dono nenhum — qualquer utilizador autenticado reembolsava a corrida de outro só com o ride_id, e a taxa vinha do body (o cliente decidia quanto lhe voltava). Tem de entrar na aplicação.
- [stated] MINA CONFIRMADA POR MCP: em produção `tvde_create_roundtrip_credit_cash` tem 1 argumento (p_outbound_ride_id uuid). O working tree tem Flutter a chamá-la com 2 (tvde_store.dart, tvde_request_ride_screen.dart, tvde-plan-payment). Se isso for a deploy, parte o pacote ida-e-volta em dinheiro. Ficou fora do commit, e bem.
- [stated] DIVERGÊNCIA REPO vs PRODUÇÃO a resolver antes de aplicar: o executor diz que o PI `tvde_roundtrip` não leva `ride_id`; a `tvde-payment` v8 EM PRODUÇÃO leva (`meta = { kind:'tvde_roundtrip', method, ride_id, user_id, distance_km, applied }`). Ou seja, o ficheiro local está desalinhado do que está no ar — deploy às cegas do local pode reverter a v8.
- [stated] BRANCH POR DECIDIR: o executor está em `autonomous-night/fase2-cortex-tasks` e não fez push; o CI (Codemagic) constrói de `autonomous-night-2026-04-29`.
- [stated] Também reportado pelo executor (não corrigido, fica para sessão própria): nas ENTREGAS o `consume_tokens` corre no Flutter dentro de um catch mudo — mesmo buraco dos tokens, o saldo pode não baixar.

BUG 6 PROVADO POR MCP (2026-08-13 20:10) — motorista chamado ANTES de pagar
- [stated] Corrida 81d1bd09-cbd1-40d6-b78a-feefd58ca8ad: criada com `payment_method='cash'` e `payment_intent_id` NULL, apesar de o Danilo estar a escolher MB Way. Como `fn_tvde_dispatch_on_request` despacha CASH logo no INSERT, a cadeia disparou em 1,4s: oferta 20:10:43 → push_enviado 20:10:44 → motorista_atribuido/motorista_a_caminho 20:10:58 — com o cliente ainda no ecrã de pagamento. Às 20:12:44 a corrida foi cancelada com reason='payment_failed', taxa 0.
- [stated] Ou seja: o app cria a corrida ANTES de o método de pagamento estar decidido/cobrado e deixa cair no default 'cash'. Regra do Danilo: só chamar motorista depois do pagamento confirmado, tanto cartão como MB Way. Em dinheiro é que pode despachar logo.
- [stated] LADO BOM PROVADO: a máquina de despacho (tvde_offer_to_next → notify-tvde-driver → push → aceitar) FUNCIONA e é rápida. O que está errado é só o portão do pagamento.
- [stated] TOKENS DE TESTE dados por MCP a pedido do Danilo (2026-08-13 20:13): 2.000 tokens (=€10) na conta de CLIENTE dele c9fccf85-03ee-4efc-83bf-613f211a78ff (bora_tokens id 72ea2da0-6731-45ed-b715-6d617f499ce9, expira 12/10/2026). Saldo dele ficou 2.078 tokens ≈ €10,39. Serve para testar o desconto depois da correcção.

ARMADILHA POSTGRES a evitar no desarme da mina (verificada por MCP 2026-08-13)
- [stated] Em produção existe SÓ `tvde_create_roundtrip_credit_cash(p_outbound_ride_id uuid)` (oid 61459). Corpo lido: valida auth.uid() e dono da corrida, calcula preço por `tvde_roundtrip_price_for_km(est_distance_km)`, é idempotente (devolve vale existente com payment_intent_id NULL), grava `paid_cents = v_price` e liga `roundtrip_credit_id` à corrida.
- [stated] PERIGO: um `CREATE OR REPLACE` com 2 argumentos NÃO substitui a de 1 — cria uma SEGUNDA função (overload). A partir daí qualquer chamada com 1 argumento fica AMBÍGUA e o Postgres rebenta com "function is not unique", partindo o pacote ida-e-volta em dinheiro para toda a gente, incluindo as builds antigas já instaladas. A migration TEM de fazer DROP da versão de 1 argumento e criar a de 2 com `p_tokens_to_apply integer DEFAULT 0`, na mesma transacção. O DEFAULT é o que mantém as builds antigas a funcionar.
- [stated] Ao meter tokens nessa função: `paid_cents` tem de ficar líquido do desconto (é o que o cliente paga mesmo em mão), com o mesmo tecto de 50%, e sem descontar em duplicado com os tokens da própria corrida.
- [stated] Executor (commit be13c8e) corrigiu o BUG 6 em dois sítios: o Flutter deixou de criar a ida do pacote sem `paymentMethod` (caía no default 'cash'), e o gate `fn_tvde_dispatch_on_request` passou a exigir `payment_method = 'cash'` explícito, gravando `dispatch_deferred` no evento para o resto. Achado extra dele: `retryRide()` tinha o mesmo default — quem pagou por MB Way e carregava em "Tentar de novo" recebia uma corrida em DINHEIRO sem saber, e o motorista ia pedir o valor em mão a quem já tinha pago.
- [stated] VÁLVULA do executor: como o `'cash'` acidental era a ÚNICA coisa que despachava a ida do pacote online, `tvde_create_roundtrip_credit` passa a marcar `payment_status='succeeded'` ao ligar o vale, e o despacho sai pelo `tr_tvde_dispatch_on_paid` como em qualquer corrida paga.
- [stated] ORDEM DE APLICAÇÃO MUDOU: a migration do BUG 6 e o webhook do BUG 1 têm de ir JUNTOS. A migration sozinha tira o despacho no INSERT a cartão/MB Way e deixa as corridas online paradas.

DIVERGÊNCIA DO VALOR DO TOKEN (achada pelo executor, confirmada por MCP 2026-08-13)
- [stated] `tvde_request_ride` e `tvde_finish_ride` usam `p_tokens_to_apply * 5` (5 cêntimos por token) — cravado no SQL, sem ler definição nenhuma. Todo o resto (entregas, carteira, ecrãs do app, pacote online) usa `token_value_cents_x100`=50, ou seja 0,5 cêntimos. As RPCs do TVDE davam 10× o valor documentado (CLAUDE.md §5: 100 tokens = €0,50). Nunca se notou porque os tokens nunca chegavam a ser descontados no TVDE (BUG 2).
- [stated] EXPOSIÇÃO medida por MCP no momento da decisão: 3.233 tokens activos em 5 pessoas → €16,17 a 0,5c, ou €161,65 a 5c.
- [stated] DECISÃO (Claude.ai, comunicada ao Danilo): alinhar TUDO em 0,5 cêntimos, lendo `token_value_cents_x100`, e nunca voltar a cravar o valor no SQL. Fundamento: é o que os ecrãs do app mostram ao cliente e o que está documentado; ninguém foi prometido 5c e ninguém perde nada, porque o desconto nunca chegou a sair.
- [stated] Executor (commit 1ec200c) desarmou a mina como pedido: DROP da função de 1 argumento + CREATE da de 2 com DEFAULT 0, tudo na mesma transacção da migration do BUG 6, DROP deliberadamente SEM `IF EXISTS` (aborta tudo em vez de deixar meio-estado). Repôs os grants a `authenticated` + `service_role` e NÃO repôs PUBLIC/anon. Tokens do pacote ficam registados na IDA (o vale não tem colunas para isso), passando pelo consumidor único `tr_tvde_consume_tokens`; guard anti-duplo grava `tokens_skipped_on_credit`.
- [stated] AINDA DE PÉ, não fazer deploy: `tvde-plan-payment` chama `tvde_create_roundtrip_credit` com 6 argumentos e produção tem 4 (confirmado por MCP). A migration 20260804000000 existe e está por aplicar; se for aplicada DEPOIS da do BUG 6 tem de levar a linha do `payment_status`, senão a ida do pacote online deixa de ser despachada.
- [stated] Estado: 3 commits locais (be13c8e, 1ec200c e o anterior b7d2d94), nada aplicado, nada em push.

PRONTO A APLICAR (2026-08-13, fim da sessão) — nada em produção ainda
- [stated] REGRA NOVA QUE FICA: o valor do token e o tecto de desconto NUNCA se cravam no SQL — lêem-se sempre de `token_value_cents_x100` e `token_payment_max_pct`. O tecto também estava cravado nas duas RPCs do TVDE, e por isso o botão do painel admin nunca teve efeito nenhum nas corridas.
- [stated] CONFIRMADO por MCP no fim da sessão: produção continua intocada — `tvde_request_ride` e `tvde_finish_ride` ainda têm o `* 5` e não lêem definição nenhuma; `tvde_create_roundtrip_credit_cash` ainda tem 1 argumento; `stripe-webhook` v32; `tvde-payment` v8. Os 4 commits (b7d2d94, be13c8e, 1ec200c, bd9517d) estão locais e sem push.
- [stated] `tvde_finish_ride` entrou por CREATE OR REPLACE com assinatura idêntica (p_ride_id uuid, p_final_distance_km numeric, p_distance_source text, p_tokens_to_apply integer) — sem risco de overload, ao contrário do caso `_cash`.
- [stated] ORDEM DE APLICAÇÃO acordada: migration 20260813200000 → migration 20260813210000 → webhook (aplicar a proposta + deploy) → tvde-payment → app. Os passos da migration do BUG 6 e do webhook do BUG 1 vão SEMPRE juntos.
- [stated] Prova a exigir depois de aplicar: numa corrida MB Way o evento `solicitada` tem de trazer `dispatch_deferred=true` e não pode haver `oferta` até o pagamento fechar; uma corrida em dinheiro tem de continuar a despachar na hora; e uma corrida com tokens tem de mostrar `tokens_applied_value_cents` > 0 com o saldo do cliente a baixar.

APLICADO EM PRODUÇÃO (2026-08-13, fim) — verificado por MCP
- [stated] Migrations 1 e 2 APLICADAS: `tvde_request_ride` e `tvde_finish_ride` já lêem `token_value_cents_x100` e `token_payment_max_pct` (o `* 5` que sobra em tvde_finish_ride é só o comentário a explicar o que era); `tvde_create_roundtrip_credit_cash` ficou com UMA só assinatura `(uuid, integer)` — o DROP+CREATE correu bem, sem overload. `stripe-webhook` foi de v32 para v33.
- [stated] O executor avisou que o `anon` voltou pelas default privileges do Supabase na função nova, ao contrário do que documentou. Verificar/revogar.
- [stated] PASSO 4 NÃO FOI FEITO, e ainda bem: ao fazer o diff que pedi, o executor descobriu que o ficheiro `tvde-payment` do REPO está DUAS releases atrás da v8 em produção (461 linhas contra ~700). Falta-lhe `getOrCreateCustomer` (cartões guardados), `saved_pm_id`/`off_session`/`setup_future_usage`, `requiresAction` (3DS sem cancelar corrida), `charge_roundtrip` e `confirm_roundtrip_payment`. Publicar o ficheiro do repo apagava os cartões guardados, o 3DS e o pacote ida-e-volta online inteiro.
- [stated] CONSEQUÊNCIA DIRECTA: os tokens CONTINUAM sem descontar nas corridas pagas por cartão/MB Way, porque quem passa `tokens_to_apply` ao servidor é precisamente o `tvde-payment` — o único passo que ficou por aplicar. Danilo confirmou isso a testar (corrida de €5 continua a cobrar €5 mesmo carregando em usar tokens).
- [stated] CAMINHO CERTO para o passo 4: a base do ficheiro tem de ser a v8 LIDA DE PRODUÇÃO pelo MCP (como ele fez no webhook), não o ficheiro do repo. E o repo tem de ser re-sincronizado a partir de produção, senão a divergência volta a morder.
- [stated] PROVAS do executor (corridas reais dentro de BEGIN…ROLLBACK, saldo do Danilo intacto no fim): MB Way nasce com `dispatch_deferred=true` e ZERO ofertas; dinheiro despacha na hora; com 100 tokens numa corrida de €5 o valor caiu para €4,50 (100 tokens = €0,50) e o saldo baixou 100 ao marcar succeeded. Ou seja, a cadeia SQL está boa — falta só o transporte dos tokens.
- [stated] A CORRIDA DOS €5 foi corrigida na base (verificado por mim): `cancel_fee_cents` 500→0 e `payment_status` refunded→succeeded. O reembolso em si NÃO foi feito — tem de sair pelo dashboard da Stripe, porque o MCP da sessão dele (e o meu) só vê sandbox.
- [stated] PUSH NÃO FEITO por duas razões boas: não há chave SSH na máquina (`Permission denied (publickey)`) e o ramo local está 12 commits à frente de `autonomous-night-2026-04-29`, dos quais 8 não são da missão (incluem o Stripe Connect Fase 1 e um bump de versionCode) — empurrar HEAD levava tudo isso de boleia. Caminho acordado: cherry-pick dos commits da missão, depois de resolvida a chave SSH.
- [stated] O executor corrigiu-se: tinha dito que `charge_roundtrip` não existia no tvde-payment — não existe no REPO, existe em PRODUÇÃO. O meu briefing estava certo nesse ponto.

SSH/GIT PUSH — investigação da chave do hermes (2026-08-13, verificado pelo próprio executor)

