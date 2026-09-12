import '../models/saved_card.dart';
import 'card_wallet_service.dart';
import 'payment_biometric_gate.dart';

/// Resultado de [SavedCardCheckout.authorize].
class SavedCardAuthorization {
  const SavedCardAuthorization._(this.savedPmId, this.card, this.cancelled);

  /// Pode cobrar. [savedPmId] `null` = não há cartão guardado, o ecrã deve
  /// seguir pelo PaymentSheet como sempre fez.
  const SavedCardAuthorization.proceed(String? savedPmId, [SavedCard? card])
      : this._(savedPmId, card, false);

  /// O cliente recusou/cancelou a biometria — NÃO cobrar.
  const SavedCardAuthorization.cancelled() : this._(null, null, true);

  final String? savedPmId;
  final SavedCard? card;
  final bool cancelled;

  bool get usesSavedCard => savedPmId != null;
}

/// Passo comum a todas as verticais que cobram cartão (Carteira Única).
///
/// Resolve o cartão padrão da carteira e corre o gate biométrico **antes** de
/// qualquer chamada que cobre. Existe para o delivery, a reserva, a marcação,
/// o TVDE e a limpeza fazerem exactamente a mesma coisa — em vez de cada ecrã
/// reinventar a ordem dos passos e algum se esquecer da biometria.
///
/// Uso:
/// ```dart
/// final auth = await SavedCardCheckout.instance.authorize(amountEur: 3.0);
/// if (auth.cancelled) return;                    // não cobrar
/// final res = await criarPaymentIntent(savedPmId: auth.savedPmId);
/// if (auth.usesSavedCard) {
///   await PaymentService().confirmSavedCardPayment(...);  // 1 toque (+3DS)
/// } else {
///   ...PaymentSheet de sempre...
/// }
/// ```
class SavedCardCheckout {
  SavedCardCheckout({CardWalletService? wallet, PaymentBiometricGate? gate})
      : _wallet = wallet ?? CardWalletService.instance,
        _gate = gate ?? PaymentBiometricGate.instance;

  static final SavedCardCheckout instance = SavedCardCheckout();

  final CardWalletService _wallet;
  final PaymentBiometricGate _gate;

  /// Descobre o cartão padrão e pede digital/rosto quando é esse o caminho.
  ///
  /// [amountEur] só serve para o diálogo do sistema dizer o valor ao cliente.
  Future<SavedCardAuthorization> authorize({double? amountEur}) async {
    final card = await _wallet.defaultCard();
    final ok = await _gate.ensureAuthorized(
      usingSavedCard: card != null,
      reason: amountEur != null
          ? PaymentBiometricGate.reasonForAmount(amountEur)
          : 'Confirma o pagamento',
    );
    if (!ok) return const SavedCardAuthorization.cancelled();
    return SavedCardAuthorization.proceed(card?.id, card);
  }
}
