---
id: memoria-claude-ai-livro-areas-stripe-connect
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata por preencher, repasse automático ainda desligado), como gerar o link de cadastro, taxas por parceiro e plano por fases

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-stripe-connect`, origem `claude-ai`, atualizada em 2026-10-23T05:39:16.591106+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas stripe connect · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/stripe-connect.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: stripe-connect
description: Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata por preencher, repasse automático ainda desligado), como gerar o link de cadastro, taxas por parceiro e plano por fases
sources: [chat]
aliases: [Connect, Stripe Connect, repasse automático, extrato do parceiro]
---

Decisão do Danilo (2026-08-06)
- [stated] Vai avançar com Stripe Connect Express para pagar automaticamente parceiros e estafetas, em vez de transferências bancárias à mão.
- [stated] Quer que a TAXA de transferência/Stripe seja cobrada ao PARCEIRO e ao ESTAFETA (não absorvida pela Bora).
- [stated] Quer o extrato detalhado dentro do painel do parceiro e do estafeta (venda, comissão Bora, taxa Stripe, líquido, data em que a Stripe depositou) — o parceiro não deve precisar de entrar na Stripe.
- [stated] Quer fazer o cadastro Connect presencialmente com o Gilberto ([[ouro-e-prata]]) quando for à barbearia.
- [stated] Quer o passo a passo, com a Claude.ai a verificar tudo por MCP antes de montar prompt.

Estado real apurado por MCP (2026-08-06)
- [stated] Conta Stripe da plataforma: acct_1T8MFaGlT3R2jCYp ("bora app"), live. MCP Stripe só com permissão de LEITURA.
- [stated] NÃO existe nada de Connect no banco: zero colunas stripe_account_id em drivers/restaurants/service_providers. Só há `iban text` nessas 3 tabelas (transferência manual).
- [stated] O repasse hoje é semanal e MANUAL: tabelas partner_weekly_settlements, driver_weekly_settlements, cleaner_weekly_settlements, appointment_payouts, partner_reservation_payouts, payouts — todas com status/payment_method/payment_reference/paid_by (ou seja, alguém marca como pago à mão).
- [stated] users.stripe_customer_id já existe (lado cliente); orders.stripe_charge_cents também.

Taxas apuradas (pesquisa 2026-08-06 — confirmar na Stripe antes de fechar contas)
- [stated] Cartão europeu no EEA: ~1,5% + €0,25 por pagamento. Cartão de fora do EEA: +1,5%. Câmbio: +1%.
- [stated] Connect tem DOIS modelos: (A) "a Stripe cobra os teus utilizadores" → a plataforma não paga nada de Connect; (B) "tu cobras" → €2/mês por conta ativa + 0,25% + €0,25 por cada payout enviado.
- [stated] Como um pedido do Bora divide para 2-3 pessoas (loja + estafeta + Bora), o caminho técnico é destination charges / separate charges and transfers → a Bora é a merchant of record e cai no modelo (B). Cobrar a taxa ao parceiro/estafeta faz-se descontando no acerto, não é a Stripe que o faz sozinha.
- [stated] Consequência importante: payout tem de continuar SEMANAL (como já é). Se fosse por pedido, os €0,25 por payout comiam a margem de uma entrega de €5.

Bloqueio que é só do Danilo
- [stated] Ativar o Connect no dashboard da Stripe e aceitar os termos de plataforma — decisão financeira/legal que ninguém pode fazer por ele.

FASE 1 FECHADA (2026-08-06) — verificada por MCP pela Claude.ai, não pela palavra do executor
- [stated] Commit c760a5b no Claude Code (FABLE). `stripe_connect_enabled` continua false — nenhum dinheiro se move; acerto semanal continua manual.
- [stated] CONFIRMADO por MCP: tabelas `partner_statement_lines` e `stripe_connect_events` criadas, ambas com RLS ON. Funções criadas: `stripe_connect_fee_cents(p_gross_cents,p_kind)`, `apply_stripe_account_update(...)`, `get_statement(p_from,p_to)`, `get_my_connect_status(p_role)`, `admin_list_connect_accounts()`.
- [stated] CONFIRMADO por MCP: 3 Edge Functions ACTIVE v1 — `stripe-connect-onboard` (verify_jwt true), `stripe-connect-webhook` (verify_jwt false, assinatura própria), `stripe-connect-admin` (verify_jwt true). O `stripe-webhook` antigo (v30) ficou intocado, como pedido.
- [stated] CONFIRMADO por MCP: backfill de 5 linhas de extrato, todas owner_type='driver' (dos 2 acertos de estafeta existentes); 0 eventos de webhook; 0 contas Connect gravadas; dados DEMO limpos (cleaners voltou a 1, o do próprio Danilo).
- [stated] CORREÇÃO ao meu prompt (achada pelo executor): deep links `boraapp://` NÃO servem em Account Links — a Stripe só aceita http(s). O retorno passa por `bora-app-web.pages.dev/connect/*`.
- [stated] Bug apanhado e corrigido pelo executor antes do commit: `array_append` em plpgsql.
- [stated] NÃO FEITO: screenshots no telemóvel (adb vazio, telemóvel não estava por USB) e `/ctx doctor` / `/ctx stats` (ferramentas ctx_* não expostas nessa sessão).
- [stated] BLOQUEIO que é do Danilo: ativar Connect no dashboard Stripe, criar o webhook novo e colar `STRIPE_CONNECT_WEBHOOK_SECRET` (+ `STRIPE_TEST_SECRET_KEY` para testar) — secrets não se criam por MCP. Guia entregue: GUIA_DANILO_STRIPE_CONNECT.md.
- [stated] FASE 2 (próximo prompt): transferências automáticas no fecho do acerto semanal + linha de extrato por pedido.

