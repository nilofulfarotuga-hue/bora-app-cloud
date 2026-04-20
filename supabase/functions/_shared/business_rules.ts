/**
 * BORA — Business Rules Constants
 * Source of truth: .claude/.ai/business_rules.md
 * DO NOT modify values without updating business_rules.md first.
 */

// SLA
export const SLA_BASE_MINUTES = 10 as const;
export const SLA_CHECK_AT_MINUTES = 7 as const;
export const SLA_MAX_EXTENSION_MINUTES = 5 as const;

// PROXIMITY
export const NEAR_ENOUGH_DISTANCE_METERS = 500 as const;
export const NEAR_ENOUGH_ETA_MINUTES = 2 as const;

// QUEUE
export const LOCAL_QUEUE_RADIUS_METERS = 200 as const;
export const LOCAL_QUEUE_DWELL_SECONDS = 5 as const;

// BATCHING
export const BATCHING_RADIUS_KM = 15 as const;
export const BATCHING_WAIT_WINDOW_MINUTES = 3 as const;
export const BATCHING_TIME_TOLERANCE = 1.20 as const;

// TOKENS
export const TOKEN_MAX_DISCOUNT_RATIO = 0.50 as const;
export const TOKEN_VALUE_EUR = 0.005 as const;
export const TOKEN_EXPIRY_DAYS = 60 as const;

// DRIVER
export const DRIVER_HELP_COST_EUR = 4.00 as const;
export const DRIVER_ADDITIONAL_ORDER_BONUS_EUR = 3.00 as const;
export const DRIVER_ADDITIONAL_ORDER_TOKENS = 50 as const;

// FEES
export const WRONG_ADDRESS_FEE_EUR = 2.00 as const;
// Client cancel fees (BR §8.3) — aligned with business_rules.md v2 source of truth
export const CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.00 as const;
export const CANCEL_FEE_AFTER_ACCEPT_EUR = 2.50 as const;
export const CANCEL_FEE_AFTER_PURCHASE_RATIO = 1.00 as const;

// BUSINESS
/** Direct commission charged to partner per order */
export const PARTNER_COMMISSION_RATIO = 0.10 as const;

/** Additional platform fee on product value (hybrid model) */
export const PLATFORM_SERVICE_FEE_RATIO = 0.05 as const;

/** Additional margin on product listing (hybrid model) */
export const PRODUCT_MARGIN_RATIO = 0.05 as const;

// Total platform revenue ≈ 0.20 (0.10 + 0.05 + 0.05) — implicit, no constant needed

export const NON_PARTNER_MARKUP_RATIO = 0.15 as const;

/**
 * Maximum order total (EUR) accepted with payment_method = 'cash'.
 * Enforced server-side by the `enforce_cash_payment_limit` DB trigger.
 */
export const CASH_MAX_ORDER_VALUE_EUR = 30.00 as const;
