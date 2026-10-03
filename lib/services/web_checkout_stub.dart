/// Lado mobile do `web_checkout`: nunca é chamado.
///
/// No telemóvel o `PaymentService.processPayment` usa o PaymentSheet nativo e
/// nem sequer entra neste caminho. Isto existe só para o código compilar em
/// Android/iOS.
library;

/// Espelho de `PagamentoWebPendente` do lado web. No telemóvel nunca existe
/// nenhum — a app não sai da página a meio de um pagamento.
class PagamentoWebPendente {
  const PagamentoWebPendente({
    required this.vertical,
    required this.clientSecret,
    required this.rotaRegresso,
    required this.criadoEm,
    this.referenciaId,
    this.paymentIntentId,
  });

  final String vertical;
  final String clientSecret;
  final String rotaRegresso;
  final DateTime criadoEm;
  final String? referenciaId;
  final String? paymentIntentId;

  bool get expirado => false;
}

Future<void> startWebCardCheckout({
  required String clientSecret,
  required String publishableKey,
  String label = 'Bora',
  String vertical = 'desconhecida',
  String? referenciaId,
  String? paymentIntentId,
}) {
  throw UnsupportedError(
    'startWebCardCheckout só existe no browser — no telemóvel usa-se o '
    'PaymentSheet do flutter_stripe.',
  );
}

/// No telemóvel nunca há pagamento pendente por retomar.
PagamentoWebPendente? lerPagamentoWebPendente() => null;

void limparPagamentoWebPendente() {}