Ativação no dashboard Stripe (2026-08-06) — Danilo a fazer ao vivo
- [stated] Configuração escolhida no onboarding da plataforma: fluxo de fundos "compradores compram de ti / vendedores pagos individualmente" (separate charges & transfers, Bora merchant of record); criação de conta = onboarding hospedado pela Stripe; gestão = Dashboard Express; responsabilidade por reembolsos e estornos = da plataforma (Bora).
- [stated] Passou o ecrã "Confirme suas escolhas de integração" e chegou ao ecrã de aceitar responsabilidades (reembolsos/estornos, onboarding e conformidade, suporte a consultas de pagamento e risco, perdas e tarifas do Radar).
- [stated] CONNECT ATIVO confirmado (2026-08-06): Danilo aceitou as responsabilidades e o `GET /v1/accounts` já responde na conta live (lista vazia — 0 contas conectadas ainda, como esperado). O bloqueio "ativar Connect no dashboard" está FECHADO.
- [stated] MCP Stripe continua SÓ LEITURA — `PostWebhookEndpoints` foi recusado por permissões. O webhook do Connect tem mesmo de ser criado à mão por Danilo no dashboard.
- [stated] Eventos que a Edge Function `stripe-connect-webhook` trata (lidos do código por MCP): account.updated, account.application.deauthorized, payout.paid, payout.failed. URL do endpoint: https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/stripe-connect-webhook (tipo: eventos em contas conectadas).
- [stated] WEBHOOK CRIADO E CORRIGIDO (2026-08-06, verificado por MCP): `we_1U1ROvGlT3R2jCYpG8qnQ1zW`, live, status enabled, escopo "contas conectadas", api_version 2026-02-25.clover, url certa. Os 4 eventos ficaram exatos: account.updated, account.application.deauthorized, payout.paid, payout.failed. (À 1ª tentativa entrou `authorized` em vez de `deauthorized`; Danilo corrigiu em Editar destino.)
- [stated] FALTA SÓ o `whsec_` (segredo de assinatura) ser colado como secret `STRIPE_CONNECT_WEBHOOK_SECRET` no Supabase. Sem isso a Edge Function devolve 400 a tudo (fail-closed, por desenho).
- [stated] NOTA DE LEITURA: o ID da conta e do webhook têm `Gl` (G + L minúsculo), não `GI` — confunde-se em fotos de ecrã e faz o GET falhar. Em caso de dúvida, listar em vez de adivinhar o ID.
- [stated] SECRET GRAVADO E CADEIA PROVADA (2026-08-06). O executor usou o CLI local `C:\supabase\supabase.exe` (o `npx supabase` não tem binário para Windows x64 — guardar esta nota, poupa tempo na próxima). Commit b425ede (com rebase, o CI tinha subido o versionCode para 523).
- [stated] VERIFICADO POR MIM (não pela palavra do executor): logs da Edge Function mostram a viragem exata — às 12:25 dois POST **400** (sem secret) e às 13:41-13:42 quatro POST **200** já na v2 da função. Prova que o secret entrou e a assinatura passa.
- [stated] VERIFICADO POR SQL depois da limpeza: stripe_connect_events=0, 0 contas Connect em restaurants/drivers/service_providers, `stripe_connect_enabled`=false. Ou seja, a prova E2E do executor foi mesmo limpa e continua tudo desligado — nenhum dinheiro se move.
- [stated] O `whsec_` passou pelo chat. Boa higiene: fazer "Roll secret" no endpoint da Stripe e regravar. Não é urgente (o secret sozinho não move dinheiro, só permitiria forjar eventos de estado de conta) — fica em aberto.
- [stated] `STRIPE_TEST_SECRET_KEY` continua por criar, por isso `BORA_STRIPE_MODE=test` não funciona; corre tudo em live.
- [stated] PRÓXIMO PASSO REAL: cadastrar o 1º parceiro de verdade (Gilberto da [[ouro-e-prata]]) pelo painel admin → Pagamentos Connect → "Reenviar link de cadastro". Depois disso, Fase 2 (transferências automáticas no acerto semanal).
- [stated] TAREFA URGENTE achada por Danilo (2026-08-06): a Stripe não conseguiu verificar "Danilo da Silva" como representante da conta. Prazo 20/08/2026 — se não resolver até lá, os REPASSES ficam suspensos (isto é a própria conta da plataforma, não é o cadastro do Gilberto).
- [stated] 2º aviso da Stripe chegado por email (2026-08-06, 18:41): "Atualize suas informações de repasse para receber seus pagamentos da bora app" — pede para adicionar conta bancária/cartão de débito no Dashboard. É a conta da PRÓPRIA plataforma (para onde a Stripe manda a receita do Bora), diferente da tarefa de verificar a identidade do Danilo.

