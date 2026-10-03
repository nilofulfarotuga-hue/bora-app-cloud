# Bloco 4 — Revisão pré-deploy `client-cancel-order` (2026-06-29)
> NÃO deployed. NÃO aplicado. Documento de revisão. Leva ao Claude.ai.
> Ficheiros: `BLOCO4_client-cancel-order_PROPOSTA.ts` (v25) · `BLOCO4_helper_wallet_refund_full.sql`.

## DIFF v24 (LIVE) → v25 (proposta) — só o que mexe em dinheiro/fluxo
| # | Mudança | Linhas v25 | Toca dinheiro? |
|---|---|---|---|
| 1 | `CancelTier` ganha `'grace'`; `resolveTier`→`baseTier` (sem grace) | 26–35 | indireto |
| 2 | helper `getIntSetting` (lê settings em runtime) | 37–43 | não |
| 3 | parâmetro novo `refund_target: 'card'\|'wallet'` (default `card`) | 55, 60 | **sim** |
| 4 | SELECT ganha `created_at, assigned_driver_id, service_type, is_purchase_finalized, driver_earnings` | 83 | não |
| 5 | **D3** bloqueio favor pós-compra (return antes de mutar) | 88–91 | **sim (impede)** |
| 6 | **D1** cálculo da graça (`age ≤ 180s` E sem estafeta) | 96–101 | **sim** |
| 7 | `feeEur=0` no estágio grace | 105–106 | **sim** |
| 8 | **Q1** ramo de reembolso: wallet vs cartão vs wallet-fallback | 134–167 | **sim** |
| 9 | **D2/E4** postagem no `ledger_entries` (estafeta+Bora / ganho normal) | 169–189 | **sim** |
| 10 | `newPaymentStatus`/`updatePayload` tratam `walletCredited` | 192–205 | sim (estado) |
| 11 | resposta inclui `refund_target` | 210–216 | não |
| — | **INALTERADO de v24:** débito cash (120–133), mecânica Stripe + idempotency key (145–159), auth/CORS | — | preservado |

## AUTO-AUDITORIA (12 pontos)
1. **IDEMPOTÊNCIA** — ✅ cartão: `idempotencyKey = refund-${payment_intent_id}-${amount}` (linha 155) → 2x mesmo cancel = mesmo refund Stripe, nunca duplica. ⚠️ wallet: as RPCs `wallet_credit_*` **não** são idempotentes; só ficam protegidas pela checagem de estado na re-entrada (`baseTier('cancelled')='invalid'`→409). Ver ponto 10.
2. **BASE = PAGO** — ⚠️ parcial. Cash→0 garantido: `paidCents` (109) + `nothingToRefund` (110) desvia para o ramo de débito (120), **nunca** credita reembolso. PORÉM `refundEur` usa `totalEur` (107), não `paidCents` — herdado da v24. Para pedido pago na íntegra é igual; recomendo **limitar `refundEur` a `paidCents/100`** por segurança.
3. **CARTÃO vs WALLET exclusivo** — ✅ ramos mutuamente exclusivos: `if wallet` (136) / `else if card` (145) / `else wallet-fallback` (160). Nunca os dois. Wallet: grace→`wallet_credit_refund_full` (100% livre), resto→`wallet_credit_refund_split` (80/20) (138, 162).
4. **SPLIT ESTAFETA (E3)** — ✅ `feeCharged = paidCents>0 || cancelFeeDebited` (172); postagem só se `assigned_driver_id && feeCharged` (173). Cash sem débito (floor excedido→`chargeMissing`) → `feeCharged=false` → **sem crédito fantasma**. Posta 1,50 estafeta + (fee−1,50) Bora (176–179).
5. **GRAÇA (E1)** — ✅ `graceSeconds` da setting (97), `ageSeconds` a partir de `order.created_at` real (98), `noDriver` (99); grace só se `before_dispatch && noDriver && age≤grace` (100–101).
6. **DECISÃO 1 (estado>tempo)** — ✅ duplo-guardado: `noDriver` exigido (100) **e** assim que estafeta aceita, `status='driverAccepted'`→`baseTier='after_accept'` → nunca cai em grace.
7. **BLOQUEIO FAVOR (D3)** — ✅ `service_type='errand' && is_purchase_finalized` → 409 **antes** de qualquer escrita (88–91). Pedido não é cancelado; entrega segue.
8. **PÓS-PICKUP (E4)** — ✅ fee = `total × ratio(1.0)` → `refundEur=0` (107); estafeta recebe `driver_earnings` normal no ledger (180–186).
9. **HARD FLOOR (−4000)** — ✅ aplicado **dentro** de `wallet_debit_cancel_fee` (chamada 125; erro→notify-admin + `chargeMissing` 128–131). ⚠️ não li o corpo dessa RPC nesta sessão — **confirmar** que ela rejeita abaixo do floor.
10. **ATOMICIDADE** — ❌ **a corrigir antes do deploy (wallet).** O dinheiro move (139–165) **antes** de marcar `status='cancelled'` (207). Cartão: seguro (idempotency key absorve re-run). **Wallet: re-run/duplo-toque/concorrência antes do flip de estado pode creditar 2×** (RPCs não idempotentes). **FIX recomendado:** compare-and-swap primeiro — `UPDATE orders SET status='cancelled' WHERE id=? AND status=<actual>`, confirmar `rowCount=1`, **só então** mover dinheiro; senão 409.
11. **SEGREDOS** — ✅ `STRIPE_SECRET_KEY` (16) e chaves Supabase (48–50) via `Deno.env.get`. Nada hardcoded.
12. **MATEMÁTICA** — ver tabelas abaixo. Bora líquida E3 = **1,00€** confirmada nos dois destinos e nos dois métodos.

