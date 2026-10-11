# ANEXO — Para onde vai o dinheiro hoje quando se cancela sem profissional (lido a 10/10/2026)

> Só leitura: `get_edge_function` (versões no ar), `pg_get_functiondef`, `pg_trigger`, SELECT. Linhas = ficheiro/definição no ar.
> ✔ = segue a regra nova · ✗ = viola · ~ = parcial

## Entregas, Favores, mercados (tabela `orders`: restaurant 21, storeShopping 21, errand 11, sendPackage 1 nos últimos 120 dias)

**Cancelado pelo sistema** (`dispatch_cancel_expired_order` L15 põe `cancellation_initiator='system'`)
→ gatilho `trg_reembolso_cancelado_pelo_sistema` (BEFORE UPDATE OF status) → `fn_reembolso_cancelado_pelo_sistema`
(só card/mbway, `payment_status='paid'`, `refund_status` vazio) → `refund_status='pending_auto'` + `net.http_post` →
**`auto-refund-order` v2**: `requires_capture` → `paymentIntents.cancel` (L49-52); `succeeded` → `refunds.create` do total (L54, chave `auto-refund-${pi}`). ✔
Prova: 947f7206 (Solaidy, McDonald's, 18,68 € MB Way, 07/10) → `refund_status='refunded'`, `refund_id` preenchido.
Falhas (~): `coalesce(stripe_charge_cents/100,…)` dá 0 quando a coluna está a 0 e não reembolsa; tokens devolvidos por janela de tempo (pode apanhar outro pedido); a parte paga com saldo não volta; ninguém avisa o cliente; se falhar fica `failed` e o `reprocess-refund` manda o MB Way para a carteira.

**Cancelado pelo cliente**
- `cancel-order-with-choice` v18 (ecrã de detalhes → `refund_choice_dialog.dart`, que **força 'wallet' para MB Way**: L61, L73-76, L135) → L215 `wallet_credit_refund_split` 80 % saldo + 20 % tokens. ✗ **Caso Divan d383a09e.**
- `client-cancel-order` v29 (ecrã de seguimento, `refund_target='card'` por defeito; e `payment_method_screen.dart` L971 depois de um pagamento falhado, `reason='payment_failed'`) → Stripe para cartão e MB Way (L174-191) ✔. `'wallet'` ou parte carteira fora da graça → split ✗. Até 05/10 contava os tokens do pedido como "pagos" mesmo quando o pagamento falhou e eles nunca foram gastos → saldo fantasma (dcc8c509 5,51 €; 6c102c39 0,24 €). Desde 05/10 ignora tokens com `tokens_applied_count=0` — e essa coluna está a 0 em todos os pedidos → quem cancela perde os tokens gastos ✗. Sem `paymentIntents.cancel` ✗. Sem aviso ao cliente.

**Cancelado pelo admin**
- `admin-cancel-order` v14 → 100 % Stripe ✔; parte carteira/tokens → split 80/20 (L231-233) ✗; sem `paymentIntents.cancel`.
- `execute-cancellation` v15 (aprovar pedido de cancelamento) → o admin escolhe; ecrã com `'wallet'` por defeito (`admin_cancellation_requests_screen.dart:44`) → split (L165/168) ✗.
- `reprocess-refund` v3 → **L54** `refund_method==='wallet' || payment_method!=='card'` → MB Way vai para a carteira ✗.

**Taxa sem estafeta**: 0 € hoje (`cancel_fee_before_dispatch_cents=0`) ✔, mas `_shared/platform_settings.ts` L22 usa 1,50 € se a leitura falhar ✗.
**Aviso "reembolso confirmado"**: não existe. `stripe-webhook` v36 L917-923 só faz `console.log` em `charge.refunded`; `refund.*` cai no `default`. `refund_status='pending'` nunca passa a `refunded` ✗.

## TVDE (corridas e reservas)
`tvde_cancel_ride` (taxa só com motorista, L75-88) → gatilho `tr_tvde_ride_auto_refund_on_cancel` → `tvde_ride_auto_refund` → `tvde-payment` `auto_refund_ride` → Stripe (pago − taxa). ✔
Prova (30 dias): 18 corridas MB Way canceladas, todas `payment_status='refunded'` (16 pelo cliente, 2 sem motorista), taxa 0.
Reservas: `tvde_cancel_reservation` / `admin_tvde_reservation_cancel` → `tvde_reservation_auto_refund` → Stripe ✔ (a taxa tardia não verifica se há motorista; hoje é 0).
~ Cartão só autorizado: o gatilho só age em `succeeded` (POR CONFIRMAR se o `tvde-payment` cancela a autorização noutro sítio — tem `paymentIntents.cancel` em L495/511/1120).

## Limpeza
`cancel_cleaning_booking` só muda o rótulo (L49 'held'→'estornado'); o dinheiro mexe-se na app (`cleaning_store.dart:420` → `cleaning-checkout` 'reverse': cancela a autorização, ou captura só a taxa, ou reembolsa — L289-331). Sem carteira ✔.
✗ Taxa de 50–100 % a menos de 24 h **mesmo sem profissional** (L39-41).
✗ `admin_cancel_cleaning`: põe 'estornado' sem chamar a Stripe (reembolso fantasma).
✗ `cancel_cleaning_series`: não toca no dinheiro.

## Lavagem
`cancel_carwash_booking`: taxa só com lavador (L29) ✔; estorno pela app (`carwash-checkout` 'reverse'). ✗ `admin_cancel_carwash_booking`: sem Stripe.

## Marcações (barbearias/salões)
`client_cancel_appointment` ≥ 24 h → `net.http_post /refund` (Stripe) ✔, mas grava 'refunded' antes de a Stripe responder (L60) ✗. `partner_cancel_appointment` 100 % Stripe ✔. ✗ `admin_cancel_appointment_on_behalf_of`: 'refunded' sem Stripe.

## Reservas de mesa
`client_cancel_reservation` ≥ 2 h → `/refund` ✔ (mesmo falso positivo assíncrono). ✗ `admin_cancel_reservation_on_behalf_of`: grava 'cancelled_refunded' e manda "Reembolso em 5–10 dias" sem Stripe (o ecrã salta a Edge `admin-cancel-reservation`, que é a que faz `refunds.create`).

Nos últimos 30 dias **nenhuma** limpeza, lavagem, marcação ou reserva paga foi cancelada → nada em jogo agora nessas; é risco para o próximo caso.
