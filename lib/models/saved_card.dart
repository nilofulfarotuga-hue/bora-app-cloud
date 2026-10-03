// 2026-05-14 — Stripe saved card model.
// Fonte: Edge Fn list-saved-cards (chama stripe.paymentMethods.list).

class SavedCard {
  final String id;       // pm_xxx (Stripe PaymentMethod id)
  final String brand;    // visa, mastercard, amex, ...
  final String last4;
  final int? expMonth;
  final int? expYear;
  final bool isDefault;

  const SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    this.expMonth,
    this.expYear,
    this.isDefault = false,
  });

  factory SavedCard.fromMap(Map<String, dynamic> m) => SavedCard(
        id: m['id'] as String,
        brand: (m['brand'] as String?) ?? 'card',
        last4: (m['last4'] as String?) ?? '••••',
        expMonth: m['exp_month'] as int?,
        expYear: m['exp_year'] as int?,
        isDefault: (m['is_default'] as bool?) ?? false,
      );

  String get prettyBrand {
    switch (brand.toLowerCase()) {
      case 'visa': return 'Visa';
      case 'mastercard': return 'Mastercard';
      case 'amex': return 'American Express';
      case 'discover': return 'Discover';
      case 'diners': return 'Diners';
      case 'jcb': return 'JCB';
      case 'unionpay': return 'UnionPay';
      default: return brand;
    }
  }

  String get prettyExpiry {
    if (expMonth == null || expYear == null) return '--/--';
    final mm = expMonth!.toString().padLeft(2, '0');
    final yy = (expYear! % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }
}