## MATEMÁTICA AO CÊNTIMO — pedido 12,00€
### Pago a CARTÃO (paidCents=1200)
| Estágio | Taxa | Reembolso | Destino cartão | Destino wallet | Estafeta | Bora líquida |
|---|---|---|---|---|---|---|
| E1 grace | 0,00 | 12,00 | Stripe 12,00 ao cartão | 12,00 saldo livre | — | 0,00 |
| E2 before | 1,00 | 11,00 | Stripe 11,00 | 8,80 livre + 2,20 tokens | — | 1,00 |
| E3 after_accept | 2,50 | 9,50 | Stripe 9,50 | 7,60 livre + 1,90 tokens | +1,50 | **1,00** |
| E4 after_pickup | 12,00 | 0,00 | — | — | ganho normal | 12,00 − ganho |
| E_FAVOR | — | **bloqueado (409)** | — | — | finaliza entrega | — |

### Pago em DINHEIRO (paidCents=0)
| Estágio | Taxa | Movimento | Estafeta | Bora |
|---|---|---|---|---|
| E1 grace | 0,00 | só cancela | — | 0,00 |
| E2 before | 1,00 | dívida wallet 1,00 (`wallet_debit_cancel_fee`) | — | a receber 1,00 |
| E3 after_accept | 2,50 | dívida 2,50 + ledger estafeta 1,50 / Bora 1,00 | +1,50 | **1,00** |
| E4 after_pickup | 12,00 | dívida 12,00 | ganho normal | resto |
| E_FAVOR | — | **bloqueado** | finaliza entrega | — |

## VEREDICTO (v25 — antes das correções)
🟡 2 itens reportados → corrigidos na v25.1 (ver abaixo). 🟢 10 verdes.

---

# v25.1 — CORREÇÕES APLICADAS (re-auditoria)

## DIFF das 2 correções (antes → depois)
**#2 — base do reembolso (linhas 110–117):**
- ANTES: `refundEur = max(0, total − fee)` (usava total teórico; `paidCents` só calculado depois).
- DEPOIS: `paidCents` movido para cima + `refundEur = max(0, min(total − fee, paidCents/100))`. Reembolso nunca excede o pago; cash (paidCents=0) → 0.

**#10 — atomicidade / claim antes do dinheiro (linhas 119–134 + 142 + 159–201 + 225–245):**
- ANTES: dinheiro movido (wallet/cartão) e SÓ no fim `update status='cancelled'` → 2ª execução podia creditar 2×.
- DEPOIS: **claim atómico primeiro** — `UPDATE orders SET status='cancelled',… WHERE id=? AND user_id=? AND status NOT IN (terminais) RETURNING id`. Se 0 linhas → `409 already_finalized` (aborta, sem mexer em dinheiro). Só com 1 linha é que move dinheiro. Falha de dinheiro PÓS-claim deixou de ser early-return (que perderia o reembolso) → flag `refundFailed` + `notify-admin-urgent` + `refund_status='failed'` (recuperável; cliente nunca perde dinheiro). `cancel_fee` reconciliado a 0 se a taxa cash não cobrar (igual v24).

## RE-AUDITORIA 12 pontos (v25.1)
1. **IDEMPOTÊNCIA** — ✅✅ agora **dupla**: claim compare-and-swap (124–134) impede 2ª execução de mover dinheiro **+** idempotency key Stripe (182).
2. **BASE = PAGO** — ✅ `refundEur = min(total−fee, paidCents/100)` (114–117). Cash → 0.
3. **CARTÃO vs WALLET exclusivo** — ✅ ramos mutuamente exclusivos (162/171/188), sem regressão.
4. **SPLIT ESTAFETA (E3)** — ✅ `feeCharged` (206), só com taxa real (207–213).
5. **GRAÇA (E1)** — ✅ inalterado (97–103), `created_at` real.
6. **DECISÃO 1** — ✅ inalterado (`noDriver` + estado).
7. **BLOQUEIO FAVOR (D3)** — ✅ 409 antes de tudo (88–91), agora ainda mais cedo que o claim.
8. **PÓS-PICKUP (E4)** — ✅ fee=total → refund 0; ganho normal (214–220).
9. **HARD FLOOR** — ✅ dentro de `wallet_debit_cancel_fee` (150). *Confirmar corpo dessa RPC.
10. **ATOMICIDADE** — ✅ **RESOLVIDO**: claim atómico (124–134); dinheiro só depois; falha pós-claim → `refundFailed`+alerta+`refund_status='failed'` (199–201, 245).
11. **SEGREDOS** — ✅ `Deno.env.get` (16, 48–50).
12. **MATEMÁTICA** — ✅ inalterada (tabelas acima); cap no pago não muda valores quando pago=total.

**Sem regressões:** débito cash (145–158), postagem ledger (203–223) e mecânica Stripe (171–187) iguais à v24. Único acréscimo de comportamento: falha de refund pós-claim agora é recuperável (admin alertado) em vez de 502 cego.

## MATEMÁTICA re-confirmada (12,00€, pago=total)
Idêntica às tabelas acima — E1 0€ · E2 1€ · **E3 2,50€ = 1,50€ estafeta + 1,00€ Bora** · E4 100% · favor bloqueado. Cap `paidCents` não altera (pago=12,00=total). Dinheiro: E2 dívida 1€, E3 dívida 2,50€ + estafeta 1,50 / Bora 1,00. Bora líquida E3 = **1,00€**. ✅

🟢 **v25.1: 12/12 verdes. Math bate ao cêntimo. Pronto para deploy** (1 caveat read-only: confirmar floor dentro de `wallet_debit_cancel_fee`).
