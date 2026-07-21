import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/card_wallet_service.dart';

/// Frase de mandato (consentimento PSD2) — Carteira Única, Parte 5/6.
///
/// As Edge Functions guardam o cartão no Stripe Customer com
/// `setup_future_usage: 'off_session'`. Guardar um meio de pagamento exige
/// consentimento informado e explícito do cliente: ele tem de saber **antes**
/// que o cartão vai ficar guardado, para que serve e como o tira de lá.
///
/// Aparece só quando ainda **não** há cartão guardado — ou seja, quando este
/// pagamento é o que vai guardar o primeiro. Depois disso desaparece sozinho,
/// para não virar ruído em todas as compras.
///
/// Deliberadamente não é um checkbox: o consentimento é dado ao continuar o
/// pagamento, e um checkbox obrigatório a mais no checkout só faz desistir
/// quem já decidiu comprar. O texto diz o que acontece, em PT-PT simples.
class CardMandateNotice extends StatefulWidget {
  const CardMandateNotice({super.key, this.wallet});

  /// Injectável para testes; em produção usa o singleton.
  final CardWalletService? wallet;

  @override
  State<CardMandateNotice> createState() => _CardMandateNoticeState();
}

class _CardMandateNoticeState extends State<CardMandateNotice> {
  /// `null` enquanto carrega — não mostramos nada até saber, para a frase não
  /// piscar no ecrã de quem já tem cartão guardado.
  bool? _isFirstCard;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final card =
        await (widget.wallet ?? CardWalletService.instance).defaultCard();
    if (!mounted) return;
    setState(() => _isFirstCard = card == null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isFirstCard != true) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              mandateText,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Texto do mandato. Constante (e não literal espalhado) para ser o MESMO nas
/// cinco verticais — um consentimento que muda de palavras conforme o ecrã não
/// é um consentimento fiável.
const String mandateText =
    'Ao pagar, autorizas o Bora a guardar este cartão para pagares num toque '
    'nas próximas compras. Cada pagamento continua a ser confirmado por ti na '
    'app. Podes remover o cartão quando quiseres em Perfil › Meus Cartões.';
