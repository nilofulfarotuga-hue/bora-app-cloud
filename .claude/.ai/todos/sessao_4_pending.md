# Sessão 4/7 — TODOs Adiados (criado 2026-05-04)

## C3 commit 2 — final_total RENAME (ORDEM OBRIGATÓRIA)

**Aplicar ≥24h após smoke prod do commit 1.** A ordem é crítica — qualquer desvio quebra a tabela.

```sql
-- 1. Drop trigger PRIMEIRO (deixa de sincronizar)
DROP TRIGGER trg_zz_final_total_dual_write ON public.orders;
-- 2. Drop função
DROP FUNCTION public.fn_sync_final_total_numeric();
-- 3. Drop coluna double precision (não pode haver callers a ler — verificar)
ALTER TABLE public.orders DROP COLUMN final_total;
-- 4. Rename: numeric → final_total
ALTER TABLE public.orders RENAME COLUMN final_total_numeric TO final_total;
```

**Pré-condições para commit 2:**
- Smoke prod ≥ 24h sem incidentes em pedidos novos
- 24 callsites de A3 podem precisar de actualização (a maioria continua a ler `final_total` que vai virar numeric — compatível)
- Re-correr `flutter analyze` após RENAME — verificar se há código que assume tipo `double` específico

---

## B5 completo — Sessão 4C dedicada

⚠️ **Asserts B5 actuais SÃO STRIP em release mode — produção continua VULNERÁVEL.** Mitigação só detector dev.

Trabalho pendente:
- Mapear 107 call sites `CartItem(...)` em `lib/`
- Identificar caminhos onde `productId` chega null/empty (legacy fontes, deeplink, search, reorder)
- Fix transversal cliente / estafeta / parceiro / admin
- Smoke + regressão completa
- **Limpeza retroactiva** `orders.items`: UPDATE via lookup `name → SKU` em `products` (alto risco — exige BEGIN/dry-run e backup)
- Considerar: server-side reject de `product_id` que tenha espaço ou >200 chars (defesa em profundidade)
- Investigar correlação 11/30 orders pós-recentes `payment_status='failed'` com `productId=name`
- Investigar caso edge `E2E2daa86` (productId NULL completo)

---

## Sessão 4B — Push notifications geo-aware (ainda pendente)

- 500m do destino: push "O seu pedido está a chegar, vá à porta receber"
- 200m do destino: push "Pedido chegou"
- Excepção: entrega no apartamento (paga extra) → estafeta sobe; sem push 200m
- Infra parcial existe (`notify-client` Edge Fn + `driver_locations_realtime` + `fcm_token` + `push_broadcasts`)
- Falta: Firebase keys prod + trigger geo-aware + textos educados

---

## Sessão 5 — Botão Suporte (FAB)

- 3 opções: chatbot IA, WhatsApp +351937501673, email boraappbora@gmail.com
- Painel admin tickets

---

## Wallet split 80/20 promocional

- `wallet_split_free_pct` setting já presente em `platform_settings`
- Implementação refunds (split free vs promotional) — sessão futura

---

## Anti-fraud — `distance_km` validation (Sessão dedicada)

- `quote_order_pricing` e `create_order` confiam no `distance_km` do payload
- Cliente malicioso pode reduzir `delivery_fee` enviando distance fabricada
- Fix: validar server-side recalculando via `earthdistance` ou PostGIS a partir de `pickup_lat/lng → dropoff_lat/lng`
- RAISE se Δ > tolerância (ex.: 0.3 km)

---

## B3 cash settlement path (diferido)

- `apply_driver_cash_settlement` faz settlement Driver↔Bora (cash adjustment), NÃO `extra_charge` settlement
- Path cash em `finalize_storeshopping_purchase` set `v_extra_charge_cents := 0` → `extra_charge_amount` nunca > 0 em cash
- `cash_total_due` é sistema paralelo (cash extra a cobrar pelo estafeta na entrega)
- Settlement marker `extra_charge_settled_via='cash'` requer arquitectura unificada (sessão futura)
- Decisão: aceitável diferir porque arquitectura actual não cria extra_charge_amount em cash flows

---

## Housekeeping financeiro futuro

- `orders.extra_charge_amount` — `double precision` (mesmo padrão C3); aplicar `_numeric` mirror + dual-write + commit faseado
- Auditar TODAS as colunas monetárias em todas as tabelas (`drivers`, `restaurants`, `wallet_*`, `tokens_*`, `orders`) — confirmar `numeric` em todas

---

## BUG 34 architectural — Sessão 7

- `orders.id` TEXT (legacy) → migrar para UUID
- Plan já existe em `decisions/2026-04-29-restaurants-id-uuid-refactor.md`

---

## S21 colateral — `promotional_balance_cents` CHECK constraint

- Validação A0+S21 não encontrou CHECK em `client_wallets.promotional_balance_cents`
- Sessão 3B-NOVA terá deferido para sessão futura
- Verificar se é intencional (apenas `free_balance_cents >= -2000` faz sentido — promotional não pode ser negativo logo CHECK não é obrigatório)
- Confirmar com Danilo

---

## /ctx-upgrade

Não executado nesta sessão (briefing era opcional). v1.0.89 → v1.0.107 disponível. Aplicar antes de Sessão 5 ou em maintenance window.

---

## Smokes operacionais diferidos para prod

Os seguintes smokes requerem app run em devices reais e não foram executados via MCP nesta sessão:
- S7 — `quote_order_pricing` paridade (requer `auth.uid()` válido)
- S14 — CASH 2 sacos → cash_total_due += €0.20
- S15 — CARD wallet=0, 3 sacos → wallet=−€0.30
- S16 — CARD wallet=−€5 settlement aplica → wallet=0
- S17 — CARD wallet=−€11 → BLOQUEIA WALLET_BLOCKED
- S18 — CARD wallet=−€5 sem acknowledged_settlement
- S22 — BUG 35 banner cash (visual)
- S23 — BUG 38 linha verde driver_map (visual)

Smoke prod em Guarda com 1 cliente real + 1 estafeta validará todos.
