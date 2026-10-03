import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/tr.dart';

/// O que está a ser comprado — decide a frase sobre o direito de livre
/// resolução (Decreto-Lei 24/2014, contratos à distância).
enum CheckoutLegalKind {
  /// Restaurante, loja, mercado, farmácia, takeaway: alimentos e outros bens
  /// perecíveis entregues, produtos abertos ou personalizados ficam de fora.
  comida,

  /// Serviço a pedido (favor, leva compras, envio, limpeza, lavagem): há 14
  /// dias até o serviço começar; iniciado com acordo, deixa de haver resolução.
  servico,

  /// Reserva ou marcação para uma data certa (mesa, cabeleireiro, corrida
  /// agendada): o art. 17.º exclui a livre resolução.
  marcacao,

  /// Corrida imediata: o serviço começa já, com o acordo do cliente.
  entrega,
}

/// Página dos termos que o link "Termos" abre.
const String kCheckoutTermsUrl = 'https://boraguarda.com/termos';

/// Frase legal de cada tipo (PT-PT). Função pura de propósito: o texto é o
/// que o cliente lê e o que a lei exige, por isso tem de ser provável em teste.
String checkoutLegalText(CheckoutLegalKind kind) => switch (kind) {
      CheckoutLegalKind.comida =>
        'Ao confirmar, fazes uma encomenda com obrigação de pagar. Tens 14 dias de livre resolução, exceto para alimentos, bebidas e outros bens perecíveis entregues, produtos abertos ou personalizados e serviços já prestados (DL 24/2014).'
            .tr,
      CheckoutLegalKind.servico =>
        'Ao confirmar, fazes um pedido de serviço com obrigação de pagar. Tens 14 dias de livre resolução até o serviço começar; depois de iniciado com o teu acordo, não há direito de resolução (DL 24/2014).'
            .tr,
      CheckoutLegalKind.marcacao =>
        'Ao confirmar, fazes uma marcação com obrigação de pagar para uma data certa. Não há direito de livre resolução em serviços com data marcada; aplicam-se as regras de cancelamento indicadas acima (DL 24/2014, art. 17.º).'
            .tr,
      CheckoutLegalKind.entrega =>
        'Ao confirmar, pedes uma corrida com obrigação de pagar. O serviço começa de imediato com o teu acordo, pelo que não há direito de livre resolução (DL 24/2014).'
            .tr,
    };

/// Aviso legal do checkout (DL 24/2014, art. 4.º e 5.º) — ronda-fecho
/// 2026-09-22, bloco D2.
///
/// Vai IMEDIATAMENTE acima do botão final de cada checkout, e esse botão tem
/// de dizer "Encomenda com obrigação de pagar" (art. 5.º, n.º 2). Texto
/// pequeno e cinzento, sem caixa, centrado, com o link "Termos" no fim.
///
/// Não é checkbox: o consentimento dá-se ao carregar no botão — a mesma
/// lógica do `CardMandateNotice`, para não pôr mais um obstáculo a quem já
/// decidiu comprar.
class CheckoutLegalNotice extends StatefulWidget {
  const CheckoutLegalNotice({super.key, required this.kind, this.openUrl});

  final CheckoutLegalKind kind;

  /// Injectável para testes; em produção abre o navegador externo.
  final Future<void> Function(Uri uri)? openUrl;

  @override
  State<CheckoutLegalNotice> createState() => _CheckoutLegalNoticeState();
}

class _CheckoutLegalNoticeState extends State<CheckoutLegalNotice> {
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = _openTerms;

  Future<void> _openTerms() async {
    final uri = Uri.parse(kCheckoutTermsUrl);
    final open = widget.openUrl;
    if (open != null) {
      await open(uri);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 12,
      height: 1.3,
      color: Colors.grey.shade700,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: checkoutLegalText(widget.kind)),
          const TextSpan(text: ' '),
          TextSpan(
            text: 'Termos'.tr,
            style: base.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: _termsTap,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
