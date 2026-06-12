# Bloqueadores Pré-Launch Resolvidos — 2026-06-12

> Origem: AUDITORIA_GERAL_PRE_LAUNCH_2026-06-12.md. Sessão única, commit por
> bloco. Este ficheiro é o resumo para o knowledge/Obsidian.
> **Danilo: correr o sync manual para o vault Obsidian (C:\Users\danil\Desktop\Bora)**
> — script já existe no repo: `.claude/scripts/sync-obsidian-knowledge.ps1 -VaultPath "C:\Users\danil\Desktop\Bora"`.

## O que foi corrigido (e como)

### B1 — Cap de distância de entrega ✅
- **Problema:** `create_order` aceitava qualquer distância (pedido real: 9.125 km → entrega €4.563).
- **Fix:** validação server-side no `create_order` — lê `platform_settings.delivery_max_distance_km` (15; fallback 15), `RAISE delivery_distance_exceeded` acima disso; takeaway isento. Flutter: `OrderStore.lastCreateOrderError` + mensagem PT-PT "Entrega não disponível. Máximo 15 km." no checkout.
- **Prova em prod:** 16 km → recusado; 14 km → passa o gate (cai na validação seguinte, zero escritas).
- Migration: `20260612213000_b1_delivery_distance_cap.sql` · commit `afdbad1`.

### B3a — Cap 50% de pagamento com tokens ✅
- **Problema:** regra §4.3 (máx 50% do pedido em tokens) só existia no UI, com 0.50 hardcoded; o servidor nunca validava.
- **Fix:** cliente envia `token_discount_cents` no `p_input`; `create_order` lê `token_payment_max_pct` (50) e `RAISE token_cap_exceeded` acima do cap; valor registado em `orders.tokens_applied_value_cents` (entra no cap de refund). UI lê o pct da DB via `get_setting` (fallback 50) e mostra "Máximo 50% em Bora Tokens (€X,XX)". Charge/buffer NÃO alterados (desconto continua aplicado localmente no buffer — gap conhecido documentado no relatório).
- **Prova em prod:** pedido €15,30 + 800c de tokens → recusado (cap 765c).
- Migration: `20260612214500_b3a_token_payment_cap.sql` · commit `b342513`.

### B3b — Cap SEMANAL de saque de tokens do estafeta ✅ (bug confirmado)
- **Problema:** conversão tokens→€ era 100% client-side (`consume_tokens` + inserts manuais) com cap de 50% POR CHAMADA → 50%+50%+50%… esvaziava o saldo na mesma semana.
- **Fix:** nova RPC atómica `driver_convert_tokens(p_amount)` (SECURITY DEFINER, GRANT authenticated): semana civil seg 00:00→dom (`date_trunc('week')`); fórmula spec Danilo `já_sacado_semana + novo > saldo_atual × pct` → `RAISE token_withdrawal_weekly_cap_exceeded`; lê `token_withdrawal_max_pct_weekly` (50) e `token_value_cents_x100` da DB; consome + regista `driver_transactions` (type=`token_conversion`, lido pelo `compute_driver_settlement`) + credita `driver_balances` numa transação. Flutter (`driver_earnings_screen`) chama só a RPC; mensagem "Limite semanal atingido. Podes sacar mais na próxima semana."
- **Prova em prod (driver real 503a2e09, txn abortada):** `already=1142 new=1 cap=9 balance=19` → recusado.
- Migration: `20260612220000_b3b_driver_token_withdrawal_weekly_cap.sql` · commit `54997ed`.

### B4 — Estafeta vê preços BASE na lista de compras ✅
- **Problema:** lista de compras (storeShopping) mostrava preços com +15% (`_markupPctDisplay = 0.15` hardcoded fora do PricingService) — mas o estafeta paga preço de prateleira na caixa.
- **Fix:** itens canónicos mostram `basePrice ?? price` (pré-B1 o price já era base); extras mostram o preço digitado sem ×1,15; "Subtotal comprado"/"Adicionados"/"Total na caixa" (ex "Total ajustado") e "Bora reembolsa-te" em base. Dinheiro do CLIENTE intacto: cobrança em dinheiro e diff vs buffer calculados à parte com `BRBusiness.NON_PARTNER_MARKUP_RATIO` (hardcode eliminado). `create_order`/ganhos intocados.
- Commit `55d3a5b`.

