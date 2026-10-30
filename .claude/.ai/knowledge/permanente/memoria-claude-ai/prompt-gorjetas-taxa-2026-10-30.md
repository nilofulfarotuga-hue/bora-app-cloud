---
id: memoria-claude-ai-prompt-gorjetas-taxa-2026-10-30
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-30
zona: verde
confianca: alta
estado: atual
---

# Prompt — gorjetas: taxa da Stripe na gorjeta paga depois e gorjeta do carrinho junto da compra (30/10/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `prompt-gorjetas-taxa-2026-10-30`, origem `claude-ai`, atualizada em 2026-10-30T13:55:41.466213+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: prompt gorjetas taxa 2026 10 30 · memoria claude.ai · claude_ai_memoria

⚠️ MODO PROTECÇÃO TOTAL ⚠️

MOTOR: Fable 5.1 (missão de dinheiro; se esta sessão for Opus 5.5, segue na mesma) · PORTA: Claude Code no PC do Danilo (pasta do repo bora-app-cloud; trabalho num ramo/worktree próprio, ver ARRANQUE)
MISSÃO: gorjetas-taxa-2026-10-30 (e2e_log: fluxo `gorjetas-taxa-2026-10-30`, um passo por bloco)
ORQUESTRADOR: entra pelo CEO-AI (`.claude/skills/ceo-ai/`) e segue a skill `protocolo-missao-bora`. Esquadrão: líder + pagamentos (Edge Functions/SQL) + app cliente/estafeta + admin (paridade) + juiz. Agentes em paralelo quando os ficheiros não chocam; o líder junta, revê e faz os commits.

AUTORIZAÇÃO (texto literal do Danilo à Claude.ai, 30/10/2026 13:40, depois de escolher a opção 1 "descontar a taxa exata da Stripe"): "Eu quero a opção 1, descontar a taxa extra da Stripe. E também, se for no carrinho junto à gorjeta, já inclui já a taxa, certo? Alguma coisa assim. Mas aí, se o cliente quiser pagar a gorjeta depois, aí desconta a taxa. Então já vai, faz bem arrumado aí, arruma tudo aí."
Vale para: a regra nova das gorjetas, cobrar a gorjeta do carrinho no mesmo pagamento da compra, devolver a gorjeta quando o pedido é cancelado, e o que for preciso nos ecrãs, painel e textos para isso. NÃO vale para mudar preços, comissões, taxas de entrega ou de serviço, nem para mexer no dinheiro de clientes ou prestadores antigos — isso fica com a Claude.ai e o Danilo.

A REGRA (Danilo, 30/10/2026):
1. Gorjeta dada NO CARRINHO (checkout) com cartão ou MB Way → vai no MESMO pagamento da compra. Não há taxa à parte, por isso vai INTEIRA para o estafeta.
2. Gorjeta paga DEPOIS (ecrã de avaliação da entrega ou da corrida TVDE) com cartão ou MB Way → é um pagamento à parte; o estafeta/motorista recebe a gorjeta MENOS a taxa exata que a Stripe cobrou nesse pagamento. Exemplo real: 2,00 € − 0,28 € = 1,72 €.
3. Gorjeta em dinheiro → inteira (não passa pela Stripe).
4. A Bora não ganha nada em cima de gorjeta. Pedido cancelado → a gorjeta volta inteira ao cliente.

CARTA DE AUTONOMIA: decides sozinho, nunca terminas o turno à espera, saltas o que estiver bloqueado (regista em docs/TRANCAS.md) e segues, reportas pelo Telegram, e no fim crias tu a continuação se faltar algo (cortex_nova_ordem). Erro que encontres fora do que está aqui: REPORTA no e2e_log e no relatório, não corrijas calado. Se a bora-tranca recusar escrever algo de dinheiro, não contornes: deixa tudo pronto, regista e escreve no relatório "⚠️ ISTO MEXE EM DINHEIRO — está tudo pronto" (a Claude.ai trata pelo GitHub web, como a 29/10).

