# Categorias + Reservas Pré-Pagamento · 2026-04-30

> Branch: `autonomous-night-2026-04-29` · Modo autónomo total
> Project: `ojykpzwqrtusfeakzrna` (LIVE)
> Stripe LIVE — `create-reservation-payment-intent` v2 deployed

## TAREFA 1 — Category mapping 281→23

### Antes
- 39202 produtos · 7640 sem `taxonomy_section` (~19%)
- 281 distinct `category_root`
- 23 secções canónicas

### Depois
- **39199/39202 produtos mapeados** (99.99%) — 3 são produtos sem `category_root`
- 281 mappings em `category_mapping` (todos com confidence 0.30–0.80, prontos para revisão admin)
- Trigger `trg_products_auto_taxonomy` activo: novos produtos auto-mapeados; novos roots inserem mapping automaticamente

### Distribuição taxonomy_section após backfill
| Secção | Roots mapeados |
|---|---|
| Outros | 86 (electrónica/papelaria/brinquedos — sem secção alimentar) |
| Higiene do Lar | 17 |
| Vinhos & Espirituosas | 16 |
| Bebidas | 16 |
| Mercearia | 16 |
| Higiene Pessoal | 13 |
| Snacks | 12 · Talho 12 |
| Laticínios & Ovos | 11 · Padaria & Pastelaria 11 · Frutas & Legumes 11 |
| Peixaria | 10 |
| (restantes 12) | 1–9 cada |

### Smoke tests
| # | Cenário | Verdict |
|---|---|---|
| 1 | 99.99% produtos com taxonomy_section | ✅ |
| 2 | Trigger preenche taxonomy_section em INSERT | ✅ |
| 3 | Trigger cria mapping novo para root desconhecido | ✅ |

### Admin (REGRA PAINEL)
- ✅ `admin_list_category_mappings(filter, search, limit)` RPC
- ✅ `admin_update_category_mapping(root, section, mark_reviewed, notes)` com audit log
- ✅ `admin_category_mapping_stats()` para card stats
- ✅ `AdminCategoryMappingScreen` com filtros (todos/por rever/confidence baixa) + search + edit dropdown + CSV
- ✅ NavCard "Mapeamento de categorias" no admin_dashboard

### Bugs corrigidos durante implementação
- v1 da função `auto_map_category` tinha false positives: `cat`→moscatel, `cha`→charcutaria, `rum`→arrumação, `ração`→decoração. **Fix v2**: word boundaries `\m...\M` em PostgreSQL regex.
- `INITCAP(text_with_html_entities)` quebrava entities (`Beb&eacute;` → `Beb&Eacute;`). **Fix**: CASE/WHEN map para forma canónica oficial.

## TAREFA 2 — Reservas Pré-Pagamento €3 (BR §18)

### Política implementada (decisões/2026-04-30-reservas-prepagamento-design.md)
- €3 fixo (`platform_settings.reservation_prepayment_cents`)
- Cancel ≥2h antes → Stripe refund total
- Cancel <2h antes → Bora 100%
- Cliente chega → €3 vira menu credit (próximo pedido nesse restaurante, expiry 30d)
- Cliente falta (>60min) → no_show, Bora 100%
- Partner rejeita → Stripe refund automático
- Partner não paga nada (feature gratuita)

### Edge Functions deployed
| Edge Fn | Versão | Status |
|---|---|---|
| `create-reservation-payment-intent` | **v2** | ACTIVE (verify_jwt=true) |

Cria reservation `pending_payment` + Stripe PaymentIntent €3 com idempotency key.

### Backend (RPCs aplicadas via MCP)
| RPC | Função |
|---|---|
| `client_confirm_reservation_payment(uuid)` | Marca paid + notifica partner |
| `client_cancel_reservation(uuid, text)` | Calcula janela ≥2h, refund decision |
| `partner_decide_reservation(uuid, bool, text)` | Aprovar/rejeitar (rejeição = refund auto) |
| `partner_mark_arrival(uuid)` | Cria `restaurant_menu_credits` €3 + notifica |
| `auto_close_no_show_reservations()` | Marca no_show + notifica (cron 0 * * * *) |
| `consume_menu_credit_for_order(uuid, text, text)` | Aplica crédito no checkout |
| `admin_reservations_metrics(int)` | KPIs no-show%, cancel%, receita |
| `admin_reservations_today()` | Card "Reservas hoje" |

Todas com `_admin_op_guard` onde aplicável + audit log onde relevante.

### 8 Smoke tests via MCP
| # | Cenário | Verdict |
|---|---|---|
| 1 | 7 RPCs + cron job existem em prod | ✅ |
| 2 | Tabela `restaurant_menu_credits` + 4 settings populated | ✅ |
| 3 | Cron `auto_close_no_show_reservations` schedule `0 * * * *` activo | ✅ |
| 4 | Cron marca `approved + reserved_for<NOW-60min` como `no_show` + notifica | ✅ |
| 5 | `consume_menu_credit` usa 1× e bloqueia segunda chamada (FOR UPDATE SKIP LOCKED) | ✅ |
| 6 | `admin_reservations_metrics` protegida por `_admin_op_guard` (rejected without auth) | ✅ |
| 7 | `admin_reservations_today` protegida (rejected without auth) | ✅ |
| 8 | Cancel window math (≥2h vs <2h) calculo correcto | ✅ |

