---
id: memoria-claude-ai-livro-areas-limite-pagamento-dinheiro
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Limite de €40 em pagamento a dinheiro no [[bora-app]] — onde vive mesmo (4 sítios hardcoded) e prompt entregue para o tornar configurável por cliente

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-areas-limite-pagamento-dinheiro`, origem `claude-ai`, atualizada em 2026-10-23T05:42:41.697519+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro areas limite pagamento dinheiro · memoria claude.ai · claude_ai_memoria

> Cópia da memória da Claude.ai (ficheiro /areas/limite-pagamento-dinheiro.md), copiada a 23/10/2026. A fonte da verdade é a memória da Claude.ai — não editar aqui; correções vão para a página erros-aprendidos.

---
name: limite-pagamento-dinheiro
description: Limite de €40 em pagamento a dinheiro no [[bora-app]] — onde vive mesmo (4 sítios hardcoded) e prompt entregue para o tornar configurável por cliente
sources: [chat]
aliases: [limite de dinheiro, max_cash_amount_cents, cash limit, pagar em dinheiro]
---

- [stated] 01/09: o Danilo quis fechar um pedido de 46,18€ em dinheiro na conta dele e a opção "Dinheiro" aparecia apagada; pediu para libertar o limite.
- ⚠️ ARMADILHA PROVADA (custou várias tentativas ao vivo): mexer em `platform_settings.max_cash_amount_cents` NÃO faz nada. Foi subido para 10000 duas vezes, com fecho total da app e limpeza de cache, e o botão continuou apagado. O valor no banco é decorativo.
- O limite dos €40 está ESCRITO À MÃO em 4 sítios (confirmados por leitura do repo público e por `pg_get_functiondef`):
  1. `lib/screens/payment_method_screen.dart:326-327` — `cashBlockedByLimit = !cartStore.isTakeaway && totalCashWithDebt > 40.0`; é este que apaga o botão no ecrã de pagamento
  2. `lib/screens/errand_form_screen.dart:105` — `static const _maxCashCents = 4000` (usado na l.480, fluxo Favores)
  3. Trigger `public.enforce_cash_payment_limit()` em `orders` — `IF v_total > 40 THEN RAISE EXCEPTION 'CASH_LIMIT_EXCEEDED...'`
  4. `supabase/functions/_shared/business_rules.ts:68` — `CASH_MAX_ORDER_VALUE_EUR = 40.00`
- ⚠️ MENTIRA DOCUMENTAL a corrigir: o comentário por cima do ponto 4 diz "Source of truth: platform_settings.max_cash_amount_cents" — é falso, e foi o que me levou a perder tempo a mexer no banco.
- ⚠️ DIVERGÊNCIA repo↔produção no trigger: a migration `20260409000000_driver_balance_cash_system.sql` diz 30, a função em produção diz 40. A verdade é a produção.
- Logo, subir o limite exige BUILD NOVO — e o CI publica direto para produção a 100% (ver [[play-store-release]]).
- [stated] PROMPT REGISTADO: `PROMPT_limite_dinheiro_por_cliente_2026-09-01.md`, entregue 01/09, MOTOR OPUS (janela Pro do Claude Code), sessão `limite-dinheiro-por-cliente`. Scope: coluna `client_wallets.cash_limit_override_cents` (NULL = usa o global, número = limite deste cliente), conta do Danilo sem limite na prática e todas as outras contas iguais a hoje; passar os 4 sítios a ler override do cliente → global → constante; campo no painel admin; prova nos dois casos (conta dele passa acima de €40, outra conta continua bloqueada). Estado: entregue como ficheiro; nada disparado
- Contorno enquanto isso: manter o pedido abaixo de €40 ou dividir em dois pedidos.

