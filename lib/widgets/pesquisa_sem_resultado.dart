// "Nunca beco sem saída" (09/11/2026, missão m11 — adendo 2, parte A).
// Quando a pesquisa não acha nada: "Não encontrei X aqui" e um botão
// "Pede ao Amigo", que abre o Amigo já com o pedido escrito — ele procura
// noutras lojas ou propõe um Favor. Usado dentro das lojas (mercados,
// restaurantes, farmácias) e na lupa da home.

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../screens/client/assistant/amigo_bora_entrada.dart' show abrirAmigo;
import '../services/assistant_service.dart';

class PesquisaSemResultado extends StatelessWidget {
  const PesquisaSemResultado({
    super.key,
    required this.termo,
    this.loja,
    this.aoPedirAoAmigo,
    this.extra,
  });

  /// O que o cliente escreveu.
  final String termo;

  /// Nome da loja (nulo na lupa da home).
  final String? loja;

  /// Trocável nos testes; por defeito abre o Amigo com a mensagem.
  final void Function(String mensagem)? aoPedirAoAmigo;

  /// Algo mais por baixo (ex.: sugestões de pesquisa na lupa).
  final Widget? extra;

  /// A mensagem que o Amigo recebe já escrita.
  static String mensagemParaAmigo(String termo, String? loja) {
    final t = termo.trim();
    final l = (loja ?? '').trim();
    return l.isEmpty
        ? 'Não encontrei "{0}" na Bora. Procura noutras lojas ou propõe-me um Favor.'.trArgs([t])
        : 'Não encontrei "{0}" em {1}. Procura noutras lojas ou propõe-me um Favor.'.trArgs([t, l]);
  }

  @override
  Widget build(BuildContext context) {
    final t = termo.trim();
    final aqui = (loja ?? '').trim().isNotEmpty;
    return ListView(
      key: const Key('pesquisa-sem-resultado'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
      children: [
        Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          aqui ? 'Não encontrei "{0}" aqui.'.trArgs([t]) : 'Não encontrei "{0}".'.trArgs([t]),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: AssistantFlags.enabled,
          builder: (context, ligado, _) {
            if (!ligado) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Experimenta outra palavra.'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              );
            }
            return Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  'O Amigo procura noutras lojas ou trata disso num Favor.'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('pede-ao-amigo'),
                  onPressed: () {
                    final m = mensagemParaAmigo(t, loja);
                    final f = aoPedirAoAmigo;
                    if (f != null) {
                      f(m);
                    } else {
                      abrirAmigo(context, mensagem: m);
                    }
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('Pede ao Amigo'.tr),
                ),
              ],
            );
          },
        ),
        if (extra != null) ...[
          const SizedBox(height: 20),
          Center(child: extra!),
        ],
      ],
    );
  }
}