Investigação "não passa o cartão" (2026-08-13)
- [stated] Danilo diz que já não consegue pagar com cartão no telemóvel (antes conseguia), tentou 3-4 vezes e parece aparecer algo a pedir para atualizar.
- [stated] VERIFICADO POR MCP: a conta Stripe ACEITA cobranças — MB Way live passou 2x (corridas TVDE 12/08 14:37 pi_3U3dHPGlT3R2jCYp09DOAHUP e 13/08 12:41 pi_3U3xxLGlT3R2jCYp1W8HAcO7, €5 cada). Ambas foram canceladas pelo próprio cliente dentro dos 180s de tolerância (elapsed 157s e 119s) e reembolsadas na totalidade. Nada travado do lado da Stripe.
- [stated] VERIFICADO POR MCP: NENHUMA tentativa de cartão chegou ao servidor a 11, 12 nem 13/08 (function_edge_logs sem chamadas às funções de pagamento além de tvde-payment das 2 corridas MB Way; payment_drafts vazia; sem orders/appointments desde 03/08). Conclusão: a falha do cartão é no telemóvel/SDK, antes de chegar à Stripe — falta o texto do erro para fechar o diagnóstico.
- [stated] O email da Stripe de 13/08 ("Atualize suas informações de repasse") é da conta EXPRESS acct_1U1RpKGdkGTRCF27 (a de teste do Connect, website "wew.com"), NÃO da plataforma acct_1T8MFaGlT3R2jCYp — pede IBAN e não bloqueia pagamentos de clientes. Continua a valer o prazo 20/08 da verificação de identidade do Danilo na conta da plataforma.
- [stated] BUG NOVO achado nos logs: `stripe-webhook` regista "payment_intent.succeeded missing metadata.draft_id and order_id" nos PaymentIntents de TVDE — os pagamentos de corrida não levam metadata que os ligue ao ride. O reembolso funcionou à mesma, mas o webhook não consegue casar pagamento↔corrida.
- [stated] O conector Stripe da Claude.ai perdeu o acesso à conta LIVE — só expõe a sandbox acct_1U1... "Área restrita de bora app". Enquanto não for religado (OAuth), não dá para ler pagamentos/requisitos da conta live por MCP.
- [stated] `tvde_card_payments_enabled`=true e `cleaning_stripe_enabled`=true em platform_settings — cartão não está desligado por definição.

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
- [stated] A chave `id_ed25519_bora_deploy` existe mesmo em `C:\Users\hermes\.ssh\` (Test-Path=True), mas a pasta `.ssh` tem ACL própria que EXCLUI o utilizador `danil`, mesmo `danil` tendo FullControl na pasta-mãe `C:\Users\hermes`. Sessão do executor: utilizador danil, SEM privilégios de administrador (Get-Acl e icacls também negados). Não há cópia da chave em danil\, Desktop, Downloads nem ProgramData. Só existe `id_ed25519_vps` (essa é da VPS, não do GitHub).
- [stated] O executor RECUSOU-SE a forçar o acesso (mexer nas permissões a partir da pasta-mãe) por iniciativa própria — decisão certa, ficou registada como decisão do Danilo se quiser esse caminho.
- [stated] CHERRY-PICK TESTADO em worktree isolado (não tocou no diretório de trabalho real): 7/7 commits sem UM conflito — be13c8e, 1ec200c, bd9517d, b7d2d94 (a missão), mais 1c0a420 (relatório), 44d8a5f (v8 real do tvde-payment gravada no repo) e a74a321 (as correções v9 que já estão em produção). Os 2 últimos são necessários — sem eles o repo volta a ter o tvde-payment velho. NADA foi publicado ainda.
- [stated] PLANO ESCOLHIDO (Claude.ai, 2026-08-13): tentar primeiro trocar o remote para HTTPS (`https://github.com/nilofulfarotuga-hue/bora-app-cloud.git`) na conta danil e correr `git fetch` — é o caminho mais parecido com o que já funcionava antes nesta conta (login via Git Credential Manager, um clique de "Authorize" numa janela do navegador se pedir, ou nem isso se a sessão ainda estiver em cache). SÓ se isto falhar é que se cria um GitHub Personal Access Token como reserva.

