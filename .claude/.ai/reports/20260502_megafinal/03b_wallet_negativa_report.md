# Sessão 3B-NOVA — Wallet com Saldo Negativo (Fase B: Execução)

**Data:** 2026-05-04
**Branch:** autonomous-night-2026-04-29
**Status:** ✅ DEPLOYADO PROD + flutter analyze 0 novos errors
**Estratégia:** substitui plano Stripe off_session (abandonado).

---

## ✅ FEITO

### Backend (5 migrations aplicadas em prod)

| Migration | Bloco plano | Conteúdo |
|---|---|---|
| `20260504020000_wallet_negative_schema_and_settings.sql` | B1+B2 | DROP CHECK `>=0` → ADD `>=-2000`. ALTER `wallet_transactions` ADD `balance_after_cents`+`idempotency_key UNIQUE`. CHECK kind expandido. 6 settings novos. |
| `20260504030000_wallet_apply_adjustment_rpc.sql` | B3 | RPC nova `wallet_apply_post_delivery_adjustment` (idempotência via `adj_<order>_<kind>`, cap €10, hard floor defensivo). MOD `wallet_debit_for_order` (permite negativo). MOD `wallet_credit_refund_split` (abate dívida primeiro). |
| `20260504040000_finalize_uses_wallet_adjustment.sql` | B4 | `finalize_storeshopping_purchase` em card/mbway extra → chama B3 em vez de `extraRequired`. Kill-switch consciente. Cash mantém `cash_total_due`. Refund branch intacto. |
| `20260504050000_create_order_wallet_negative.sql` | B5 | Gate `WALLET_BLOCKED` se `balance < soft cap`. Settlement automático se `balance < 0`. Kill-switch consciente. NÃO TOCA pricing/menu_credit/INSERT. |
| `20260504060000_admin_forgive_and_overdue_cron.sql` | B11+B12 | RPC `admin_forgive_wallet_debt`. pg_cron `wallet_overdue_alerts` 09:00 UTC (90d alerta / 180d acção). |

### UI Flutter

| Ficheiro | Bloco | Mudança |
|---|---|---|
| `lib/services/wallet_service.dart` | helpers | `WalletConstants` (espelho settings). `WalletBalance.isNegative/isBlocked/isWarning/debtCents`. `WalletTx.balanceAfterCents` + novos kindLabels. `WalletService.adminForgiveDebt`. |
| `lib/screens/profile_screen.dart` | B6 | `_WalletCardsBlock` adapta cor (verde/amarelo/vermelho) + banner bloqueio. |
| `lib/screens/cart_screen.dart` | B7 | `_settlementCents()`. Linha "Saldo devedor anterior". Bloqueio botão "Finalizar pedido" + banner aviso. |
| `lib/screens/wallet_history_screen.dart` | B8 | Card vermelho/bloqueado se negativo. Ícones distintos por kind (settlement, forgive, debit, etc.). Linha "Saldo após:" via `balance_after_cents`. |
| `lib/screens/orders_screen.dart` | B9 | Preload `wallet_get_balance` last_transactions → mapa `orderId→txs`. Chip "Carteira" no card + modal detalhes. |
| `lib/screens/admin/admin_wallets_screen.dart` | B10 | Toggle "Apenas saldo negativo". Sort negativos primeiro. Coluna saldo vermelha. Acção "Perdoar dívida" (com motivo). Botão CSV export wallets negativas. |

### Smokes RPC validados (DO blocks via MCP service-role)

| Smoke | Resultado | Detalhe |
|---|---|---|
| **S-CHECK** | ✅ OK_rejected | `UPDATE free_balance_cents=-2001` rejeitado pelo CHECK |
| **S7** | ✅ OK_raised | `wallet_apply` 1500 cents → `amount_exceeds_cap: requested=1500 cap=1000` |
| **S8** | ✅ OK_raised | `wallet_debit_for_order` 2001 cents → `wallet_hard_floor_exceeded: have=0 need=2001 floor=-2000` |
| **S1** | ✅ OK | wallet=0, debit 30 cents → balance=-30, `crossed_zero=true` |
| **S-IDEM** | ✅ OK | replay mesma chamada → `idempotent_replay=true`, balance ainda -30 |
| **S3** | ✅ OK | wallet=-950 + `create_order` sendPackage → `wallet_settlement_cents=950`, wallet→0, charge_total=€15.50 |
| **S4** | ✅ OK | wallet=-1100 + `create_order` → `WALLET_BLOCKED: saldo €-11.00, regularize antes de novos pedidos` |
| **Kill-switch** | ✅ OK | `wallet_negative_enabled=false` + wallet=-500 + `create_order` → `wallet_balance_pre_cents=null`, `wallet_settlement_cents=0`, wallet manteve -500 (intacto) |

