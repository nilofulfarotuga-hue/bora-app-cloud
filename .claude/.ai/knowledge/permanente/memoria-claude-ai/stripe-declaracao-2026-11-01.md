---
id: memoria-claude-ai-stripe-declaracao-2026-11-01
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-01
zona: verde
confianca: alta
estado: atual
---

# Stripe do Bora desde o início — extrato para o contabilista (01/11/2026)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `stripe-declaracao-2026-11-01`, origem `claude-ai`, atualizada em 2026-11-01T21:34:41.424403+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: stripe declaracao 2026 11 01 · memoria claude.ai · claude_ai_memoria

# Stripe do Bora desde o início — relatório para o contabilista (01/11/2026, Claude.ai)

Pedido do Danilo: resumo de tudo o que passou pela conta Stripe do Bora (acct_1T8MFaGlT3R2jCYp, live) desde o início, por mês e por tipo, porque nunca foi declarado. Regras dele: a Bora declara só comissões/taxas (a mercadoria das lojas não é receita); o TVDE de passageiros fica fora; os pagamentos do Jai Agarwal (139 €/mês e os de setembro) são serviços de site já faturados à parte.

## Como foi feito (fica a funcionar)
- Edge Function nova `stripe-relatorio-contabilista` (verify_jwt=true; dentro exige servidor ou admin, exigirServidorOuAdmin de _shared/chaves.ts). Lê balance_transactions da API da Stripe (fetch, 100 por página, expand source), classifica por metadata.kind / order_id / descrição / cliente, guarda em `public.stripe_extrato_contabilista` (RLS, só is_admin(); anon e authenticated sem acesso) e cruza com a base (RPC `stripe_extrato_cruzar_base`: orders, tvde_rides, tvde_subscriptions, cleaning_bookings, carwash_bookings, appointments, tips). Resumo: RPC `stripe_extrato_resumo(desde, ate)` → por mês, por mês e tipo, totais, linhas com nota.
- Executada a 01/11 20:18 pelo próprio banco (net.http_post com a chave sb_secret_backend do cofre, pedido 93024): 294 linhas (180 payment, 33 charge, 42 reembolsos, 22 payouts, 17 stripe_fee), 3 páginas, 20 cruzadas com a base. Repetir: `select net.http_post(url := project_url||'/functions/v1/stripe-relatorio-contabilista', headers := apikey+Bearer sb_secret_backend, body := '{"guardar":true}')`.
- 17 linhas com categoria fixada à mão (coluna categoria_manual, que a função nunca sobrescreve): Jai/Guarda FC → servicos_site; 186 e 291,53 de 27/10 → contas Jai/Vansh; 100 e 400 de agosto → link sem nome (a confirmar); sinais de reserva de maio → reservas.
- Ficheiros no repo: supabase/functions/stripe-relatorio-contabilista/index.ts; supabase/migrations/20261101201500_stripe_extrato_contabilista_2026_11_01.sql.

## Totais desde o início (bruto = cobrado aos clientes; tudo em euros)
- 2026-04: bruto 9,25 (1 cobrança), reembolsos 9,25, taxas 0,39 → líquido -0,39. Pedido de teste.
- 2026-05: bruto 33,69 (8), taxas 2,53 → líquido 31,16; payouts 28,07. Entregas 18,69 + sinais de reserva 15,00.
- 2026-06: bruto 28,00 (3), taxas 0,85 → 26,95; payouts 29,65. Outros 25,00 (sem identificação) + reserva 3,00.
- 2026-07: bruto 19,00 (4), taxas 0,98 → 17,82; payouts 4,63. Outros 13,00 + reservas 6,00.
- 2026-08: bruto 712,00 (14), taxas 20,44, reembolsos 15,00 → 675,96; payouts 537,33. Jai 139,00 (site) + 500,00 por link sem nome (100 a 04/08 e 400 a 10/08, provavelmente site do Guarda FC) + TVDE 41,00 + reserva 12,00 + 20,00 pequenos.
- 2026-09: bruto 2.922,31 (73), taxas 85,55, reembolsos 38,38 → 2.797,11; payouts 2.709,78. Serviços de site Jai/Guarda FC 2.439,00 (300 Ruchi Saha 02/09, 300 Jai 10/09, 200 Ruchi 11/09, 750 Espy Costa + 750 LeninV Godinho a 15/09, 139 Jai 30/09) + TVDE 304,88 (56 cobranças) + entregas 121,43 (7) + reserva 12,00 + 45,00 pequenos (25+10+10).
- 2026-10: bruto 1.327,87 (107), taxas 48,71, reembolsos 171,13 → 1.106,66; payouts 564,56. TVDE 486,30 (90 cobranças, 125,56 reembolsados) + contas Jai/Vansh 477,53 (186,00 + 291,53 a 27/10) + entregas/mercados 180,64 (10, 45,57 reembolsados) + Jai 139,00 + limpeza 32,40 + gorjeta 2,00 + 10,00 pequenos.
- 2026-11 (só dia 1): bruto 11,25 (3 TVDE), reembolsos 6,25; payout 561,04.
- TOTAL: bruto 5.063,37 · taxas Stripe 160,38 · reembolsos 240,01 · líquido 4.658,37 · transferido para o banco 4.435,06.

