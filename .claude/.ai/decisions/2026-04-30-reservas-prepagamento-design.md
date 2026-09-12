# Reservas pré-pagamento €3 — Design

> 2026-04-30 · Decisão final Danilo · Implementação ACTIVA

## Política (BR §18)

### Pré-pagamento
- **€3 fixo** por reserva (configurável: `platform_settings.reservation_prepayment_cents`)
- Cobrado no momento de pedir reserva via Stripe (cartão ou MBWay)
- Restaurante **NÃO paga nada** — feature gratuita para parceiros

### Estados possíveis e fluxo de dinheiro

| Evento | Status | Dinheiro |
|---|---|---|
| Cliente cria reserva + paga €3 | `pending_payment` → `pending` | €3 ringfenced no Stripe |
| Parceiro **aprova** | `approved` | Continua ringfenced |
| Parceiro **rejeita** | `rejected_refunded` | **Stripe refund total** (não foi culpa cliente) |
| Cliente **cancela** ≥2h antes | `cancelled_refunded` | **Stripe refund total** (5–10 dias) |
| Cliente **cancela** <2h antes | `cancelled_no_refund` | **Bora fica com €3** |
| Cliente **chega** (parceiro confirma) | `arrived` | **€3 vira `restaurant_menu_credits`** (desconto próximo pedido cliente naquele restaurante) |
| Cliente **falta** (>30min após reserved_for, sem chegar) | `no_show` | **Bora fica com €3** |

### Janela de cancelamento
- Configurável: `platform_settings.reservation_cancel_window_hours = 2`
- Comparação: `reserved_for - NOW() > cancel_window_hours`

### Crédito menu
- Tabela `restaurant_menu_credits`
- Aplica auto no próximo `create_order` do cliente naquele `restaurant_id`
- Expira em **30 dias** desde `arrived_at`
- Não cumulável (1 reserva = 1 crédito; usar antes de criar nova)

## Comparação com indústria

- **OpenTable**: cobra deposit em alguns restaurantes (€20–€100 típico), refund flexível
- **Glovo**: não tem reservations
- **Ricardo Reserva PT**: deposit de €5–€10 com regra similar
- **Bora**: €3 baixo + crédito ao chegar = incentivo positivo (não punitivo)

## Por que €3 e não €5
- Danilo: barreira psicológica baixa para clientes pouco habituados a deposit
- 2 cafés ≈ €3 → "se chego, recupero. se falto, paguei o lugar a outra pessoa"

## Trade-offs aceites

1. **Stripe minimum charge €0.50**: €3 é folgado.
2. **Refund delay 5–10 dias** para Stripe: comunicar claramente no cancel dialog.
3. **Cron no-show 1h tick**: se cliente chega 31min depois de reserved_for, sistema pode marcar no-show prematuro. Mitigação: cron só marca após 60min, dá margem segura.
4. **Restaurante não compensa Bora pelos no-shows**: assumido como custo de aquisição do parceiro (free feature → mais reservas).