### Flutter
**Cliente:**
- ✅ `reservation_flow_screen` migrado: chama Edge Fn → Stripe `presentPaymentSheet` → RPC `client_confirm_reservation_payment`. Banner verde "Cancelamento gratuito até 2h antes".
- ✅ `client_reservations_screen` novo: lista reservas + botão Cancelar com confirmation dialog (avisa se <2h)
- ⚠️ Checkout integration `consume_menu_credit_for_order` — RPC pronta, integração no `create_order` flow fica como follow-up (precisa modificar create_order RPC para aplicar credit antes do total)

**Parceiro:**
- ✅ `partner_reservations_screen` migrado para 2 RPCs: `partner_decide_reservation` (aprovar/rejeitar) + `partner_mark_arrival` (chegada → credit auto)

**Admin:**
- ✅ `admin_reservations_screen` melhorado com `_MetricsHeader` (no-show%, cancel%, receita Bora, créditos)
- ✅ `AdminReservationsTodayCard` widget no admin_dashboard (refresh 60s)

### business_rules.md §18
Adicionada secção completa com tabelas de estados, fluxo de dinheiro, política cancelamento, crédito menu.

## Bugs novos descobertos

1. **`reservations.client_user_id`** (não `user_id`): Edge Fn v1 falhava no INSERT. **Fix**: redeployed v2.

2. **`auto_map_category` v1 false positives**: `cat→moscatel`, `cha→charcutaria`, `rum→arrumação`, `ração→decoração`. **Fix**: word boundaries `\m...\M` (regex Postgres).

3. **`INITCAP` em HTML entities**: `Beb&eacute;` ficava `Beb&Eacute;`. **Fix**: CASE/WHEN map.

4. **86 roots → "Outros"**: maioria são electrónica/papelaria/brinquedos. Aceitável (sem secção alimentar dedicada). Admin pode rever caso queira separar.

5. **Notificação para parceiro requer `restaurants.email == auth.users.email` match** — funciona, mas se um parceiro não tem auth user com mesmo email, a notification não chega. Documentar no onboarding.

## Verificação MCP final

✅ Tabelas novas: `category_mapping` (281 rows), `restaurant_menu_credits`
✅ Settings: 4 entries em `category='reservations'`
✅ Triggers: `trg_products_auto_taxonomy`, `trg_category_mapping_touch`
✅ Edge Fns: `create-reservation-payment-intent` v2 ACTIVE
✅ Cron: `auto_close_no_show_reservations` (0 * * * *)
✅ RPCs admin: 4 novas (`admin_list_category_mappings`, `admin_update_category_mapping`, `admin_category_mapping_stats`, `admin_reservations_metrics`, `admin_reservations_today`)
✅ RPCs cliente/partner: 6 novas (`client_*` + `partner_*` + `auto_close_*` + `consume_menu_credit_*`)

## Comandos rollback

### T1 (categorias)
```sql
DROP TRIGGER trg_products_auto_taxonomy ON public.products;
DROP FUNCTION public._products_set_taxonomy_section();
DROP FUNCTION public.auto_map_category(text);
DROP FUNCTION public._normalize_for_match(text);
DROP TABLE public.category_mapping CASCADE;
-- Não-destrutivo dos produtos: taxonomy_section continua populado.
```

### T2 (reservas)
```sql
SELECT cron.unschedule('auto_close_no_show_reservations');
DROP FUNCTION public.consume_menu_credit_for_order CASCADE;
DROP FUNCTION public.auto_close_no_show_reservations();
DROP FUNCTION public.partner_mark_arrival(uuid);
DROP FUNCTION public.partner_decide_reservation(uuid, boolean, text);
DROP FUNCTION public.client_cancel_reservation(uuid, text);
DROP FUNCTION public.client_confirm_reservation_payment(uuid);
DROP FUNCTION public.admin_reservations_metrics(int);
DROP FUNCTION public.admin_reservations_today();
DROP TABLE public.restaurant_menu_credits CASCADE;
DELETE FROM platform_settings WHERE category='reservations';
-- Edge Fn rollback: redeploy create-reservation-payment-intent v1 ou disable
```

## Tempo por tarefa

| Tarefa | Tempo |
|---|---|
| T1 (categorias: investigação + função v1+v2 + bulk + trigger + admin) | ~50min |
| T2.A (decisão + business_rules §18) | ~10min |
| T2.B+C (settings + table + Edge Fn) | ~20min |
| T2.D (6 RPCs + cron) | ~30min |
| T2.E (Flutter cliente — flow Stripe + lista) | ~25min |
| T2.F (Flutter parceiro — RPCs migration) | ~10min |
| T2.G (Admin metrics + dashboard card) | ~20min |
| T2.H (8 smoke tests) | ~10min |
| Migrations locais + relatório | ~15min |
| **Total** | **~3h 10min** |

## Estado da branch + commits

Pre-sessão: HEAD `7bfbb4e` (sessão fechar-tudo).

Commits planeados (4):
1. `feat(T1): category_mapping 281→23 (auto_map v2 + trigger + admin screen)`
2. `feat(T2-backend): reservations pré-pagamento €3 (Edge Fn + 6 RPCs + cron + business_rules §18)`
3. `feat(T2-flutter): cliente reservation flow Stripe + lista + parceiro decide/arrival`
4. `feat(T2-admin): metrics screen + dashboard card "Reservas hoje"`

Push final: `origin/autonomous-night-2026-04-29`.
