# 08 — Edge Functions

> Snapshot via MCP `list_edge_functions` (projeto `ojykpzwqrtusfeakzrna`, 2026-05-29):
> **44 funções ACTIVE**. As skills **chamam** estas funções — nunca as recriam.
> `verify_jwt` indicado entre parênteses.

## Pagamentos / financeiro
- `create-payment-intent` (jwt=false) — Stripe card; valida amount ±5% vs `orders.payment_buffer_total`; mín €0.50.
- `create-mbway-payment-intent` (jwt=false) — MB WAY LIVE; phone E.164 → push MB WAY.
- `stripe-webhook` (jwt=false) — `payment_intent.succeeded` → paid + dispatch.
- `refund` (jwt=true, service_role) — reembolso Stripe.
- `charge-extra` (jwt=true) — cobrança extra (storeShopping).
- `finalize-order-from-intent` · `pay-debt-standalone` · `list-saved-cards` (jwt=true).
- `create-reservation-payment-intent` · `create-mbway-reservation-payment-intent` — prépagamento reservas.

## Dispatch / pedidos
- `dispatch-engine` (jwt=false, v56) — motor de dispatch server-side (fonte de verdade).
- `client-cancel-order` · `cancel-order-with-choice` · `execute-cancellation` (jwt=true).
- `admin-cancel-order` · `admin-cancel-reservation` (jwt=true).

## Onboarding / uploads (USADAS PELAS ONBOARDERS)
- **`register-partner`** (jwt=true, v3) — cria 1 restaurante parceiro. Detalhe ↓.
- **`upload-restaurant-asset`** (jwt=true, v3) — upload p/ bucket público `restaurant-assets`. Detalhe ↓.
- **`upload-driver-document`** (jwt=true, v1) — documentos de estafeta.
- `upload-avatar` · `upload-receipt` · `upload-order-photo` (jwt=true).
- `update-products` (jwt=false) — mutação de produtos em lote.

## Notificações (push)
- `notify-driver` (jwt=false) · `notify-partner` · `notify-client` · `notify-chat-message` ·
  `notify-admin-urgent` · `notify-admin-reimbursement` · `notify-partner-low-rating` ·
  `notify-purchase-finalized`.

## Suporte / IA / admin
- `support-chatbot` · `support-submit-ticket` · `support-password-reset` · `robot-b` ·
  `analyze-conversations` · `reindex-knowledge` · `admin-ai-assistant` · `gemini-diagnostic` ·
  `ocr-receipt` · `execute-broadcast` · `admin-force-driver-logout` · `delete-account`.

---

## `register-partner` — payload (verify_jwt=true)
Requer `Authorization: Bearer <JWT>` do **utilizador parceiro** (o `sub` do JWT vira
`restaurants.user_id`). POST JSON:
```jsonc
{
  "restaurantName": "string (obrigatório)",
  "address": "string (obrigatório)",
  "email": "string (obrigatório)",
  "phone": "string",
  "cuisineType": "string",          // '' para loja/farmácia
  "category": "restaurant|supermarket|store|pharmacy",
  "lat": 0.0, "lng": 0.0,           // opcional
  "nif": "9 dígitos",               // opcional; valida mód-11
  "iban": "PT + 21 dígitos",        // opcional; regex ^PT\d{21}$  ⚠️ NÃO é PT50
  "ownerDocUrl": "url", "activityDocUrl": "url"  // opcional
}
```
- Cria `restaurants` com `is_partner=true`, `is_online=false`, `approval_status='pending'`, `photo_url=''`.
- Resposta 201: `{ success, restaurant_id, status:'pending', message }`.
- **NÃO insere produtos** nem define logo/hero — fazer separadamente (ver abaixo).
- ⚠️ Validação IBAN real: **`^PT\d{21}$`** (23 chars). A spec antiga "PT50+21" estava errada
  (bug histórico corrigido — ver memória `project_sessao_partner_approval_fix`).

## `upload-restaurant-asset` — payload (verify_jwt=true)
POST JSON: `{ restaurantId, kind, fileBase64, contentType }`.
- `kind`: string livre (`owner_doc`, `activity_doc`, `logo`, `hero`, …).
- Upload p/ bucket público `restaurant-assets`, path `{restaurantId}/{kind}-{timestamp}.{ext}`.
- Resposta 200: `{ success, public_url, path }`.
- Para logo/hero aparecerem: após upload, **UPDATE `restaurants.photo_url` / `hero_image_url`**
  com o `public_url` (a função não toca nessas colunas).

## Produtos
register-partner não cria produtos. Inserir em `products` (PostgREST autenticado como o
parceiro — RLS valida `restaurants.user_id = auth.uid()`) **ou** via `update-products`.

## Fontes adicionais
- `.claude/.ai/knowledge/from-obsidian/arquitetura/edge-functions.md` (visão histórica).
- Fonte de verdade: `bora_app/supabase/functions/*/index.ts` + MCP `get_edge_function`.
