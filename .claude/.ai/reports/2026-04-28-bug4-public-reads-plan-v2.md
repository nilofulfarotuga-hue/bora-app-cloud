# BUG 4 end-to-end — Plano REVISTO (parceiro vs não-parceiro)

> **Data:** 2026-04-28
> **Estado:** ⏸ AGUARDA APROVAÇÃO
> **Substitui:** `2026-04-28-bug4-public-reads-plan.md` (v1)
> **Razão da revisão:** v1 tratou todos os restaurantes como iguais. Danilo apontou correctamente que o sistema tem 2 tipos com comportamentos diferentes.

---

## 1. Como o sistema distingue parceiro vs não-parceiro

| Aspecto | Parceiro | Não-parceiro |
|---|---|---|
| Coluna DB | `restaurants.is_partner = true` | `restaurants.is_partner = false` |
| Como é setada | `register_partner_screen` → `RestaurantStore.registerPartnerRestaurant` → INSERT com `'is_partner': true` (`restaurant_store.dart:471`) | Seed / scrape público (Auchan, Lidl, …) com `'is_partner': false` |
| Email | Real (gmail, etc) | Convenção `<nome>@nonpartner.bora.app` |
| Auth Supabase | Sim — login via `partner_login_screen` | Não (auth_link='no-auth' confirmado em SQL) |
| Dashboard | `partner_dashboard_screen` + `restaurant_dashboard_screen` | Inexistente |
| Pode mudar `is_online`, `business_hours`, `reservations_enabled` | Sim (próprio) | Não (mas a coluna existe) |
| Aparece no storefront cliente | Sim | Sim |
| Driver pode pickup | Sim | Sim (Auchan groceries, etc) |

**Distribuição actual em produção (confirmada por SQL):**
- `is_partner = true` → 4 (todos test/dummy: iyyth, kbvyg, pizzaria paulista x2)
- `is_partner = false` → 10 (Auchan, Burger King, Continente, …)

`auchan-guarda` (id usado nos testes) → **não-parceiro** (`is_partner=false`, email `auchan@nonpartner.bora.app`, sem auth).

---

## 2. Re-análise dos 3 "fluxos que partem" — agora por tipo

### Fluxo a) Dashboard parceiro — `partner_dashboard_screen.dart:127`

```dart
final currentRestaurant = restaurantStore.restaurants.firstWhere(
  (r) => r.id == widget.restaurant.id,
  orElse: () => widget.restaurant,    // ← FALLBACK
);
```

| | Análise | Veredicto |
|---|---|---|
| Aplica a não-parceiros? | Não — eles não têm dashboard | N/A |
| Aplica a parceiros? | Sim, mas há `orElse` | Não parte; cai em `widget.restaurant` (snapshot inicial) |
| Comportamento se filtrarmos em DB | Parceiro suspenso vê dashboard com info **stale** (snapshot do momento que entrou); refreshes em background falham silenciosamente; mudanças (toggle online, business_hours) ainda funcionam porque chamam UPDATE directo em DB | **Não parte. Fica desactualizado.** |

→ **Risco real: BAIXO**. O `orElse` salva-nos. E ficar stale é semanticamente correcto: admin suspendeu, parceiro não deveria ter info fresca.

### Fluxo b) Login parceiro — `restaurantByEmail` em `partner_login_screen.dart:176`

```dart
final restaurant = restaurantStore.restaurantByEmail(_emailController.text);
if (restaurant == null) {
  authStore.logout();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Não encontramos o restaurante associado a este email.')),
  );
  return;
}
```

| | Análise | Veredicto |
|---|---|---|
| Aplica a não-parceiros? | Não — eles não fazem login (sem `auth.users` link) | N/A |
| Aplica a parceiros? | Sim | Snackbar de erro genérico |
| Comportamento se filtrarmos em DB | Parceiro suspenso vê "Não encontramos…" e fica preso fora | **Não parte sistema. UX confusa.** |

→ **Risco real: MÉDIO** (UX, não funcional). Semanticamente o login deveria ser bloqueado quando admin suspende — mas a mensagem actual é enganosa.

### Fluxo c) Driver pickup lookup — `driver_map_screen.dart:780-820`

```dart
/// Visual-only override: for each pickup stop, if the order has a
/// vendorName that matches a known restaurant, replace the stop location
/// with the real restaurant coordinates. Does NOT mutate the order or
/// affect pricing — only the marker/polyline rendering.
```

| | Análise | Veredicto |
|---|---|---|
| Aplica a não-parceiros? | **Sim** — driver pode ir buscar groceries ao Auchan | — |
| Aplica a parceiros? | Sim — driver pode ir buscar comida à Pizzaria | — |
| Comportamento se filtrarmos em DB | Lookup retorna nada → cai no `if (realLoc == null) return stop;` → mantém `stop` original com `order.pickup_lat/lng` (já no order) | **NÃO PARTE.** Cai no fallback. |
| Visual-only confirmado | O comentário do código diz expressly "Does NOT mutate the order or affect pricing — only the marker/polyline rendering" | — |

→ **Risco real: NULO**. É uma optimização visual que já tem fallback robusto.

---

## 3. Re-classificação dos riscos

A v1 listou 3 fluxos como "parte". Após análise empírica do código:

