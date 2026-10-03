# 03 — REGRAS DE NEGÓCIO (DINHEIRO)

> A fonte canónica é `business_rules.md` no vault Obsidian (`C:\Users\danil\Desktop\Bora`). Este capítulo é o espelho consolidado. Divergência entre este ficheiro e o vault → o vault ganha; reportar a divergência.

## Parceiro vs Não-Parceiro (A distinção mais importante do app)

| | PARCEIRO | NÃO-PARCEIRO |
|---|---|---|
| Aplica-se a | **Só restaurantes** | Restaurantes sem acordo + **TODOS os mercados** |
| Comissão | 10% visível + 5% markup oculto nos produtos + 5% taxa serviço cliente | Preço base + 15% fixo (incluído no preço) |
| Fee cliente | — | €2,50 fixo |
| Estafeta | €3,80 + €0,20/km | €3,80 + €0,20/km + €0,80 + 30% do lucro líquido Bora |

Mercados não-parceiros: Continente, Lidl, Auchan, Pingo Doce, Mercadona, Intermarché. **Confundir as duas colunas = erro grave.**

## Valores gerais

- Entrega: €2,50 até 4 km, +€0,50/km acima.
- Cash: máximo €40 por pedido.
- Sacos: restaurante €0,30 fixo; mercado €0,10/saco.
- Tokens cliente: `ROUND(preço × 3)`, mínimo 1. Tokens estafeta: +40 normal, +50 pedido parceiro. (Tokens de fidelidade do estafeta ≠ tokens de wallet do cliente — nunca misturar.)
- Buffer MB Way: `payment_buffer_total = fees_total + round(estimativa × 1.2)` — **NUNCA ×1.15**.
- Payout a motoristas/estafetas é **SEMANAL** (acerto de contas), nunca reembolso instantâneo. Saldo negativo = Bora deve ao motorista.

## Wallet — split de reembolso

Cancelamento com refund pra wallet → **80% saldo livre** (sem restrição) + **20% tokens** (expiram em 60 dias). Percentagens em `platform_settings`. Cliente escolhe entre refund Stripe ou wallet.

## Cancelamento de pedidos (motor em 5 estágios — EF `client-cancel-order` v26)

| Estágio | Condição | Custo ao cliente |
|---|---|---|
| E1 | ≤180s, sem estafeta | Grátis |
| E2 | >180s, sem estafeta | €1 |
| E3 | Estafeta já aceitou | €2,50 (com split) |
| E4 | Pós-pickup | 100% |
| E5 | Pós-finalize (errands) | Bloqueado |

RPC `request_order_cancel` é ÓRFÃ — ignorar. Admin: histórico, reprocessar refund, editar taxas via `admin_update_cancel_setting`.

## Reservas — pré-pagamento

€3 fixo do cliente (`prepayment_cents=300`). Chegou: parceiro desconta €2 (`partner_payout_cents=200`), Bora retém €1 (`bora_service_cents=100`). No-show: Bora 100%. Cancela >2h antes: reembolso total. Cancela <2h (`cancel_window_hours=2`): Bora 100%.

## TVDE — preços e regras

- Parada adicional: **€2/parada, máx 2**, com countdown. Corrida cash → parada não paga nada na hora, motorista recolhe TUDO no fim (ex.: €8 pacote + €2 = €10 em mão). Corrida cartão/MB Way → cliente paga os €2 NA HORA e a parada só entra quando o pagamento confirma (auto-refund se falhar depois de pago).
- Cancelamento: grátis ≤3 min, 100% depois.
- No-show: €3,50 fixo pro motorista (RPC `tvde_mark_noshow` ainda por criar).
- **Ida-e-volta €8**: preço TOTAL do cliente pelas duas pernas (cash OU cartão/MB Way). NÃO é dinheiro do motorista: ida ganha €4 (se cash, recolhe os €8 por conta da Bora — o app avisa isso claramente); volta é GRÁTIS pro cliente, 2º motorista chamado automático, ganha €3,50; Bora fica ~€0,50. Tudo acertado no fecho semanal. Vale expira em 6h, sem auto-refund. Detecção €8-cash: crédito roundtrip SEM `payment_intent_id`.
- Plano assinatura Seg–Sex: €40/€70/€132 por 10/20/44 corridas. Corrida coberta pelo plano: motorista ganha a parte dele via acerto semanal.
- Pagamento antes do dispatch: corrida cartão/MB Way nasce `aguarda_pagamento` (cron ignora) e só vira despachável quando o pagamento confirma; recusa/timeout = auto-cancel (`payment_timeout` no cron, `payment_failed` no decline do Flutter).
- Acesso à categoria TVDE: gate por pessoa em `users.tvde_access`. **Estado atual: ABERTO pra todos** (default true, temporário). Receita de revert no cap. 04.

## Limpeza

Preços fixos T0–T4+, split **85/15**, materiais +€3, recorrência –10%, agendado (lead time mínimo removido). KYC + dupla avaliação.

## Favores (Errands) v3

Normal €6, Expresso €10. Gate de consentimento acima do orçamento; OCR de talão (Gemini); autocomplete de negócios (`guarda_businesses`); auto-catálogo "Lojas de Favores".

## Crawlers / rebuilds de catálogo

Crawlers Glovo/Uber **NÃO capturam** categorias promocionais/sazonais (ofertas da semana, destaques, operação-biquíni...). Só categorias estáveis/estruturais. Vale pra todos os rebuilds.
