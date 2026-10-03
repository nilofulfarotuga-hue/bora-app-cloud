---
tema: zonas-protegidas · escopo: projeto · estado: atual · atualizado: 2026-07-01
id: zonas-protegidas
tipo: conceito
origem: [.claude/HOOKS.md]
ultima_confirmacao: 2026-07-08
zona: vermelha
confianca: auto
---

# 🔴 Zonas Protegidas — a Trava (Fase 1)

> Fonte completa: `.claude/HOOKS.md`. Isto é o resumo para os agentes saberem o que **NÃO**
> podem tocar. A Trava (hooks `PreToolUse` + `permissions.deny`) **bloqueia de verdade**
> (exit 2 / deny) — nem `--dangerously-skip-permissions` fura. Desativar = só o Danilo à mão.

## Ficheiros de código bloqueados (Edit/Write/MultiEdit)
- `lib/services/pricing_service.dart` — cálculo de preços/taxas.
- `lib/stores/order_store.dart` — contém `finalizePurchase*`. ⚠️ ficheiro inteiro bloqueado
  (realtime/dispatch/status também vivem lá; o Danilo pode relaxar à mão se travar trabalho).
- `lib/widgets/errand_execution_sheet.dart` — `_finalizePurchase`.
- `supabase/functions/{dispatch-engine, stripe-webhook, finalize-order-from-intent,
  create-payment-intent, create-mbway-payment-intent, refund, reprocess-refund, charge-extra}/**`.
- **A própria Trava:** `.claude/hooks/**`, `.claude/settings.json`, `.claude/settings.local.json`.

## Banco de dados bloqueado
- **DDL** (CREATE OR REPLACE / DROP / ALTER) sobre funções/triggers de dinheiro
  (`pricing_*`, `create_order`, `*settlement*`, `*payout*`, `refund*`, `wallet_*`, `*token*`,
  `enforce_financial_immutability`, `finalize_*`, `_enforce_refund_cap`, …).
- **DROP/TRUNCATE** e **DISABLE ROW LEVEL SECURITY** em tabelas financeiras
  (`orders`, `wallets`, `ledger(_entries)`, `bora_tokens`, `wallet_transactions`,
  `*_balances`, `order_financials`, `*_weekly_settlements`, `appointment_payouts`, …).
- **deploy** das edge functions protegidas · **`supabase db reset`**.

## Git destrutivo bloqueado
`git push --force` / `-f` / `--force-with-lease` · `git reset --hard`. (Push normal PASSA.)

## Comportamento do agente
Se a tarefa exigir tocar aqui → **PARA e reporta** (não brigues com a Trava). Trabalho de
preparação pode-se fazer; a alteração de dinheiro só entra com "vai" do Danilo (🔴 Lista Vermelha).
