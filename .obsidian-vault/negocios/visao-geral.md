# Bora App — Visão Geral

**Plataforma:** Delivery e logística urbana (Guarda, Portugal)
**Stack:** Flutter (mobile + web) + Supabase (PostgreSQL + Edge Functions + Realtime)
**Pagamentos:** Stripe (cartão) + MBWay (simulado) + Dinheiro
**Supabase:** `ojykpzwqrtusfeakzrna.supabase.co`
**Contacto:** boraappbora@gmail.com · +351 937 501 673
**Logótipo:** "B" verde escuro (#1B5E20) + motociclista vermelho/laranja

---

## Perfis de Utilizador

| Perfil | Descrição |
|---|---|
| Cliente | Faz pedidos, paga, recebe entregas |
| Estafeta (Driver) | Aceita pedidos, recolhe e entrega |
| Parceiro | Restaurante/loja com acordo comercial |
| Admin | Danilo (único por agora) |
| Empregada de Limpeza | Presta serviços de limpeza (futuro) |

---

## Tipos de Serviço

- `restaurant` — restaurante parceiro
- `storeShopping` — compra no mercado (estafeta compra pelo cliente)
- `carryGroceries` — levar compras que o cliente já fez
- `sendPackage` — enviar encomenda de A para B
- `restaurantReservation` — reserva de mesa (lançamento)
- `restaurantTakeaway` — cliente vai buscar (lançamento)
- `homeCleaning` — limpeza de casa (futuro)
- `marketplace` — compra internacional (futuro)

---

## Estado Atual (Abril 2026)

### ✅ Pronto para produção
- Order lifecycle completo
- Dispatch Engine server-side (Edge Function com retry)
- Sistema financeiro (ledger, driver balances, cash cap €40)
- Tokens/Loyalty (atribuição automática, FIFO)
- Pricing engine (todos os tipos de serviço)
- Auth dual-layer + demo accounts offline
- Google Maps (mapa cliente + driver, autocomplete)
- MBWay e Cash funcionais
- Admin dashboard (métricas financeiras)

### ⚠️ Parcial
- Stripe — integrado mas `BACKEND_BASE_URL` sem URL de produção
- Realtime sync — subscriptions ativas mas com bugs entre dispositivos
- Driver flow UI — incompleto
- Push Notifications — Firebase desativado

### ❌ Por fazer
- Firebase / Push Notifications
- MBWay real (integração com banco)
- Partner demo account
- Admin access control (substituir email allowlist)
- ChatStore / FavoriteStore