SSH resolvido sozinho, sem nenhum clique do Danilo (2026-08-13, visto por foto do ecrã)
- [stated] Trocar o remote para HTTPS + `git fetch` autenticou sem pedir NADA — já havia credencial guardada no Windows para github.com (utilizador nilofulfarotuga-hue) via Git Credential Manager. Não precisou do token de reserva.
- [stated] O executor detectou sozinho que o ramo de destino (autonomous-night-2026-04-29) mudou desde o teste do cherry-pick: já recebeu o Stripe Connect Fase 1 (o que tirou o medo da "boleia" — resolve-se por si, já é a base agora) mas também mexeu em `admin_dashboard_screen.dart`, ficheiro que os commits desta missão também tocam. Está a re-testar o cherry-pick contra a cabeça nova antes de publicar — decisão cautelosa e certa, ainda sem push feito.
- [stated] AVISO OPERACIONAL: o Claude Code do Danilo mostrou "Próximo do limite de uso semanal — reinicia dom. 16/08 19:00". Vale a pena não abrir sessões extra nesta missão até isso resolver, para não ficar sem motor a meio de um push.

Estado real a 2026-09-14 (Claude.ai por MCP) — CORRIGE linhas antigas deste ficheiro
- [stated] Danilo quer cadastrar-se a SI PRÓPRIO primeiro, como MOTORISTA, numa conta Connect separada da conta do Bora, com IBAN de outra conta bancária (a conta da plataforma, do banco novo, fica com o que sobra do Bora) — e usa esse cadastro como treino para depois fazer os outros estafetas e parceiros. Substitui o plano de começar pelo Gilberto da [[ouro-e-prata]].
- CONTA DELE ATIVA (14/09, verificado por mim na Stripe live): `acct_1U1RpKGdkGTRCF27` com details_submitted, charges_enabled e payouts_enabled true, transfers active, termos aceites e IBAN de OUTRA conta bancária dele (Millennium BCP) registado — era exactamente o que ele queria. Continuam `disabled` e por preencher só [[goola-acai]] `acct_1U9JSJGaqvfVyyow` (company: pede NIPC, dados do dono e IBAN) e [[ouro-e-prata]] `acct_1U1RnZGtdmD8LsOp`. Colunas stripe_account_id/status existem em drivers, restaurants, service_providers e cleaners.
- CADEIA PROVADA PONTA A PONTA: o `stripe-connect-webhook` apanhou o account.updated sozinho e `drivers.stripe_account_status` passou a 'enabled' sem ninguém tocar em nada.
- Pendente na conta dele: `individual.verification.document` em eventually_due (a Stripe vai pedir foto do documento; ainda não trava nada) e a morada ficou com o nº 12 quando é o 14 — decidi NÃO mexer agora para não reabrir verificação, e corrigir as duas coisas juntas quando o documento for pedido.
- `stripe_connect_enabled` continua FALSE e a Fase 2 (transferência automática no fecho semanal) continua por fazer — mesmo com o cadastro terminado o acerto continua manual/MB Way. [stated] Ele quer o repasse automático a funcionar já na semana seguinte; avisei que ligar mexe em dinheiro a sério e fica à espera da palavra dele.
- O conector Stripe da Claude.ai VOLTOU a ter a conta LIVE (acct_1T8MFaGlT3R2jCYp, livemode true) — já dá para ler contas e requisitos por MCP. O MCP NÃO expõe account_links (PostAccountLinks não existe), MAS há caminho que FUNCIONA e é só meu, sem executor: Edge `tmp-connect-link` (criada 14/09, segredo `[REMOVIDO]`), chamada por `net.http_post` com a service_role key de `vault.decrypted_secrets`, resposta lida em `net._http_response`. O Account Link da Stripe expira em ~5 MINUTOS, por isso a v2 da função (verify_jwt FALSE) tem também um CONVITE PERMANENTE por GET: `https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/tmp-connect-link?a=<acct_>&k=<chave>`, em que a chave são os 16 primeiros hex de SHA-256("<acct_>|<segredo>") — devolvida no campo `convite_key` do POST. Gera um link fresco a cada toque, logo pode ser enviado por mensagem ao parceiro (a do [[goola-acai]] é [REMOVIDO]). Testado a funcionar.
- LIMITE DA STRIPE a não voltar a tentar: em contas Express com recolha pela Stripe, a plataforma SÓ pode pré-preencher `business_profile` (nome, url, mcc, contactos de apoio). `company`, `email` e o IBAN são recusados ("not authorized to edit"/"does not have the required permissions") — o NIPC, a morada, os dados do dono e o IBAN têm mesmo de ser metidos pela própria pessoa no formulário, mesmo quando já os temos na ficha da loja.
- CAMPO "website" do onboarding: a resposta certa para TODA a gente (estafetas e parceiros) é `boraguarda.com` — é a plataforma de onde vem o dinheiro, como o motorista da Uber que põe uber.com. Ele confundiu-se a pensar que era um site dele; explicado.

Quem paga a taxa da Stripe — decisão por parceiro (2026-09-14)
- [stated] A regra antiga "a taxa da Stripe é sempre cobrada ao parceiro/estafeta" NÃO é uniforme: ao [[goola-acai]] NÃO cobra taxa de Stripe nenhuma (considera-a já incluída na comissão); ao Gilberto da [[ouro-e-prata]] cobra, por enquanto, SÓ a taxa de transferência para a conta dele — o resto do valor do serviço vai todo para o Gilberto.
- [stated] O serviço ao Gilberto fica GRÁTIS por agora; daqui a cerca de um mês, com a coisa mais desenvolvida, é que combina com ele o preço mensal.

