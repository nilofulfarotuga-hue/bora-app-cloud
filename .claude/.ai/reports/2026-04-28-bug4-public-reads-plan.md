# BUG 4 end-to-end — Plano de filtro nas reads públicas

> **Data:** 2026-04-28
> **Estado:** ⏸ AGUARDA APROVAÇÃO
> **Contexto:** B.3.4 deferida da Fase 1. Admin desliga `is_active_admin=false` mas o cliente continua a ver no storefront. Esta task fecha o ciclo.

---

## 1. Inventário completo (10 ocorrências, 3 ficheiros)

| # | Ficheiro:Linha | Operação | Contexto | Acção sugerida |
|---|---|---|---|---|
| 1 | `screens/admin/admin_partners_screen.dart:34` | `.from('restaurants').select('id,name,category,address,is_active_admin')` | **Admin** — lista para gerir | **NÃO ALTERAR** — admin precisa de ver os suspensos |
| 2 | `screens/admin/admin_partners_screen.dart:57` | `.update({'is_active_admin': newActive})` | **Admin** — toggle | N/A (write) |
| 3 | `services/notification_service.dart:196` | `.update({'fcm_token': token})` | Parceiro guarda token | N/A (write próprio) |
| 4 | `services/notification_service.dart:228` | `.update({'fcm_token': null})` | Parceiro logout | N/A (write próprio) |
| 5 | `stores/restaurant_store.dart:130` | `.from('restaurants').select()` | **Carga global** — partilhada por TODOS | ⚠️ **NÃO ALTERAR** (ver §2) |
| 6 | `stores/restaurant_store.dart:135` | `.from('restaurants').select()` | Re-carga após seed | ⚠️ **NÃO ALTERAR** (ver §2) |
| 7 | `stores/restaurant_store.dart:466` | `.insert({...})` | Seed inicial | N/A (write) |
| 8 | `stores/restaurant_store.dart:650` | `.update({'is_online': isOnline})` | Parceiro toggle online | N/A (write próprio) |
| 9 | `stores/restaurant_store.dart:668` | `.update({'reservations_enabled': enabled})` | Parceiro toggle reservas | N/A (write próprio) |
| 10 | `stores/restaurant_store.dart:686` | `.update({'business_hours': ...})` | Parceiro horários | N/A (write próprio) |

**Apenas 2 SELECTs em DB.** Ambos em `restaurant_store.dart` (linhas 130 e 135). Não há nenhum outro lugar em Flutter que faça `.from('restaurants').select()` — tudo o resto consome a lista em memória `_restaurants`.

---

## 2. Por que NÃO filtrar em `loadRestaurantsFromSupabase` (linhas 130/135)

A lista carregada por essas 2 queries é a **fonte única** consumida por **TODOS** os papéis. Adicionar `.eq('is_active_admin', true)` lá esconde do cliente — mas também:

| Consumidor | Ficheiro:Linha | O que parte se filtrarmos em DB |
|---|---|---|
| 🚨 **Dashboard parceiro suspenso** | `partner_dashboard_screen.dart:127` (`restaurantStore.restaurants.firstWhere`) | Parceiro perde acesso ao seu próprio painel |
| 🚨 **Login parceiro suspenso** | `partner_login_screen.dart:176`, `partner_entry_screen.dart:28`, `register_partner_screen.dart:123` (`restaurantByEmail`) | Parceiro suspenso não consegue logar para reclamar / entender |
| 🚨 **Driver pickup lookup** | `driver_map_screen.dart:784` (resolve `vendorName → restaurant.lat/lng` para pedidos activos) | Drivers de pedidos in-flight perdem o pickup geocoded |
| ⚠️ **Detail screen (re-entry)** | `restaurant_menu_screen.dart:136` (`restaurantById`) | Cliente que tinha o restaurant aberto / orderando vê a tela quebrar a meio |
| ✅ Histórico (`orders_screen`, `order_details_screen`, `chat_screen`) | usa `order.vendorName` (snapshot text) | Não afectado — `vendor_name` está gravado nos `orders` |

**Conclusão:** filtrar em DB é demasiado agressivo. Quebra fluxos críticos de parceiro e driver.

---

## 3. Plano recomendado (Opção β) — filtrar em memória, só nos widgets de storefront

