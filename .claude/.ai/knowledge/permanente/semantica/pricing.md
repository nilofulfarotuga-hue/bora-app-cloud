---
tema: pricing · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# 💶 Pricing / Tokens / Comissões — resumo operacional

> Resumo de LEITURA. A verdade final está em `.claude/.ai/business_rules.md` e no código
> 🔴 protegido (`pricing_service.dart`, RPCs `pricing_*`). Não recalcular à mão nos ecrãs.

## Entrega — `estado: atual`
- Base: **€2,50 até 4 km** + **€0,50/km** acima.
- Markup: **15% não-parceiro** / **10+5+5% parceiro**.
- Cash: **máximo €40** por pedido (trigger `enforce_cash_payment_limit`).
- Sacos: restaurante **€0,30** fixo · mercado **€0,10/unidade**.

## Comissão parceiro 10+5+5 — `estado: atual` (Batch D)
- **10%** `partner_commission_visible` (parceiro paga no settlement).
- **5%** `partner_markup_hidden` (embutido no preço; cliente não vê).
- **5%** `partner_service_fee_client` / `service_fee` (visível no recibo do cliente).

## Estafeta — `estado: atual`
- **€3,80 + €0,20/km** · bónus **€0,80** (storeShopping/carry/send) · **+€3** stacked parceiro.
- Partilha **30%** do lucro líquido Bora (não-parceiro).

## Tokens — `estado: atual`
- Driver **+40** normal / **+50 = entrega de loja parceira** (não é stacking). Cliente
  **3 tokens por €** — `GREATEST(1, ROUND(valor×3))`.
- **100 tokens = €0,50** · máx **50%** de desconto. DB `bora_tokens`, trigger `trg_award_tokens_on_delivery`.
- **Só o delivery atribui tokens hoje** — TVDE, marcações e Limpeza NÃO (Limpeza tem proposta
  pendente: `supabase/PROPOSTA_20260706_cleaning_tokens.sql`, ver `semantica/vertical-limpeza.md`).
- ✅ **Contradição resolvida (2026-07-06, commit `4d34a2a`):** `business_rules.md` §4.2 corrigido —
  a regra certa é "3 tokens por €" (o código, `ROUND(price×3)`). — Facto anterior "cliente ganha
  3% do valor": **estado: superado (por correção do §4.2, 2026-07-06)**.

## Onde o dinheiro é forçado no servidor
Ledger append-only + `enforce_financial_immutability` (orders_financial_lock) + `_enforce_refund_cap`.
Editar qualquer um disto = 🔴 bloqueado pela Trava (ver `zonas-protegidas.md`).