## Leitura para a declaração (regras do Danilo)
- Serviços de site (Jai/Guarda FC), faturados à parte na atividade individual: 2.717,00 (+500 de agosto a confirmar).
- TVDE de passageiros (fora da declaração da Bora): 843,43 bruto, 185,19 reembolsados.
- Entregas/mercados pela Stripe: 330,01 bruto (inclui mercadoria das lojas, que não é receita; a receita da Bora é a do fecho mensal).
- Limpeza 32,40; reservas 48,00 (sinais, quase tudo teste); gorjetas 2,00; contas Jai/Vansh 477,53 (mistura corridas, compras e recados); pequenos sem identificação 113,00.
- O que a Bora declara por mês vem do admin_monthly_closeout (receita própria), não do bruto da Stripe.

## Cuidados
- O cruzamento com a base só apanha 20 cobranças (os pedidos antigos não guardavam payment_intent_id; o TVDE grava-o). 43 cobranças ficaram sem cruzamento mas classificadas pela metadata.
- A conta Stripe nova da empresa começa do zero (regra de 24/10); este extrato é só da conta pessoal.

## Correções de 01/11 à noite (autorização do Danilo: "ver tudinho para o mês que vem não dar erro")
- Aplicadas em produção: _fecho_limites corrigida (31/10 entrava em nenhum mês); admin_monthly_closeout com TVDE fora, limpeza dentro e IVA conforme a entidade; driver_monthly_invoice_summary com o adquirente certo (individual até out/2026, sociedade desde nov/2026); RPC fecho_mensal_prestadores; tabelas fecho_mensal_contabilista_log e cleaner_monthly_statement_log; cron 125 'fecho-mensal-contabilista' (07 e 08 UTC do dia 1; a função age às 08h de Lisboa; 1.º disparo 01/12/2026); Edge Function fecho-mensal-contabilista publicada; fecho_contabilista_ativo=true. Sem email do Hugo (fecho_contabilista_email vazio) o fecho automático vai só ao Danilo com "FALTA EMAIL DO CONTABILISTA" no assunto.
- Outubro certo: receita própria 159,95 (entregas 130,34 + limpeza 29,61); Mayra 167,79; Danilo 87,56 (17 entregas); Valdemir 16,08.
- Por fazer: publicar monthly-partner-statement v3 (classificador travou a publicação por MCP) e depois reenviar o fecho de outubro com force:true (SQL na página fecho-outubro-2026).

## CORREÇÃO 01/11 21:30 (Claude.ai) — os 2.717 € NÃO eram todos do site
Revisto com o livro (recibo-jogador-gfc, guarda-fc) e as conversas de 14/09, 20/09 e 22/09: os 2×750 € de 15/09 (Espy Costa, LeninV Godinho) foram dinheiro do Jai para a conta das corridas — pagaram a conta A 447,15 € + conta B 40 €, e os outros 974,85 € foram devolvidos ao Jai e ao Vansh pelo Revolut da Letícia a 22/09 (fora da Stripe). Os 200 € de 11/09 (Ruchi Saha) abateram na conta das corridas (conta corrigida de 14/09: "pagamento recebido −200"). Os 500 € de agosto (100 a 04/08, 400 a 10/08) não batem com o site (a 24/08 o site tinha 650 € pagos, nenhum por esta Stripe) — provável avença de 100 €/semana do transporte do Jai, por confirmar com o Danilo. categoria_manual/nota_manual atualizadas nas 5 linhas.
Totais certos (SELECT 01/11 21:30): sites e mensalidade do Jai 1.017 € (300 Ruchi 02/09 + 300 Jai 10/09 + 3×139); contas Jai/Vansh 2.177,53 € (200 + 750 + 750 + 186 + 291,53; 974,85 devolvidos fora da Stripe → ficou 1.202,68); TVDE 843,43 € (156 cobranças, 185,19 devolvidos); Bora 412,41 € (entregas/mercados 330,01 com 54,82 devolvidos, limpeza 32,40, reservas 48, gorjeta 2); por identificar 613 € (500 de agosto + 12 pequenos = 113). Total 5.063,37; taxas 160,38 + 4,61 outras = 164,99; reembolsos 240,01; banco 4.435,06; fica na Stripe 223,31.
Faturas: a do site ao clube ficou preparada a 17-18/09 e não emitida; a da mensalidade o Jai pediu-a a 31/10 — não dizer ao Hugo que já está faturado.
