/// Lado mobile do `web_checkout`: nunca é chamado.
///
/// No telemóvel o `PaymentService.processPayment` usa o PaymentSheet nativo e
/// nem sequer entra neste caminho. Isto existe só para o código compilar em
/// Android/iOS.
library;

Future<void> startWebCardCheckout({
  required String clientSecret,
  required String publishableKey,
  String label = 'Bora',
}) {
  throw UnsupportedError(
    'startWebCardCheckout só existe no browser — no telemóvel usa-se o '
    'PaymentSheet do flutter_stripe.',
  );
}
