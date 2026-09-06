import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/cart_screen.dart';

/// Confirmação compacta e não-bloqueante de "adicionado ao carrinho"
/// (padrão Uber Eats / Glovo).
///
/// Uma única linha (com reticências), flutuante junto ao fundo, fundo verde
/// da marca com ícone de check. Tocar apenas confirma; NUNCA navega
/// automaticamente para o pagamento. A ação "Ver" leva ao carrinho.
///
/// ── Porque é que este ficheiro tem um Timer próprio (2026-08-25) ──────────
/// O Danilo apanhou no telemóvel a faixa verde presa no ecrã, a tapar os
/// produtos. Causa-raiz no próprio Flutter (`scaffold.dart`, ScaffoldMessenger
/// .build): o temporizador que fecha o SnackBar só é criado num rebuild em que
/// `route.isCurrent` ainda é verdade. Quando o cliente navega logo a seguir a
/// adicionar (é o que a ficha do produto passou a fazer), esse rebuild nunca
/// acontece com a rota original em cima — e o `duration` do SnackBar nunca
/// chega a ser armado. Resultado: faixa eterna.
///
/// Por isso a saída NÃO depende do temporizador interno: armamos o nosso, que
/// vive no ScaffoldMessenger (global) e fecha o aviso aos [_kDuracao] mesmo
/// que a rota mude, que não haja rebuild, ou que o telemóvel tenha um serviço
/// de acessibilidade ligado.
const Duration _kDuracao = Duration(seconds: 2);

/// Espaço reservado no fundo para a barra "Ver carrinho · €X" e para as ações
/// fixas dos ecrãs de produto — o aviso fica ACIMA delas, nunca por cima.
const double _kAlturaBarraCarrinho = 104;

Timer? _timer;

void showAddedToCartSnack(
  BuildContext context,
  String message, {
  VoidCallback? onView,
}) {
  final messenger = ScaffoldMessenger.of(context);
  // Capturado ANTES de qualquer navegação: o "Ver" continua a funcionar mesmo
  // depois de a ficha do produto se fechar (o widget que chamou já não existe,
  // mas o NavigatorState continua vivo).
  final navigator = Navigator.of(context);
  final abaixo = MediaQuery.viewPaddingOf(context).bottom;

  _timer?.cancel();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: _kDuracao,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: _kAlturaBarraCarrinho + abaixo,
          left: 16,
          right: 16,
        ),
        dismissDirection: DismissDirection.horizontal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: onView ??
              () => navigator.push(
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  ),
        ),
      ),
    );

  // A rede de segurança: fecha aos 2s aconteça o que acontecer.
  _timer = Timer(_kDuracao, () {
    messenger.hideCurrentSnackBar();
    _timer = null;
  });
}

/// Fecha a ficha do produto depois de adicionar (2026-08-25).
///
/// Regra do Danilo: adicionar fecha a ficha e devolve o cliente ao menu da
/// loja, com o aviso por cima e a barra do carrinho já com o total novo — é
/// essa barra a confirmação permanente. Vale para TODAS as fichas, com ou sem
/// opções obrigatórias (quando faltam opções o botão nem sequer chama isto).
void fecharFichaAposAdicionar(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) navigator.pop();
}
