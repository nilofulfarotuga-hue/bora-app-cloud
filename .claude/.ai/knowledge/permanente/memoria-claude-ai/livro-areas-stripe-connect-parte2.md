---
id: memoria-claude-ai-livro-areas-stripe-connect-parte2
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-04
zona: verde
confianca: alta
estado: atual
---

# Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata por preencher, repasse automático ainda desligado), como gerar o link de cadastro, taxas por parceiro e plano por fases (parte 2 de 3)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-stripe-connect-parte2`, origem `claude-ai`, atualizada em 2026-11-04T21:13:32.954255+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas stripe connect parte2 · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/stripe-connect.md), copiada a 2026-11-04 21:15 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos. (parte 2 de 3 — começa em livro-areas-stripe-connect, continua em livro-areas-stripe-connect-parte3)

CAUSA RAIZ ACHADA (2026-08-13, verificada por MCP) — TVDE MB Way não chama motorista
- [stated] `stripe-webhook` (v32) NÃO tem ramo para corridas: PIs com metadata.kind='tvde_ride'/'tvde_roundtrip'/'tvde_stop' caem no else e só registam "missing metadata.draft_id and order_id". Logo `tvde_rides.payment_status` nunca passa a 'succeeded' pelo servidor.
- [stated] Cadeia de despacho (lida do banco): trigger `tr_tvde_dispatch_on_request` só despacha CASH no insert; `tr_tvde_dispatch_on_paid` só corre quando payment_status vira 'succeeded' → `tvde_offer_to_next` → `tr_notify_tvde_driver_on_offer` → Edge Fn `notify-tvde-driver`. Como o 'succeeded' só vem do poll do cliente (confirm_ride_payment, 3s/120s), se o MB Way demorar mais de 2 min ou a app fechar, NENHUM motorista é chamado. Todas as corridas têm tried_driver_ids=[] e current_offer_driver_id=null.
- [stated] O motorista não é o problema: Danilo estava online, com token FCM, coordenadas e heartbeat fresco em drivers + driver_locations.
- [stated] CLIENTE REAL PERDIDO: users e99d105d-f6e9-40a3-b809-0981c31235b0 (jvillarroeltrm@gmail.com, sem nome nem telefone gravados, registado 07/08) — 3 corridas: 12/08 14:37 e 13/08 12:41 pagou €5 por MB Way, esperou ~2 min sem motorista, cancelou e foi reembolsado; 12/08 15:00 fez uma em dinheiro que essa sim terminou.
- [stated] Danilo (13/08): o "passar o cartão por aproximação no telemóvel" é a máquina dele fora do app (ele mesmo mete o valor e o cliente aproxima) — NÃO tem a ver com o Bora App. O problema do app é o MB Way não chamar o motorista.
- [stated] Ordem criada para corrigir (zona vermelha, à espera do "vai" do Danilo): prop-98c2fc14 "tvde-mbway-nao-chama-motorista" — ramo TVDE no webhook, ecrã "à espera da confirmação MB Way" + poll 300s, auditar o mesmo buraco nas entregas, lista admin de corridas presas no pagamento, e limpar a corrida presa e3a6cc36 (PI pi_3U43bSGlT3R2jCYp1WuEIVxZ).
- [stated] BONIFICAÇÃO FEITA por MCP a pedido do Danilo (2026-08-13): 1.000 tokens (=€5, `token_value_cents_x100`=50 → 0,5 cêntimos/token) creditados ao cliente e99d105d, válidos 60 dias (bora_tokens id eed4bc09-3162-44d2-8dd5-e768ea00f3a2, expira 12/10/2026), com linha em admin_audit_log. O RPC `admin_grant_tokens` exige `_admin_op_guard()` (JWT de admin), por isso não corre por MCP — foi INSERT direto + auditoria à mão. Guardar esta nota.
- [stated] LIMITE A TER EM CONTA: `token_payment_max_pct`=50 — tokens só pagam até 50% de cada pedido/corrida. Logo os €5 de tokens não pagam uma corrida de €5 inteira; dão desconto de €2,50 em duas corridas de €5. Danilo foi avisado.
- [stated] Email de desculpas ao cliente ficou em RASCUNHO no Gmail do Danilo (draft r-4592156499866028835) — o conector Gmail da Claude.ai só cria rascunhos, não envia. É o Danilo que carrega em Enviar.

TESTE DO DANILO 13/08 19:01 — mais 3 bugs provados por MCP (corrida 09c01c88-cc50-419d-951e-15c7afc6b033, PI pi_3U43sVGlT3R2jCYp0fulK3tK)
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

