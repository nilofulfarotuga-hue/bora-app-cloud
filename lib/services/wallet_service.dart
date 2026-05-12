import 'package:supabase_flutter/supabase_flutter.dart';

/// Wallet Service — wraps Supabase RPCs for client_wallets + bora_tokens.
///
/// RPCs (server-side, see migrations 20260430120000_client_wallets.sql):
///  - wallet_get_balance(p_user_id)        → JSONB { free_cents, tokens_balance, last_transactions[] }
///  - wallet_credit_refund_split(...)       → called by Edge Fn, not directly by client
///  - wallet_debit_for_order(...)           → called server-side
///  - admin_grant_wallet_free / admin_revoke_wallet_free / admin_list_wallets
class WalletService {
  WalletService._();
  static final instance = WalletService._();

  final _supa = Supabase.instance.client;

  Future<WalletBalance> getBalance({String? userId}) async {
    final res = await _supa.rpc('wallet_get_balance',
        params: {'p_user_id': userId});
    final m = (res as Map).cast<String, dynamic>();
    return WalletBalance.fromJson(m);
  }

  /// Cancel order with refund choice (Stripe vs wallet).
  ///   refundMethod: 'stripe' | 'wallet'
  Future<Map<String, dynamic>> cancelWithChoice({
    required String orderId,
    required String reason,
    required String refundMethod,
  }) async {
    final res = await _supa.functions.invoke('cancel-order-with-choice', body: {
      'order_id': orderId,
      'reason': reason,
      'refund_method': refundMethod,
    });
    if (res.status >= 400) {
      throw Exception('cancel_with_choice_failed: ${res.data}');
    }
    return (res.data as Map).cast<String, dynamic>();
  }

