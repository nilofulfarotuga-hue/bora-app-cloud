import 'package:flutter/foundation.dart';

import 'biometric_auth_service.dart';

/// Gate biométrico do pagamento (Carteira Única, Parte 2/6).
///
/// Pagar com cartão guardado é um toque só: não há PaymentSheet, não há CVV,
/// não há nada entre o botão e a cobrança. Por isso pedimos digital/rosto
/// **antes** de cobrar, como fazem as apps de banca.
///
/// Regras deliberadas:
/// - Só vale para cartão **guardado**. Com cartão novo o PaymentSheet já obriga
///   a introduzir os dados, que é prova suficiente.
/// - Aparelho **sem** biometria configurada passa à frente. Um cliente sem
///   digital registada não pode ficar impedido de comprar.
/// - Na web não há `local_auth` — passa à frente.
///
/// Injecção de funções (e não do [BiometricAuthService]) porque esse serviço
/// tem construtor privado e não é subclassável a partir dos testes.
class PaymentBiometricGate {
  PaymentBiometricGate({
    Future<bool> Function()? isCapable,
    Future<bool> Function(String reason)? authenticate,
    bool? isWeb,
  })  : _isCapable = isCapable ?? (() => BiometricAuthService.instance.isDeviceCapable),
        _authenticate =
            authenticate ?? BiometricAuthService.instance.authenticate,
        _isWeb = isWeb ?? kIsWeb;

  static final PaymentBiometricGate instance = PaymentBiometricGate();

  final Future<bool> Function() _isCapable;
  final Future<bool> Function(String reason) _authenticate;
  final bool _isWeb;

  /// `true` = pode cobrar. `false` = o cliente cancelou ou falhou a biometria.
  ///
  /// [reason] é o texto que o Android/iOS mostra no diálogo do sistema — deve
  /// dizer o valor, para o cliente saber ao que está a autorizar.
  Future<bool> ensureAuthorized({
    required bool usingSavedCard,
    String reason = 'Confirma o pagamento',
  }) async {
    if (!usingSavedCard) return true;
    if (_isWeb) return true;
    if (!await _isCapable()) return true;
    return _authenticate(reason);
  }

  /// Texto para o diálogo do sistema, já com o valor: "Confirma o pagamento de
  /// €12,40". Mantém-se aqui para as Partes 3 e 4 escreverem o mesmo.
  static String reasonForAmount(double amount) =>
      'Confirma o pagamento de €${amount.toStringAsFixed(2).replaceAll('.', ',')}';
}