### Princípio
- **NÃO mudar** as queries DB (`L130`, `L135`).
- **Adicionar** o campo `isActiveAdmin` ao `RestaurantModel` para que esteja disponível em memória.
- **Adicionar** um getter `RestaurantStore.publicRestaurants` que filtra `isActiveAdmin == true`.
- **Mudar** as 2 telas de storefront público para consumir `publicRestaurants` em vez de `restaurants`.

### Mudanças exactas

| # | Ficheiro | Linhas | Mudança | Tamanho |
|---|---|---|---|---|
| M1 | `lib/models/restaurant_model.dart` | constructor + factory + copyWith | Adicionar `final bool isActiveAdmin;` (default `true`) | ~3 linhas |
| M2 | `lib/stores/restaurant_store.dart` | `_restaurantFromRecord` (linha ~750) | Ler `isActiveAdmin: data['is_active_admin'] ?? true,` | 1 linha |
| M3 | `lib/stores/restaurant_store.dart` | adicionar getter público | `List<RestaurantModel> get publicRestaurants => _restaurants.where((r) => r.isActiveAdmin).toList();` | ~3 linhas |
| M4 | `lib/screens/restaurants_screen.dart` | linha 25 | `restaurantStore.restaurants` → `restaurantStore.publicRestaurants` | 1 linha |
| M5 | `lib/screens/stores_screen.dart` | linha 35 | `restaurantStore.restaurants` → `restaurantStore.publicRestaurants` | 1 linha |

**Total: ~9 linhas em 4 ficheiros.** Ligeiramente acima do "3-5 linhas" pedido, mas é o mínimo seguro. A alternativa (filtrar em DB) é 1 linha mas parte 3 fluxos críticos.

### O que continua a funcionar (intencionalmente)
- ✅ Admin vê tudo (partners screen usa query própria com `is_active_admin` na coluna mas sem filtro)
- ✅ Parceiro suspenso continua a ver o seu dashboard, fazer login, ler horários, alterar `is_online`
- ✅ Driver com pedido activo num vendor que admin acabou de suspender continua a ver pickup geocoded
- ✅ Recibos antigos continuam a mostrar `vendor_name` (snapshot string, sem lookup)
- ✅ Detalhe de pedidos passados (`order_details_screen.dart`) inalterado

### Riscos por mudança
| # | Risco | Notas |
|---|---|---|
| M1 | **Baixo** | Adição de campo opcional default `true`. Não quebra serialização (DB column tem default `true`). |
| M2 | **Baixo** | 1 linha; `?? true` mantém retrocompatibilidade se a query não trouxer a coluna. |
| M3 | **Nulo** | Novo getter, não toca em código existente. |
| M4 | **Baixo** | Mesma assinatura `List<RestaurantModel>`, só esconde os suspensos. |
| M5 | **Baixo** | Idem. |

---

## 4. Validação SQL planeada (após apply)

Setup:
```sql
UPDATE public.restaurants SET is_active_admin = false WHERE id = 'auchan-guarda';
```

Asserts:
1. **Storefront simulado** — `SELECT * FROM restaurants WHERE category IN (...) AND is_active_admin = true;` → não retorna `auchan-guarda` ✅
2. **Histórico cliente simulado** — `SELECT vendor_name FROM orders WHERE vendor_name = 'Auchan';` → continua a retornar (vendor_name é snapshot) ✅
3. **Lookup do próprio parceiro** — `SELECT * FROM restaurants WHERE email = '<auchan email>';` → continua a retornar (sem filtro) ✅
4. **Cleanup** — `UPDATE … SET is_active_admin = true …`

(Nota: o filtro em **memória** Flutter não é testável directamente em SQL; vou validar com asserts equivalentes que provam que a coluna se comporta como esperado — o filtro em Dart é uma 1-line `where`, baixíssimo risco.)

---

## 5. Pergunta ao Danilo

**Aprovas a Opção β** (4 ficheiros, ~9 linhas)?

Alternativa **Opção α** (filtrar em DB, 2 linhas) está disponível, mas só recomendo se aceitares o trade-off de partir login/dashboard de parceiro suspenso. Não é o que o teu prompt original pretendia ("não tocar em queries de histórico/pedidos antigos" — implica preservar visibilidade onde necessário; o partner dashboard cai no mesmo princípio).
