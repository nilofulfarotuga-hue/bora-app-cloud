---
id: memoria-claude-ai-livro-areas-stripe-connect
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-24
zona: verde
confianca: alta
estado: atual
---

# Stripe Connect Express no Bora — decisão do Danilo, estado real (conta dele de motorista já ATIVA, Goola e Ouro e Prata por preencher, repasse automático ainda desligado), como gerar o link de cadastro, taxas por parceiro e plano por fases (parte 1 de 3 — continua em livro-areas-stripe-connect-parte2…)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-stripe-connect`, origem `claude-ai`, atualizada em 2026-10-24T10:15:08.344117+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas stripe connect · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/stripe-connect.md), copiada a 24/10/2026 11:13 (Lisboa). A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

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

