---
tema: business-rules · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# 📐 Regras de Negócio — ponteiro

> A **verdade dos números** vive no ficheiro canónico (192 KB): `.claude/.ai/business_rules.md`.
> **Nunca** o leias inteiro (rebenta o context window) — lê **por secção**. Este ficheiro é
> só o mapa das secções. O resumo operacional dos números está em `pricing.md` (irmão).

## Secções canónicas (ler a que precisas)
- **§ Pricing / entrega / markup** — €2,50 até 4km + €0,50/km; 15% não-parceiro / 10+5+5% parceiro.
- **§ Tokens & loyalty** — 100 tokens = €0,50; cap 50% desconto; cliente 3%; driver +40/+50.
- **§ Comissão parceiro 10+5+5** — visible/hidden/service_fee (colunas dedicadas).
- **§ Dispatch** — stacking até 3; FIFO ≤200m; timeout 40s; `current_driver_offer_id` = verdade.
- **§ Cancelamento & refund** — cap por escalão; Edge Function `client-cancel-order` é a atual.
- **§ Cash** — máximo €40 por pedido.
- **§ Sacos** — restaurante €0,30 fixo; mercado €0,10/unidade.
- **§ Wallet 80/20 + cashback + referral + promos** — ver também `business-rules/wallet.md`.
- **§ Favores/errand, Serviços/agendamentos, Reservas Pro, TVDE** — regras por vertical.
- **§ Scraping de mercados** (§27) — preço puro do site oficial; nunca markup na DB.

## Invariante
Estes números são 🔴 **zona protegida** quando viram código/DB (ver `zonas-protegidas.md`).
Aqui documentamos; **não** se altera valor cobrado/pago sem o Danilo dizer "vai".
