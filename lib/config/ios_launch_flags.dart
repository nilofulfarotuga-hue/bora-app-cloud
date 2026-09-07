import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Interruptores da primeira versão iOS (missão `ios-lancamento`, 2026-09-07).
///
/// O Android e a web não mudam de comportamento: tudo aqui só actua quando a
/// plataforma corrente é iOS.

/// Apple Pay fica DESLIGADO na v1 iOS.
///
/// O `PaymentSheet` já pede Apple Pay em 6 sítios (`Stripe.merchantIdentifier`
/// está definido em `main.dart`), mas mostrar o botão sem Merchant ID e sem
/// certificado Apple Pay emitidos dá um botão que falha — reprovação 2.1 na
/// revisão da App Store. Fica para a v1.1, quando a conta de programador
/// existir e o Merchant ID estiver criado.
///
/// Ligar com `--dart-define=APPLE_PAY_ENABLED=true` depois de o certificado
/// estar emitido e testado.
const bool applePayEnabled = bool.fromEnvironment('APPLE_PAY_ENABLED');

/// `defaultTargetPlatform` em vez de `Platform.isIOS`: `dart:io` não existe na
/// web, e este ficheiro é importado por ecrãs que também correm na web.
bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

/// Configuração de Apple Pay a passar ao `PaymentSheet`.
///
/// Devolve `null` no iOS enquanto o Apple Pay não estiver aprovado — o Stripe
/// simplesmente não desenha o botão. Fora do iOS mantém-se o que já existia
/// (no Android o Stripe ignora este campo).
PaymentSheetApplePay? get boraApplePay =>
    (_isIOS && !applePayEnabled)
        ? null
        : const PaymentSheetApplePay(merchantCountryCode: 'PT');

/// Interruptor 5.2.1 (missão `ios-lancamento`, 2026-09-07) —
/// `platform_settings.ios_hide_nonpartner_logos`.
///
/// Todos os mercados (Continente, Auchan, Lidl…) são NÃO-parceiros e os seus
/// logótipos vêm de crawlers — a Bora não tem acordo de marca com eles. No
/// Android está assim há meses sem reclamação, mas a revisão da Apple é mais
/// estrita com uso de marca registada de terceiros sem parceria formal
/// (Guideline 5.2.1). Nasceu DESLIGADO em `platform_settings`; só passa a
/// esconder depois de [carregarIosHideNonPartnerLogos] ler `true` do servidor
/// — sem leitura (offline, erro), o estado seguro é mostrar o logótipo, igual
/// ao que já acontece hoje.
bool _hideNonPartnerLogos = false;
bool _hideNonPartnerLogosCarregado = false;

/// Esconder o logótipo desta loja nesta sessão? Só no iOS, só com o
/// interruptor ligado no servidor, e nunca para uma loja parceira.
bool shouldHideStoreLogo({required bool isPartner}) =>
    _isIOS && _hideNonPartnerLogos && !isPartner;

/// Lê o interruptor uma vez por sessão. Idempotente — repetir não custa nada.
Future<void> carregarIosHideNonPartnerLogos({bool forcar = false}) async {
  if (_hideNonPartnerLogosCarregado && !forcar) return;
  if (!_isIOS) {
    _hideNonPartnerLogosCarregado = true;
    return;
  }
  try {
    final linha = await Supabase.instance.client
        .from('platform_settings')
        .select('value')
        .eq('key', 'ios_hide_nonpartner_logos')
        .maybeSingle();
    final v = linha?['value'];
    _hideNonPartnerLogos = v is bool ? v : '$v'.toLowerCase() == 'true';
    _hideNonPartnerLogosCarregado = true;
  } catch (e) {
    debugPrint('[ios_launch_flags] falhou a ler ios_hide_nonpartner_logos: $e');
  }
}
