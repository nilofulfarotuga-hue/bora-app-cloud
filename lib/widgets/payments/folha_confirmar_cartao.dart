import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../models/saved_card.dart';

/// O que o cliente escolheu na folha de confirmação do cartão guardado.
enum EscolhaDoCartao {
  /// Cobrar neste cartão.
  confirmar,

  /// Pagar com outro cartão — segue pelo formulário do Stripe, que pede os
  /// dados e mostra o valor.
  trocarDeCartao,

  /// Sair do cartão: MB Way, dinheiro, o que o ecrã oferecer.
  outroMetodo,
}

/// Folha que aparece **antes** de qualquer cobrança em cartão guardado.
///
/// ## A cicatriz (22/09/2026, iPhone do Danilo)
///
/// Ele escolheu cartão numa corrida de 5,00 € e não apareceu tela nenhuma: a
/// app foi direita a "à procura de motorista" e ele julgou que tinha corrido
/// sem pagar. Tinha pago — `pi_3UIT47GlT3R2jCYp0aRuOp5Y`, cobrado às 13:44:57.
/// O caminho do cartão guardado cria o PaymentIntent já confirmado
/// `off_session` e cobra sem folha nenhuma. Ninguém lhe mostrou o valor,
/// ninguém lhe pediu confirmação.
///
/// Por isso esta folha é obrigatória e vive dentro do `SavedCardCheckout`: se
/// vivesse em cada ecrã, mais tarde ou mais cedo um deles esquecia-se — que é
/// exactamente o que aconteceu com o `amountEur` no TVDE.
class FolhaConfirmarCartao extends StatelessWidget {
  const FolhaConfirmarCartao({
    super.key,
    required this.amountEur,
    required this.card,
  });

  final double amountEur;
  final SavedCard card;

  /// Abre a folha e devolve a escolha. Fechar arrastando para baixo conta como
  /// [EscolhaDoCartao.outroMetodo] — nunca como autorização.
  static Future<EscolhaDoCartao> mostrar(
    BuildContext context, {
    required double amountEur,
    required SavedCard card,
  }) async {
    final escolha = await showModalBottomSheet<EscolhaDoCartao>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FolhaConfirmarCartao(amountEur: amountEur, card: card),
    );
    return escolha ?? EscolhaDoCartao.outroMetodo;
  }

  String get _valorEscrito =>
      '${amountEur.toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Confirmar pagamento'.tr,
                textAlign: TextAlign.center,
                style: texto.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),

            // O valor é a peça maior da folha: é a pergunta que a folha faz.
            Text(
              'Pagar $_valorEscrito',
              textAlign: TextAlign.center,
              style: texto.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${card.prettyBrand} •••• ${card.last4}',
                      style: texto.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(card.prettyExpiry,
                      style: texto.bodySmall
                          ?.copyWith(color: const Color(0xFF6B7280))),
                ],
              ),
            ),
            const SizedBox(height: 20),

            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  Navigator.pop(context, EscolhaDoCartao.confirmar),
              child: Text('Confirmar'.tr,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  Navigator.pop(context, EscolhaDoCartao.trocarDeCartao),
              child: Text('Trocar de cartão'.tr),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, EscolhaDoCartao.outroMetodo),
              child: Text('Outro método'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