ARRANQUE: lê `erros-aprendidos`, `regras-do-danilo`, `livro-indice`, `livro-areas-gorjeta` e o digest mais recente (claude_ai_memoria), o `.claude/.ai/business_rules.md` §4.5 e §13.4, e a migração `supabase/migrations/20261004100000_gorjetas.sql` (desenho de 04/10). Antes de mexer no código vê o estado local do PC: a pasta principal tem trabalho de outras sessões. Trabalha num worktree novo (ex.: C:\BoraLocal\wt-gorjetas-30-10, ramo `gorjetas-taxa-2026-10-30`) a partir de origin/autonomous-night-2026-04-29. `git add` só por caminho, nada de WIP de outras sessões. Não pares a sessão do Harness nem outras missões que estejam a correr.

BLOCO 0 — O que a Claude.ai já fez no banco (30/10 ~13:55, por MCP) — NÃO aplicar de novo
- Migração em produção `gorjeta_paga_depois_desconta_taxa_stripe_2026_10_30`:
  a) coluna gerada `tips.liquido_prestador_cents` = se moment='after' e method em ('card','mbway'): amount_cents − COALESCE(stripe_fee_cents, 25 + CEIL(amount_cents × 0,015)) (nunca abaixo de 0); senão amount_cents;
  b) `gorjetas_online_do_prestador` (usada por `compute_driver_settlement`) soma `liquido_prestador_cents`;
  c) `admin_tvde_acertos_por_tipo` (CTE gorjetas) soma `liquido_prestador_cents`.
  Cópia das funções antigas em `bkp_fn_gorjeta_liquida_20261030`.
- Prova: gorjeta 51d1b251 (29/10, corrida TVDE b36ecbb4, MB Way, cliente Elisabete, motorista Danilo): 200 − 28 = 172; `gorjetas_online_do_prestador(Danilo, semana 26/10–01/11)` = 1,72.
- Tarefa: grava esta migração no repo (`supabase/migrations/`) com a definição completa tirada de `pg_get_functiondef` e de information_schema. Nada mais neste bloco.

BLOCO A — Gorjeta do carrinho no mesmo pagamento da compra (cartão e MB Way)
- Hoje: `lib/screens/cart_screen.dart` `_tratarGorjetaDoCheckout` → `TipService.cobrar(moment: 'checkout')` → Edge `charge-tip` cria um PaymentIntent À PARTE depois de o pedido existir. Resultado: duas cobranças no extrato do cliente, no MB Way DOIS pedidos de aprovação seguidos, e a Stripe cobra os 25 cêntimos fixos duas vezes (paga a Bora).
- Novo — os dois caminhos que existem hoje (confirma no código):
  a) CARTÃO, fluxo "paga e depois cria" (Mode B de `create-payment-intent`, metadata draft_id): aceita `tip_cents` no `cart_input`, valida no servidor (0, ou entre 50 e `tip_max_cents`, e `tips_enabled`) e soma a gorjeta ao valor do PaymentIntent DEPOIS da cotação; a gorjeta fica no rascunho (`payment_drafts`). Quando o pagamento entra (`stripe-webhook` → `finalize-order-from-intent` → `create_order`), cria a linha em `tips`: target 'order', moment 'checkout', method 'card', status 'succeeded', paid_at, `stripe_payment_intent_id` = o do pedido (um PI só tem uma gorjeta; índice `tips_pi_unico`). Idempotente: se o finalize repetir, não duplica.
  b) MB WAY, o pedido nasce primeiro e `create-mbway-payment-intent` cobra `payment_buffer_total` com metadata order_id: a gorjeta fica registada ao criar o pedido (linha em `tips` 'pending', moment 'checkout', method 'mbway'), a função soma-a ao valor do MB Way e grava o PI na gorjeta; o `stripe-webhook` marca-a 'succeeded' quando o pedido fica pago e 'failed' se o MB Way falhar/expirar (sem a cobrar duas vezes nos novos pedidos MB Way do mesmo pedido). Vê também o modo antigo (Mode A, order_id + amount) e trata-o igual se ainda for usado.
  `quote_order_pricing` não muda: a gorjeta nunca entra em margens, buffers, comissões, taxa de serviço, tokens, nem no subtotal da loja. O prestador entra quando houver estafeta (confirma que o gatilho `fn_orders_gorjeta_acompanha` e o espelho `fn_tips_espelho_no_pedido` continuam certos).
