import 'package:flutter/widgets.dart';

import '../models/saved_card.dart';
import '../widgets/payments/folha_confirmar_cartao.dart';
import 'card_wallet_service.dart';
import 'payment_biometric_gate.dart';

/// Resultado de [SavedCardCheckout.authorize].
class SavedCardAuthorization {
  const SavedCardAuthorization._(this.savedPmId, this.card, this.cancelled);

  /// Pode cobrar. [savedPmId] `null` = não há cartão guardado (ou o cliente
  /// pediu para trocar), o ecrã deve seguir pelo PaymentSheet como sempre fez.
  const SavedCardAuthorization.proceed(String? savedPmId, [SavedCard? card])
      : this._(savedPmId, card, false);

  /// O cliente recusou/cancelou — NÃO cobrar.
  const SavedCardAuthorization.cancelled() : this._(null, null, true);

  final String? savedPmId;
  final SavedCard? card;
  final bool cancelled;

  bool get usesSavedCard => savedPmId != null;
}

/// Passo comum a todas as verticais que cobram cartão (Carteira Única).
///
/// Resolve o cartão padrão, **mostra a folha de confirmação** e corre o gate
/// biométrico — tudo antes de qualquer chamada que cobre. Existe para o
/// delivery, a reserva, a marcação, o TVDE e a limpeza fazerem exactamente a
/// mesma coisa, em vez de cada ecrã reinventar a ordem dos passos e algum se
/// esquecer de um.
///
/// ## Porque é que a folha vive aqui (cicatriz de 22/09/2026)
///
/// Com cartão guardado o PaymentIntent nasce já confirmado `off_session`: não
/// há PaymentSheet, não há CVV, não há nada entre o botão e a cobrança. A 22/09
/// o Danilo pagou 5,00 € numa corrida sem ver ecrã nenhum e julgou que tinha
/// corrido de graça. Agora há sempre um "Confirmar" humano com o valor à
/// frente.
///
/// A mesma data deu a segunda lição: o TVDE chamava `authorize()` **sem**
/// `amountEur`, e por isso até o diálogo do sistema saía seco ("Confirma o
/// pagamento"). Por isso [amountEur] passou a ser **obrigatório** — esquecê-lo
/// deixou de compilar.
///
/// Uso:
/// ```dart
/// final auth = await SavedCardCheckout.instance
///     .authorize(context: context, amountEur: 3.0);
/// if (auth.cancelled) return;                    // não cobrar
/// final res = await criarPaymentIntent(savedPmId: auth.savedPmId);
/// if (auth.usesSavedCard) {
///   await PaymentService().confirmSavedCardPayment(...);  // 1 toque (+3DS)
/// } else {
///   ...PaymentSheet de sempre...
/// }
/// ```
class SavedCardCheckout {
  SavedCardCheckout({
    CardWalletService? wallet,
    PaymentBiometricGate? gate,
    Future<EscolhaDoCartao> Function(
      BuildContext context, {
      required double amountEur,
      required SavedCard card,
    })? confirmar,
  })  : _wallet = wallet ?? CardWalletService.instance,
        _gate = gate ?? PaymentBiometricGate.instance,
        _confirmar = confirmar ?? FolhaConfirmarCartao.mostrar;

  static final SavedCardCheckout instance = SavedCardCheckout();

  final CardWalletService _wallet;
  final PaymentBiometricGate _gate;

  /// Injectável só para os testes poderem correr sem árvore de widgets.
  final Future<EscolhaDoCartao> Function(
    BuildContext context, {
    required double amountEur,
    required SavedCard card,
  }) _confirmar;

  /// Descobre o cartão padrão, pede confirmação ao cliente e só depois
  /// digital/rosto.
  ///
  /// [amountEur] é o que vai ser cobrado — aparece na folha e no diálogo do
  /// sistema. É obrigatório de propósito (ver o docstring da classe).
  Future<SavedCardAuthorization> authorize({
    required BuildContext context,
    required double amountEur,
  }) async {
    final card = await _wallet.defaultCard();

    // Sem cartão guardado nada muda: o PaymentSheet do Stripe já mostra o
    // valor e já obriga a introduzir os dados, que é confirmação suficiente.
    if (card == null) return const SavedCardAuthorization.proceed(null);

    if (!context.mounted) return const SavedCardAuthorization.cancelled();
    final escolha =
        await _confirmar(context, amountEur: amountEur, card: card);

    switch (escolha) {
      case EscolhaDoCartao.outroMetodo:
        return const SavedCardAuthorization.cancelled();
      case EscolhaDoCartao.trocarDeCartao:
        // Segue pelo PaymentSheet com cartão novo — sem `savedPmId`, e sem
        // biometria (introduzir o cartão é prova bastante).
        return const SavedCardAuthorization.proceed(null);
      case EscolhaDoCartao.confirmar:
        break;
    }

    final ok = await _gate.ensureAuthorized(
      usingSavedCard: true,
      reason: PaymentBiometricGate.reasonForAmount(amountEur),
    );
    if (!ok) return const SavedCardAuthorization.cancelled();
    return SavedCardAuthorization.proceed(card.id, card);
  }
}
