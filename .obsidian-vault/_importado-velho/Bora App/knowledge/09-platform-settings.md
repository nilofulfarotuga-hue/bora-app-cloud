# 09 — Platform Settings (runtime)

> Tabela `platform_settings` (PK `key` TEXT, `value` jsonb). 67 chaves
> (snapshot MCP 2026-05-29). Valores monetários em **cêntimos** salvo indicação.
> Ler: `SELECT key, value FROM platform_settings WHERE key='...'`.
> Alterar: ver receita em [12-recipes.md](12-recipes.md). **Mudança = decisão de negócio** → confirmar com Danilo.

## Entrega / distância
| key | valor | nota |
|-----|-------|------|
| delivery_base_fee_cents | 250 | €2.50 base |
| delivery_base_distance_km | 4 | km incluídos na base |
| delivery_per_km_cents | 50 | €0.50/km extra |

## Estafeta
| key | valor |
|-----|-------|
| driver_base_fee_cents | 380 |
| driver_per_km_cents | 20 |
| driver_surcharge_cents | 80 |
| driver_profit_share_pct | 0.30 |
| partner_driver_stacking_bonus_cents | 300 |
| logistics_driver_base_cents | 400 |
| logistics_driver_per_km_cents | 50 |
| package_base_fee_cents | 600 |
| package_platform_share_cents | 200 |

## Comissão / markup
| key | valor |
|-----|-------|
| non_partner_markup_pct | 0.15 |
| partner_visible_commission_pct | 0.10 |
| partner_hidden_markup_pct | 0.05 |
| client_service_fee_pct | 0.05 |

## Sacos / apartamento / cash / extra
| key | valor |
|-----|-------|
| bag_fee_restaurant_cents | 30 |
| bag_fee_supermarket_per_bag_cents | 10 |
| apartment_surcharge_total_cents | 150 (100 driver + 50 plataforma) |
| max_cash_amount_cents | 4000 (€40) |
| max_extra_charge_cents | 1000 |
| max_extra_charge_pct | 0.30 |

## Cancelamento
| key | valor |
|-----|-------|
| cancel_fee_before_dispatch_cents | 100 |
| cancel_fee_after_accept_cents | 250 |
| cancel_fee_after_pickup_ratio | 1 |

## Dispatch
| key | valor |
|-----|-------|
| dispatch_offer_timeout_seconds | 40 |
| dispatch_retry_no_driver_seconds | 10 |
| dispatch_max_total_seconds_with_drivers_online | 1200 |
| dispatch_partner_confirm_extension_seconds | 600 |
| dispatch_auto_cancel_safety_seconds | 1800 |

## Tokens / wallet / referral
| key | valor |
|-----|-------|
| token_value_cents_x100 | 50 (100 tokens = €0.50) |
| token_normal_cents_value / token_partner_driver_cents_value | 50 |
| client_token_award_pct | 3 |
| wallet_hard_floor_cents | -2000 |
| wallet_cancel_hard_floor_cents / wallet_max_negative_balance_cents | -4000 |
| wallet_max_use_pct_per_order | 1 |
| wallet_split_free_pct | 0.80 |
| wallet_negative_enabled | true (alerta 90d / ação 180d) |
| referral_referrer_reward_cents / referral_invited_reward_cents | 500 |
| referral_min_first_order_cents | 2000 |
| referral_invite_expires_days | 30 |

## Reservas (extracto — 20+ chaves `reservation_*`)
prepayment 300 · bora_service 100 · partner_payout 200 · cancel_window_hours 2 ·
no_show_grace_minutes 60 · credit_expiry_days 30 · max_advance_days 60 ·
min_advance_minutes 30 · turn_time 2/4/6+ = 90/120/150 · reminders 24h/2h enabled.

## Fontes adicionais
- Para a lista completa e atual: MCP `SELECT key, value, description, category FROM platform_settings ORDER BY category, key`.
- `.claude/.ai/knowledge/business-rules/` (mapeamento setting → regra).