- App: o carrinho manda a gorjeta no `cart_input` e deixa de chamar `charge-tip` no checkout por cartão/MB Way. O ecrã mostra a linha "Gorjeta" e o total a pagar JÁ com a gorjeta; o cliente aprova UM pagamento só.
- Dinheiro: fica como está (`tip_registar_dinheiro`, entregue em mão, conta para o limite de 40 €).
- Pedido pago todo com saldo/tokens (`no_card_charge_needed`, sem cartão nem MB Way): a gorjeta do carrinho continua à parte como hoje (charge-tip). Não inventar outro caminho.
- Compatível com apps antigas (quem não atualizou continua a chamar charge-tip depois do pedido): o servidor aceita os dois caminhos e nunca cobra a gorjeta duas vezes no mesmo pedido.
- Tudo o que compara o valor cobrado na Stripe com o total do pedido tem de contar com a gorjeta: `payments-reconciler` / `payment_reconciliation_findings`, `refund`, finalize do talão e dos Favores (`finalize_storeshopping_purchase*`, `finalize_errand_purchase`, `finalizar_talao_nao_parceiro`), `charge-extra`, `order-edit-settle`, reembolso de diferenças de peso. Diferenças da compra NUNCA mexem na gorjeta.
- Interruptor `platform_settings.tips_checkout_junto_pagamento` (true = gorjeta junto da compra; false = como antes). Visível e editável no painel admin. Começa true quando o servidor estiver no ar e provado; a app nova respeita-o.

BLOCO B — Gorjeta devolvida quando o pedido é cancelado
- Achado (Claude.ai 30/10): quando um pedido é cancelado ou rejeitado, só a gorjeta em DINHEIRO passa a 'cancelled' (`fn_orders_gorjeta_acompanha`). A gorjeta já paga por cartão/MB Way fica cobrada e ninguém a devolve: nenhuma função de cancelamento (client-cancel-order, cancel-order-with-choice, admin-cancel-order, auto-refund-order, execute-cancellation, refund) toca em `tips`. Se o pedido for cancelado antes de haver estafeta, a gorjeta fica com prestador 00000000-… e não vai para ninguém.
- Regra: pedido cancelado ou rejeitado antes da entrega → a gorjeta volta INTEIRA ao cliente, sempre, fora de qualquer taxa de cancelamento (a taxa de cancelamento só se aplica à compra). Volta pelo mesmo caminho e com a mesma escolha do cliente que o resto do reembolso (mesmo meio ou Carteira Bora, regra de 29/10). Gorjeta junto da compra: o reembolso inclui a gorjeta inteira. Gorjeta à parte (apps antigas / saldo-only): reembolso desse PaymentIntent (mesma lógica idempotente do refund do charge-tip). A linha em `tips` passa a 'refunded' com refunded_at e motivo.
- Dados antigos: hoje há 2 gorjetas no total e nenhuma neste caso — só confirmar por SELECT e reportar.

BLOCO C — A taxa da Stripe fica sempre gravada (agora conta dinheiro)
- `gravarEstado` (charge-tip) e `tipGravarEstado` (stripe-webhook) leem a taxa do balance_transaction, mas se falhar fica null ("taxa é informativa") e o filtro `.not('status','in','(succeeded,refunded)')` impede de a preencher depois.
- Consertar: (1) com a gorjeta já 'succeeded' e a taxa null, deixa gravar SÓ a taxa; (2) tarefa agendada ao domingo antes do fecho semanal (o fecho corre segunda 00:05 UTC, job 26) que vai buscar à Stripe as taxas que faltam e regista no e2e_log; (3) a estimativa da coluna gerada (25 cêntimos + 1,5%) só serve enquanto falta a taxa.

BLOCO D — O que o estafeta/motorista vê (app, PT-PT)
- `lib/widgets/gorjetas_recebidas_section.dart` lê `amount_cents` e soma o bruto. Passa a mostrar, por gorjeta paga depois (cartão/MB Way): "Gorjeta 2,00 € · taxa do pagamento −0,28 € · recebes 1,72 €"; gorjeta do carrinho ou em dinheiro: só o valor (inteira). Total = soma de `liquido_prestador_cents`.
- Extrato `_prestador_trabalhos`: a linha informativa "Gorjeta do cliente" usa `orders.tip_amount_cents` (bruto). Mostra o que ele recebe e a taxa quando houver. Confirma se as gorjetas das corridas TVDE aparecem no extrato do motorista; se não aparecem, acrescenta.
- "Ganhos de hoje", recibo semanal (`weekly-closeout-digest`, `settlement-receipt`) e qualquer outro sítio onde o prestador vê gorjetas: o que ele recebe (líquido) e a taxa. Procura TODOS os sítios em lib/ e nas funções do banco.

