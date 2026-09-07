import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

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
