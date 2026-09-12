/// Checkout com cartão no browser.
///
/// No telemóvel o pagamento com cartão é o PaymentSheet nativo do
/// `flutter_stripe`. No browser esse PaymentSheet não é fiável (ainda menos no
/// Safari do iPhone, que é o alvo principal), por isso a web usa o **Payment
/// Element do Stripe.js** numa página leve própria (`web/pay.html`).
///
/// Ponto crítico do desenho: a assinatura é a mesma nos dois lados — um
/// `Future` que **completa em sucesso e lança em cancelamento/recusa**. Isso
/// mantém os 9 call-sites de `processPayment` exatamente como estão, com todo
/// o trabalho pós-pagamento a correr a seguir tal como no telemóvel.
///
/// O PaymentIntent é o **mesmo** que o telemóvel usa (criado server-side pelas
/// Edge Functions com o preço fechado), logo o `stripe-webhook` recebe o mesmo
/// evento e os refunds/cancelamentos funcionam iguais. Nenhuma Edge Function
/// foi alterada para isto.
library;

export 'web_checkout_stub.dart'
    if (dart.library.js_interop) 'web_checkout_web.dart';