### Documentação

| Ficheiro | Conteúdo |
|---|---|
| `business_rules.md` §28 | Política completa: limites, casos de uso, ordem operações, refund, push (TODO), Uber/Glovo ref, boas práticas, admin, regime fiscal Art. 53.º. |
| `.claude/.ai/todos/sessao_3b_pending.md` | TODO push templates (B13 diferido), Stripe off_session ABANDONADO, pending_charges decisão futura, regime IVA normal, refund parcial wallet, performance last_order_at. |

---

## ❌ DEFERIDO / NÃO IMPLEMENTADO

### B13 — Push templates server-side
Bloqueio: Sessão 1B push (Firebase keys server-side) ainda não validada em prod. Templates desejados documentados em `business_rules.md §28.7` e `sessao_3b_pending.md`. Pontos de invocação preparados: `wallet_apply_post_delivery_adjustment` retorna `crossed_zero` flag; `create_order` retorna `wallet_settlement_cents`. Bastará adicionar `pg_net.http_post` quando bloqueio levantar.

In-app feedback (sem push) já está completo em todas as telas relevantes (B6-B10).

---

## 🐛 BUGS COLATERAIS DESCOBERTOS

### Memória CLAUDE auto desactualizada
- "5 pending non-partner restaurants" → real é 0 (todos aprovados, BUG 6 closed).
- "7 reservation RPCs prod" → real são 6 (`admin_reservations_metrics`, `admin_reservations_today`, `auto_close_no_show_reservations`, `client_cancel_reservation`, `client_confirm_reservation_payment`, `partner_decide_reservation`). Sétimo provavelmente foi removido em sessão anterior; não bloqueia.

### Sessão 3 (mantidos sem regredir)
- `confirm-mbway-payment` Edge Fn obsoleta — apagar pós teste prod.
- `create-mbway-payment-intent-debug` — apagar.
- `final_total` (double) vs `customer_total` (numeric) — uniformizar tipo.
- `extra_charge_amount` não nullify após charge bem-sucedido.

---

## 📊 NÃO REGREDIU

- ✅ BUG 1: 0 coords NULL pós 2026-05-03 (manteve)
- ✅ BUG 6: 10 non-partner approved (manteve)
- ✅ Reservation RPCs prod (6) (manteve)
- ✅ `cash_total_due` column existe (manteve)
- ✅ `pending_charges` table inactiva (manteve)
- ✅ Cap 5 sacos em finalize (manteve, smoke S3 confirmou)
- ✅ Cash flow Sessão 3 não regrediu (cash extra continua via `cash_total_due`)
- ✅ flutter analyze: 52 issues, **0 novos errors** (= baseline)

---

## 🔧 KILL-SWITCH

```sql
UPDATE platform_settings SET value='false'::jsonb
  WHERE key='wallet_negative_enabled';
```

Efeito imediato:
- `create_order` salta gate + settlement → comportamento bit-exact Sessões 1+2+3
- `finalize_storeshopping_purchase` em card/mbway extra cai em `extraRequired` (Sessão 3)
- Wallets já negativas continuam visíveis ao admin (perdoar manualmente via `admin_forgive_wallet_debt`)

✅ Validado por smoke "Kill-switch" — wallet=-500 inalterada após `create_order`.

---

## 📦 COMMITS

A criar (1 commit por bloco/migration):
1. `feat(db): wallet permite negativo até -€20 (Sessão 3B B1+B2)`
2. `feat(db): wallet_apply_post_delivery_adjustment RPC + ajustes (B3)`
3. `feat(db): finalize debita wallet em vez de extraRequired (B4)`
4. `feat(db): create_order gate + settlement (B5)`
5. `feat(db): admin_forgive_wallet_debt + cron 90d/180d (B11+B12)`
6. `feat(ui): wallet UI cliente — perfil + cart + history + orders (B6-B9)`
7. `feat(ui): admin wallets filtro negativo + perdoar + CSV (B10)`
8. `docs: business_rules.md §28 + sessao_3b_pending.md (Sessão 3B)`

---

## 🎯 PRÓXIMO PASSO

Aguardar validação Danilo. Se OK, fazer commits (1 atómico por item) e fechar Sessão 3B.

Para testar end-to-end em ambiente real:
1. Login como cliente
2. Criar pedido `storeShopping` card; estafeta finaliza com 3 sacos
3. Verificar wallet → -€0.30
4. Voltar a pedir → ver linha "Saldo devedor anterior: +€0.30" no checkout
5. Confirmar pedido → `charge_total` = original + €0.30, wallet → 0
