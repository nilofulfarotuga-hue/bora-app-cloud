/// BORA — Business Rules Constants
/// Source of truth: .claude/.ai/business_rules.md
/// DO NOT modify values without updating business_rules.md first.

// ignore_for_file: constant_identifier_names

abstract final class BRSla {
  /// Base SLA from order accepted (minutes)
  static const int SLA_BASE_MINUTES = 10;

  /// Automatic check point for proximity evaluation (minutes)
  static const int SLA_CHECK_AT_MINUTES = 7;

  /// Maximum automatic extension when driver is near enough (minutes)
  static const int SLA_MAX_EXTENSION_MINUTES = 5;
}

abstract final class BRProximity {
  /// Driver is considered "near enough" if distance ≤ this value (metres)
  static const int NEAR_ENOUGH_DISTANCE_METERS = 500;

  /// Driver is considered "near enough" if ETA ≤ this value (minutes)
  static const int NEAR_ENOUGH_ETA_MINUTES = 2;
}

abstract final class BRQueue {
  /// Radius of the local FIFO queue (Regime A) in metres
  static const int LOCAL_QUEUE_RADIUS_METERS = 200;

  /// Minimum time driver must remain inside radius to join queue (seconds)
  static const int LOCAL_QUEUE_DWELL_SECONDS = 5;
}

abstract final class BRBatching {
  /// Maximum pickup distance for batch candidates (km)
  static const double BATCHING_RADIUS_KM = 15.0;

  /// Time window to collect batch candidates (minutes)
  static const int BATCHING_WAIT_WINDOW_MINUTES = 3;

  /// Combined route must be faster than sum of individual routes × this ratio
  static const double BATCHING_TIME_TOLERANCE = 1.20;
}

abstract final class BRTokens {
  /// Maximum fraction of order total that can be paid with tokens
  static const double TOKEN_MAX_DISCOUNT_RATIO = 0.50;

  /// Euro value of one token (100 tokens = 0.50 €)
  static const double TOKEN_VALUE_EUR = 0.005;

  /// Token expiry in days (FIFO consumption order)
  static const int TOKEN_EXPIRY_DAYS = 60;
}

abstract final class BRDriver {
  /// Fixed cost charged by principal driver to helper (Driver Help, internal)
  static const double DRIVER_HELP_COST_EUR = 4.00;

  /// Fixed bonus for driver accepting an additional order
  static const double DRIVER_ADDITIONAL_ORDER_BONUS_EUR = 3.00;

  /// Fixed token bonus for driver accepting an additional order
  static const int DRIVER_ADDITIONAL_ORDER_TOKENS = 50;

  /// Tokens earned per euro of driver earnings on a delivery
  static const int DRIVER_TOKENS_PER_EUR = 10;
}

abstract final class BRFees {
  /// Fee charged when driver arrives at wrong address
  static const double WRONG_ADDRESS_FEE_EUR = 2.00;

  /// Cancellation fee before dispatch starts
  static const double CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.50;

  /// Cancellation fee after driver accepted (ratio of order total)
  static const double CANCEL_FEE_AFTER_ACCEPT_RATIO = 0.50;

  /// Cancellation fee after purchase started (ratio of order total)
  static const double CANCEL_FEE_AFTER_PURCHASE_RATIO = 1.00;
}

abstract final class BRBusiness {
  /// Direct commission charged to partner per order
  static const double PARTNER_COMMISSION_RATIO = 0.10;

  /// Additional platform fee on product value (hybrid model)
  static const double PLATFORM_SERVICE_FEE_RATIO = 0.05;

  /// Additional margin on product listing (hybrid model)
  static const double PRODUCT_MARGIN_RATIO = 0.05;

  // Total platform revenue ≈ 0.20 (0.10 + 0.05 + 0.05) — implicit, no constant needed

  /// Invisible markup applied at product registration for non-partner stores
  static const double NON_PARTNER_MARKUP_RATIO = 0.15;

  /// Maximum order total (EUR) accepted with payment_method = 'cash'.
  /// Above this threshold the cash option MUST be hidden/disabled. The
  /// database trigger `enforce_cash_payment_limit` enforces the same rule
  /// server-side — client validation is UX only.
  static const double CASH_MAX_ORDER_VALUE_EUR = 30.00;
}