| Fluxo | v1 classificou | v2 confirma | Aplica a |
|---|---|---|---|
| Dashboard parceiro | 🚨 partia | 🟡 stale data, não parte | só parceiros |
| Login parceiro suspenso | 🚨 partia | 🟡 UX confusa, não parte | só parceiros |
| Driver pickup lookup | ⚠️ partia | ✅ tem fallback, nulo | ambos |

**Conclusão chave:** A Opção α (filtrar em DB) é **bastante mais segura do que a v1 sugeria**. Nenhum fluxo "parte"; o pior caso é um parceiro suspenso ver snackbar enganador no login (UX, não funcional).

---

## 4. Plano revisto — 3 opções

### Opção α — Filtrar em DB (2 linhas) ⭐ RECOMENDADA agora

**Mudança:**
```dart
// restaurant_store.dart L130 e L135
List<dynamic> response = await supabase
    .from('restaurants')
    .select()
    .eq('is_active_admin', true);     // ← novo
```

**Pros:**
- 2 linhas, 1 ficheiro, mudança cirúrgica
- End-to-end imediatamente: admin desliga → cliente, parceiro e driver lookup deixam de ver
- **Semanticamente correcto:** "admin tem poder total" → suspenso fica suspenso para todos os fluxos públicos (incluindo o login parceiro suspenso, que é exactamente o que admin pretende ao suspender)

**Cons (mínimos):**
- Parceiro suspenso vê "Não encontramos o restaurante…" no login — mensagem genérica, UX confusa. **Mitigação opcional (1-2 linhas)**: melhorar o snackbar para "Conta suspensa pelo admin. Contacta-nos." mas isto requer saber que existe vs está suspenso → exigiria query adicional, fora de scope.
- Dashboard parceiro suspenso (se já estava logado) mostra info stale. Não parte; mudanças directas em DB ainda funcionam. Aceitável.

**Risco:** Baixo.

### Opção β — Filtrar em memória só nos widgets de storefront (~9 linhas)

**Mudanças:** model + factory + copyWith + getter `publicRestaurants` + 2 telas (descrito na v1).

**Pros:**
- Parceiro suspenso continua a poder fazer login e ver dashboard (stale info)
- Útil se quiseres permitir que parceiro suspenso possa ler mensagens / saber que foi suspenso

**Cons:**
- 9 linhas em 4 ficheiros
- Parceiro suspenso pode operar dashboard (toggle online, etc) **mesmo após admin suspender** — semanticamente fraco vs "admin tem poder total"
- Não bloqueia driver pickup lookup (que é nulo na prática mas seria desejado para audit)

### Opção γ — Híbrida (RLS policy)

Descartada. Requer `user_` linkado em `restaurants` (actualmente null em todos os parceiros) e adiciona complexidade RLS sem benefício marginal sobre α.

---

## 5. Recomendação

**Adoptar Opção α.**

Justificação:
1. **Mudança mínima** — 2 linhas vs 9
2. **Mais alinhada com o princípio "admin tem poder total"** — suspender significa suspender, não "esconder do cliente mas deixar parceiro logar".
3. **Risco re-avaliado como baixo** — nenhum fluxo realmente parte; pior caso é UX confusa no login do parceiro suspenso (que é raro e semanticamente correcto)
4. **Reversível** — admin reactiva → parceiro volta ao normal imediatamente
5. **Não bloqueia melhorias futuras** — se mais tarde quiseres mensagem dedicada "conta suspensa" no login, é uma mudança aditiva (não exige tirar α)

---

## 6. Plano de validação SQL (após aplicar α)

Setup:
```sql
UPDATE public.restaurants SET is_active_admin = false WHERE id = 'auchan-guarda';
```

Asserts:
1. **Storefront cliente (não-parceiro suspenso)** — `SELECT count(*) FROM restaurants WHERE is_active_admin = true AND id = 'auchan-guarda';` → **0** ✅
2. **Storefront cliente (não-parceiro activo)** — `SELECT count(*) FROM restaurants WHERE is_active_admin = true AND id = 'continente-guarda';` → **1** ✅ (controlo: outros não-parceiros continuam visíveis)
3. **Histórico cliente** — `SELECT vendor_name FROM orders WHERE vendor_name = 'Auchan';` → continua a retornar (snapshot text, não passa por restaurants) ✅
4. **Admin partners screen (lê tudo)** — `SELECT count(*) FROM restaurants;` → **14** (sem filtro) ✅ — confirma que admin continua a ver suspensos

Setup parceiro:
```sql
UPDATE public.restaurants SET is_active_admin = false WHERE id = 'partner-1776237403416663';
```
Asserts:
5. **Storefront cliente (parceiro suspenso)** — não retorna pizzaria paulista ✅
6. **Login parceiro (`restaurantByEmail`)** — devolveria `null`; UI mostra "Não encontramos o restaurante…" — esperado (fricção semanticamente correcta) ⚠️

Cleanup:
```sql
UPDATE public.restaurants SET is_active_admin = true WHERE id IN ('auchan-guarda', 'partner-1776237403416663');
```

---

## 7. Pergunta ao Danilo

**Aprovas Opção α (2 linhas, filtro em DB)** ou preferes **Opção β (9 linhas, parceiro suspenso ainda pode logar)**?

Default sugerido: **α** (aderente a "admin tem poder total").

Se aprovares α e quiseres a UX melhorada do snackbar do login do parceiro suspenso, abro task de seguimento ("partner_login: distinguir 'não existe' de 'suspenso'").