  // ── Admin ──────────────────────────────────────────────────────────────
  Future<List<AdminWalletRow>> adminList({
    String? search,
    int? minBalanceCents,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _supa.rpc('admin_list_wallets', params: {
      'p_search': search,
      'p_min_balance': minBalanceCents,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (res as List)
        .map((e) => AdminWalletRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> adminGrantFree({
    required String userId,
    required int amountCents,
    required String reason,
  }) async {
    await _supa.rpc('admin_grant_wallet_free', params: {
      'p_user_id': userId,
      'p_amount_cents': amountCents,
      'p_reason': reason,
    });
  }

  Future<void> adminRevokeFree({
    required String userId,
    required int amountCents,
    required String reason,
  }) async {
    await _supa.rpc('admin_revoke_wallet_free', params: {
      'p_user_id': userId,
      'p_amount_cents': amountCents,
      'p_reason': reason,
    });
  }

  /// Admin perdoa dívida do cliente (wallet < 0 → 0, INSERT forgive transaction).
  Future<int> adminForgiveDebt({
    required String userId,
    required String reason,
  }) async {
    final res = await _supa.rpc('admin_forgive_wallet_debt', params: {
      'p_user_id': userId,
      'p_reason': reason,
    });
    final m = (res as Map).cast<String, dynamic>();
    return (m['forgiven_cents'] as num).toInt();
  }

  /// BUG #1 frontend (2026-05-12) — Pagar dívida wallet standalone (sem pedido).
  ///   amountCents: mínimo = abs(dívida); pode ser mais (surplus → saldo positivo).
  ///   paymentMethod: 'card' | 'mbway'.
  ///   mbwayPhone: obrigatório se 'mbway', formato +351XXXXXXXXX.
  /// Retorna {clientSecret, paymentIntentId, mode, debt_cents, amount_cents}.
  Future<Map<String, dynamic>> payDebtStandalone({
    required int amountCents,
    required String paymentMethod,
    String? mbwayPhone,
  }) async {
    final body = <String, dynamic>{
      'amount_cents': amountCents,
      'payment_method': paymentMethod,
    };
    if (paymentMethod == 'mbway' && mbwayPhone != null) {
      body['mbway_phone'] = mbwayPhone;
    }
    final res = await _supa.functions.invoke('pay-debt-standalone', body: body);
    if (res.status >= 400) {
      throw Exception('pay_debt_standalone_failed: ${res.data}');
    }
    return (res.data as Map).cast<String, dynamic>();
  }
}

/// Constantes wallet — espelham platform_settings server-side.
/// Atualizar em conjunto com migration 20260504020000.
class WalletConstants {
  WalletConstants._();
  /// Soft cap: cliente bloqueado de criar pedidos abaixo deste saldo.
  static const int maxNegativeCents = -1000; // -€10
  /// Hard floor (CHECK constraint DB).
  static const int hardFloorCents = -2000;   // -€20
  /// Cap absoluto cents por ajuste pós-entrega.
  static const int maxExtraChargeCents = 1000; // €10
}

class WalletBalance {
  final String userId;
  final int freeCents;
  final int tokensBalance;
  final int tokenValueCentsX100;   // 1 token = N/100 cents
  final List<WalletTx> lastTransactions;

  WalletBalance({
    required this.userId,
    required this.freeCents,
    required this.tokensBalance,
    required this.tokenValueCentsX100,
    required this.lastTransactions,
  });

  /// Tokens valor em cents (não tokens × valor unitário, mas cents totais).
  int get tokensValueCents =>
      (tokensBalance * tokenValueCentsX100 / 100).round();

  /// Saldo negativo (Sessão 3B): cliente em dívida.
  bool get isNegative => freeCents < 0;
  /// Cents devidos (sempre positivo). 0 quando saldo >= 0.
  int get debtCents => freeCents < 0 ? -freeCents : 0;
  /// Cliente bloqueado de criar novos pedidos (atingiu soft cap).
  bool get isBlocked => freeCents < WalletConstants.maxNegativeCents;
  /// Aviso amarelo: passou >= 50% do soft cap mas ainda não bloqueou.
  bool get isWarning => isNegative && freeCents <= (WalletConstants.maxNegativeCents ~/ 2);

  factory WalletBalance.fromJson(Map<String, dynamic> j) => WalletBalance(
        userId: j['user_id'] as String,
        freeCents: (j['free_cents'] as num?)?.toInt() ?? 0,
        tokensBalance: (j['tokens_balance'] as num?)?.toInt() ?? 0,
        tokenValueCentsX100: (j['token_value_cents_x100'] as num?)?.toInt() ?? 5,
        lastTransactions: ((j['last_transactions'] as List?) ?? const [])
            .map((e) => WalletTx.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class WalletTx {
  final String id;
  final int amountCents;
  final String kind;
  final String reason;
  final String? relatedOrderId;
  final int? balanceAfterCents;
  final DateTime createdAt;

  WalletTx({
    required this.id,
    required this.amountCents,
    required this.kind,
    required this.reason,
    required this.relatedOrderId,
    required this.balanceAfterCents,
    required this.createdAt,
  });

  factory WalletTx.fromJson(Map<String, dynamic> j) => WalletTx(
        id: j['id'] as String,
        amountCents: (j['amount_cents'] as num).toInt(),
        kind: j['kind'] as String,
        reason: j['reason'] as String,
        relatedOrderId: j['related_order_id'] as String?,
        balanceAfterCents: (j['balance_after_cents'] as num?)?.toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  bool get isCredit => amountCents > 0;

  String get kindLabel {
    switch (kind) {
      case 'refund_credit_free':
        return 'Reembolso (saldo livre)';
      case 'refund_credit_tokens':
        return 'Reembolso (tokens)';
      case 'order_payment':
        return 'Pagamento pedido';
      case 'admin_grant':
        return 'Crédito admin';
      case 'admin_revoke':
        return 'Débito admin';
      case 'cashback':
        return 'Cashback';
      case 'referral':
        return 'Referral';
      // Sessão 3B
      case 'debit':
        return 'Débito pós-entrega';
      case 'settlement':
        return 'Liquidação dívida anterior';
      case 'adjustment':
        return 'Ajuste manual';
      case 'forgive':
        return 'Dívida perdoada';
      // BUG #1 backend (§53 — 2026-05-12)
      case 'cancel_fee_debit':
        return 'Taxa de cancelamento';
      default:
        return kind;
    }
  }
}

class AdminWalletRow {
  final String userId;
  final String email;
  final String? fullName;
  final int freeBalanceCents;
  final int tokensBalance;
  final DateTime? lastTxAt;

  AdminWalletRow({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.freeBalanceCents,
    required this.tokensBalance,
    required this.lastTxAt,
  });

  factory AdminWalletRow.fromJson(Map<String, dynamic> j) => AdminWalletRow(
        userId: j['user_id'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String?,
        freeBalanceCents: (j['free_balance_cents'] as num?)?.toInt() ?? 0,
        tokensBalance: (j['tokens_balance'] as num?)?.toInt() ?? 0,
        lastTxAt: j['last_tx_at'] != null
            ? DateTime.parse(j['last_tx_at'] as String)
            : null,
      );
}
