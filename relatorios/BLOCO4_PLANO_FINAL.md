# Bloco 4 — Cancelamento Uber · Plano final para aprovação (2026-06-29)

## Descoberta que muda a arquitetura
O cancelamento REAL do cliente **não** passa pela RPC `request_order_cancel` (essa é
órfã — zero chamadas em Flutter e na DB; reposta ao original). O motor real é a
**Edge Function LIVE `client-cancel-order` (v24)** que já faz tiers automáticos e
**reembolsa cartão de volta ao cartão via Stripe**. Por isso o trabalho do Bloco 4
vive na Edge Function, não na RPC.

## Estado nesta sessão
- ✅ Aplicado (seguro, inerte até deploy): settings `cancel_grace_seconds=180` e
  `cancel_fee_after_accept_driver_cents=150` (editáveis no admin) + colunas de
  auditoria em `cancellation_requests`.
- ✅ DB reposta ao estado anterior: `request_order_cancel` voltou ao original;
  helper temporário removido.
- 📄 **Proposta (NÃO deployed):** `BLOCO4_client-cancel-order_PROPOSTA.ts` (v25).
- 📄 **Helper a aplicar no deploy:** `BLOCO4_helper_wallet_refund_full.sql`.
- ⏸️ Flutter/admin: **não tocados** de propósito — mostrar contador "grátis" antes de
  a Edge honrar a graça cobraria o cliente. Vão juntos no deploy (spec abaixo).

## As 3 decisões do Danilo (na proposta)
- **D1** graça 180s grátis **só enquanto não há estafeta** (`assigned_driver_id IS NULL`).
- **D2** taxa pós-aceite 2,50€ = **1,50€ estafeta + 1,00€ Bora** (ledger_entries).
- **D3** favor após `is_purchase_finalized=true` → **bloqueia** (entrega segue).
- **Q1** reembolso à **escolha do cliente**: `card` (Stripe→cartão ~5 dias) ou
  `wallet` (imediato; E1=100% livre, E2/E3=80% saldo + 20% tokens).

## Matemática ao cêntimo (exemplo total = 12,00€, pago a cartão)
| Estágio | Condição | Taxa | Reembolso | card | wallet | Estafeta | Bora |
|---|---|---|---|---|---|---|---|
| **E1 grace** | sem estafeta + ≤180s | 0,00 | 12,00 | Stripe 12,00 | 12,00 livre | — | 0 |
| **E2 before** | sem estafeta + >180s | 1,00 | 11,00 | Stripe 11,00 | 8,80 livre + 2,20 tokens | — | 1,00 |
| **E3 after_accept** | estafeta aceitou, pré-pickup | 2,50 | 9,50 | Stripe 9,50 | 7,60 livre + 1,90 tokens | +1,50 | +1,00 |
| **E4 after_pickup** | após pickup | 12,00 (100%) | 0,00 | — | — | ganho normal | resto |
| **E_FAVOR** | favor já comprado | — | **bloqueado** | — | — | finaliza entrega | — |

Cash (teste): `paid_cents=0` → nada a devolver; taxa vira dívida via
`wallet_debit_cancel_fee` (E2/E3); E1 grátis = só cancela. D2 ledger só quando a
taxa foi mesmo cobrada.

Conferência Bora E3 (ambos os destinos): Bora retém 2,50 → paga 1,50 ao estafeta →
fica com **1,00€** líquido. ✓ (no destino wallet, Bora retém os 12,00 Stripe, gera
9,50 de saldo + 1,50 estafeta = 11,00, líquido **1,00€**). ✓

## Spec Flutter (PT-PT) — aplicar no mesmo deploy
- Botão "Cancelar pedido" em `order_tracking_screen` / `order_details_screen`.
- **E1**: contador "Podes cancelar grátis durante MM:SS" (decresce de 180s; some quando
  estafeta aceita OU tempo esgota).
- **E2/E3**: diálogo "Cancelar agora tem uma taxa de X €. Continuar?" + **escolha do
  reembolso** (cartão ~5 dias úteis / wallet imediato 80%+20% tokens).
- **E4**: aviso forte "O teu pedido já está em entrega — cancelar não tem reembolso."
- **E_FAVOR**: bloqueado "A compra já foi feita; o estafeta vai concluir a entrega."
- `clientCancelOrder` passa a enviar `refund_target: 'card'|'wallet'`.

## Spec Admin (PT-BR) — aplicar no mesmo deploy
- Editar settings: `cancel_grace_seconds`, `cancel_fee_before_dispatch_cents`,
  `cancel_fee_after_accept_cents`, `cancel_fee_after_accept_driver_cents`,
  `cancel_fee_after_pickup_ratio` (tela admin de settings).
- Histórico de cancelamentos: estágio, taxa, reembolso, destino, estafeta creditado.
- Fila `cancellation_requests` (disputas + cancelamentos de estafeta/parceiro) com
  decidir/override — JÁ existe (`admin_pending_actions` / `AdminCancelOrderDialog`).

## Checklist de deploy (quando aprovares)
1. `psql` / MCP: aplicar `BLOCO4_helper_wallet_refund_full.sql`.
2. Copiar a proposta para `supabase/functions/client-cancel-order/index.ts` e
   `supabase functions deploy client-cancel-order` (verify_jwt=true).
3. Aplicar Flutter + admin (spec acima) e push → CI build.
4. Teste E2E (cash) dos 5 estágios no device.
