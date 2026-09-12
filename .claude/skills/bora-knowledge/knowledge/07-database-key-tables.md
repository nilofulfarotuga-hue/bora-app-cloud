# 07 — Tabelas-chave (DB)

> Snapshot via MCP Supabase `information_schema.columns` (projeto `ojykpzwqrtusfeakzrna`,
> 2026-05-29). Schema declarativo completo: `bora_app/supabase/schema.sql`.
> ⚠️ `restaurants.id`, `products.id`, `orders.id` são **TEXT** em prod (legado).
> `assigned_driver_id` é TEXT propositadamente (cast `::UUID` nos triggers).

## restaurants (parceiros, mercados, farmácias, lojas)
PK `id` TEXT. Colunas-chave: `user_` (uuid, NULL p/ non-partner) · `name` · `address` ·
`phone` · `email` · `is_partner` · `category` (restaurant/supermarket/store/pharmacy) ·
`cuisine_type` · `photo_url` · `hero_image_url` · `lat`/`lng` · `is_online`(def true) ·
`business_hours` (jsonb, default 09:00-22:00 todos os dias) · `reservations_enabled`(false) ·
`takeaway_enabled`(false) · `takeaway_default_prep_minutes`(20) · `curbside_enabled`(false) ·
`nif` · `iban` · `owner_doc_url` · `activity_doc_url` · `approval_status`(**'pending'**) ·
`approved_at/by` · `rejection_reason` · `avg_rating` · `ratings_count`(0) · `fcm_token` ·
`is_active_admin`(true) · `submitted_at` · `reviewed_at` · `user_id`(uuid).

## products
PK `id` TEXT. `restaurant_id` · `name` · `description` · `photo_url` · `price` ·
`is_available` · `category` · `unit` · variantes inline (`brand_low/mid/premium` +
`price_low/mid/premium`) · `is_popular`(false) · `is_on_sale`(false) · `discount_price` ·
`source` · `image_source` · `needs_photo`(false) · `needs_review`(false) ·
taxonomy: `category_root` · `taxonomy_section` · `taxonomy_confidence`(0) ·
`search_normalized` · `name_original` · `name_es` (Mercadona ES→PT).

## product_variants
PK `id` TEXT. `product_id` · `brand_name` · `price` (double). Usado p/ ex. Zippy (tamanhos/marcas).

## orders (TABELA GRANDE — ver schema.sql para todas as colunas)
PK `id` TEXT (gen_random_uuid). `user_id` · `status` · `service_type` · `order_type` ·
`is_partner_store`(false) · `restaurant_id` · `vendor_name` · endereços
(`pickup_*`/`dropoff_*` + lat/lng) · `payment_method` · `payment_status`('pending') ·
breakdown financeiro: `subtotal` · `delivery_fee` · `service_fee` · `platform_commission` ·
`driver_earnings` · `bag_count`/`bag_fee` · `partner_commission_visible` ·
`partner_markup_hidden` · `partner_service_fee_client` · `total`/`customer_total` ·
`payment_buffer_total` · `estimated_total`. Dispatch: `assigned_driver_id`(TEXT) ·
`current_driver_offer_id` · `driver_offer_expires_at` · `driver_offer_history`(jsonb) ·
`tried_driver_ids`. Tokens/wallet: `tokens_applied_*` · `wallet_applied_cents`.
Cancelamento: `cancel_reason`/`cancel_fee`/`cancelled_*`/`refund_*`. Takeaway: `takeaway_*`.
`is_test_order`(false) · `purchase_flow_version`(1).

## drivers
PK `id` uuid. `user_id` · `name` · `email` · `phone` · `vehicle_type` · `license_plate` ·
`lat`/`lng` · `is_online`(true) · `fcm_token` · `photo_url` · documentos
(`document_type`('cc'), `document_number`, `document_photo_url`, `vehicle_doc_url`,
`registration_selfie_url`) · `iban` · `nif` · `payment_method`('mbway') · `mbway_phone` ·
`approval_status`('pending') · `approved_at/by` · `rejection_reason` · `token_balance`(0) ·
`avg_rating` · `ratings_count`(0) · banimento (`is_banned`(false), `banned_*`, `ban_reason_code`) ·
soft-delete (`deleted_*`) · `last_forced_logout_at/by` · `last_heartbeat_at` · `consent_*`.

## users
PK `id` uuid. `name` · `email` · `phone` · `role` · `fcm_token` · `photo_url` · `stripe_customer_id`.

## reservations
PK `id` uuid. `restaurant_id` · `client_user_id` · `client_name`/`phone` · `people`(2) ·
`reserved_for` · `status`('pending') · `prepayment_cents`(0) · `prepayment_pi` ·
`event_type`('normal') · `is_walk_in`(false) · lembretes (`reminder_24h/2h_sent_at`) · `floor_plan_id`.

## ledger_entries
PK `id` uuid. `user_id`(TEXT) · `user_type` · `order_id`(uuid) · `amount` · `type` · `reference` · `created_at`.

## bora_tokens
PK `id` uuid. `user_id` · `role` · `amount` · `source_order_id`(TEXT) · `is_used`(false) · `used_at` · `expires_at`.

## platform_settings
PK `key` TEXT. `value`(jsonb) · `description` · `category` · `updated_at/by`. Ver [09](09-platform-settings.md).

## Fontes adicionais
- `.claude/.ai/knowledge/architecture/data-model.md`.
- `bora_app/supabase/schema.sql` (snapshot declarativo) + `supabase/migrations/` (cronológico).