BLOCO E — Painel admin (PT-BR, termos técnicos explicados entre parênteses) — autoridade total
- `lib/screens/admin/admin_gorjetas_screen.dart` + `admin_listar_gorjetas`: colunas valor, taxa da Stripe, líquido para o prestador, quem pagou a taxa (prestador ou Bora), como foi paga (junto da compra / à parte no carrinho / depois / dinheiro), estado. Totais do período: gorjetas, taxas descontadas aos prestadores, taxas pagas pela Bora. Mudar `admin_listar_gorjetas` exige DROP + CREATE (muda o RETURNS TABLE): repõe as permissões exatamente como estavam (vê-as antes).
- `admin_tvde_acertos_tipo_tab.dart`: o rótulo das gorjetas passa a "Gorjetas (já sem a taxa da Stripe)".
- O interruptor do Bloco A e o reembolso de gorjeta pelo admin (para gorjeta junto da compra: reembolso parcial do PI do pedido no valor da gorjeta).

BLOCO F — Textos e regras escritas
- Carrinho: "A gorjeta vai toda para o estafeta." (tira "e é cobrada à parte" quando vai junto; no caso saldo-only mantém "é cobrada à parte"). Mesmo texto em `lib/l10n/strings_en.dart`.
- Ecrãs de avaliação (entrega `rating_screen.dart` e corrida `tvde_rate_screen.dart`): nada pode prometer "100%" ou "vai toda" para a gorjeta paga depois. Não acrescentar avisos novos ao cliente.
- Comentários que dizem "100% para o prestador" (tip_service.dart, charge-tip, gorjetas_recebidas_section, admin_gorjetas_screen, rating_screen, tvde_rate_screen, cart_screen, e em `compute_driver_settlement` a nota "gorjetas 100% prestador (04/10)") passam a dizer a regra de 30/10.
- `.claude/.ai/business_rules.md` §4.5 ainda diz "Divisão: 80% estafeta, 20% Bora" (de abril, nunca atualizado depois de 03/10): substitui pela regra de 30/10 (os 4 pontos de cima). Também `lib/config/business_rules.dart` e `supabase/functions/_shared/business_rules.ts` se falarem de gorjeta.

BLOCO G — Provas e juiz
- Testes: cálculo do líquido; valor do PaymentIntent = compra + gorjeta; finalize idempotente (não duplica a gorjeta); cancelamento devolve a gorjeta inteira fora da taxa; reconciliador sem falsos alarmes com gorjeta; texto do carrinho. `flutter analyze` limpo, `flutter test` verde, `python .claude/juiz/anti_trapaca.py`, `deno check` nas Edge Functions mexidas, rubrica UI.
- SEM cobranças reais. Simula o webhook como na ronda de 04/10 e/ou usa a Stripe em modo teste sem mudar o modo da produção (BORA_STRIPE_MODE fica live). Provas reais de dinheiro só a dinheiro.
- Provas no emulador (capturas): carrinho com gorjeta mostra o total já com a gorjeta e um pagamento só; secção de gorjetas do Danilo mostra 2,00 / −0,28 / 1,72 com a gorjeta de 29/10; painel admin com a taxa e o líquido.
- O lado do servidor (banco e Edge Functions) pode ir já para o ar se for compatível com as apps antigas: guarda a versão anterior de cada função antes do deploy e prova por SELECT/logs.

FECHO
- PUBLICAÇÃO: o Danilo publica as 3 plataformas uma vez por semana; urgente só com o "publica" dele. Envia o ramo para o servidor, junta isto ao que está pronto para a próxima publicação (fim de semana 31/10–01/11) e PÁRA à espera. Se eu (Claude.ai) colar aqui "publica", publicas nas 3 (Play Store, App Store/TestFlight, web), sem mexer no versionCode, e provas as 3 (Android, iPhone, web) com o carrinho, a secção de gorjetas e o painel.
- Regista: e2e_log (um passo por bloco), digest em claude_ai_memoria (`digest-2026-10-30-gorjetas-taxa`), este prompt no Obsidian (C:\Users\danil\Desktop\Bora) e na memória (data, sessão, scope, estado). Relatório final curto, em texto corrido: o que ficou feito, o que falta.

/ctx doctor
/ctx stats