### B6 — Alergénios (Reg. UE 1169/2011) ✅
- **Problema:** zero informação de alergénios (obrigação legal UE).
- **Fix:** coluna `products.allergens TEXT[]` + índice GIN (aplicado em prod); `lib/config/allergens.dart` (14 slugs→labels PT-PT); modelo `PartnerProduct.allergens`; form do parceiro (`add_product_screen`) com FilterChips dos 14; detalhe do produto (cliente) mostra chips ou o disclaimer "Consulte o estabelecimento para informações sobre alergénios." Informativo — nunca bloqueia pedidos.
- Migration: `20260612221500_b6_products_allergens.sql` · commit `a0394ee`.

### B5 — Paginação lazy do catálogo (45k produtos) ✅
- **Problema:** arranque carregava ~45k produtos (45 requests sequenciais) para RAM; ecrãs de mercado filtravam tudo em memória.
- **Fix:** arranque carrega APENAS parceiros + restaurantes não-parceiros (menus completos, pequenos) via `inFilter`; mercados/lojas/farmácia carregam por páginas de 30 (`loadMoreStoreProducts`) para o MESMO `_productsByRestaurant` — `partnerProductsForRestaurant` continua a ser a API de leitura, zero mudanças de modelo nos ecrãs. `MarketStoreScreen` garante 120 iniciais (hero/secções); `StoreProductsScreen` tem infinite scroll (NotificationListener, +30 perto do fim) + spinner no 1º load. Pesquisa continua 100% na DB (RPC `search_products`, já existia). Add-to-cart/preços intocados.
- Commit (ver git log B5).

### Stacking (contexto)
`partner_driver_stacking_bonus_cents=300` já estava correto na DB — **não tocado** (instrução explícita).

## Adenda (mesma data) — Verificação T1+T2: JÁ ESTAVAM FEITOS

Prompt posterior pediu T1 (toppings não cobrados) + T2 (ecrã Minhas Marcações) com diagnóstico DESATUALIZADO — ambos implementados em 2026-06-11. Verificação de hoje (zero edits):
- **T1 ✅** provado vivo: `order_line_options_extras` açaí+Mel+Banana → **€2,00**; KFC 2 grupos → 3,72; display cliente (order_details:1001) + estafeta (driver_map:2789) + parceiro (partner_dashboard:1345) via `selected_options_priced`.
- **T2 ✅**: `client/services/my_appointments_screen.dart` (3 tabs Próximas/Passadas/Canceladas, sinal PT-PT, modal com regra antes de cancelar), atalhos Serviços+Perfil, crons `appt-reminders-24h`(10h)/`appt-reminders-2h`(*/30)/no-show/payout ativos, admin OK.
- **⚠️ Decisão pendente Danilo:** prompt pedia janela **2h** p/ marcações; implementado = **24h** (`appointment_cancel_window_hours=24`, splits €0,50/€2,50) **alinhado com o DNA** — 2h é a regra de reservas de MESA. Não toquei (dinheiro). Detalhe: `relatorios/VERIFICACAO_T1_T2_JA_IMPLEMENTADOS_2026-06-12.md`.

## Pendente / follow-ups
1. **Gap conhecido (pré-existente, não tocado):** desconto de tokens é subtraído ao buffer só localmente; `create-payment-intent` valida ±5% contra o buffer da DB → cartão+tokens com desconto >5% pode falhar. Decisão futura: subtrair `tokens_applied_value_cents` ao buffer server-side (zona Stripe — precisa aprovação Danilo).
2. **B5 limitação v1:** chips de categoria e tab "Categorias" do mercado derivam dos produtos JÁ carregados (parciais até o utilizador paginar). Follow-up sugerido: RPC `store_product_categories(restaurant_id)` (distinct + count) para chips completos + paginação por categoria.
3. `loadVariantsFromSupabase` continua unbounded (pequeno hoje; Zippy variantes).
4. UI do estafeta não mostra "quanto ainda posso sacar esta semana" (a RPC devolve `weekly_cap_tokens`/`week_converted_tokens_before` — fácil de expor).
5. Testar no dispositivo (A36): checkout >15 km, toggle tokens, conversão tokens estafeta, lista de compras em base, mercado Continente (arranque + scroll), alergénios no form parceiro e detalhe cliente.
