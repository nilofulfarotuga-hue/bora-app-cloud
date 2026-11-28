// "Nunca beco sem saída" (09/11/2026, missão m11 — adendo 2, parte A).
// Quando a pesquisa não acha nada: "Não encontrei X aqui" e um botão
// "Pede ao Amigo", que abre o Amigo já com o pedido escrito — ele procura
// noutras lojas ou propõe um Favor. Usado dentro das lojas (mercados,
// restaurantes, farmácias) e na lupa da home.
//
// 18/11/2026 (farmacia-peca-aqui, regra do Danilo "primeiro é o parceiro"):
// numa farmácia parceira que recebe pedidos (o mesmo critério dos botões do
// topo, `farmacia_botoes_visiveis`) e está aberta, aparece PRIMEIRO o botão
// verde "Pedir à {farmácia}" — abre o "Não encontra o produto? Peça aqui" com
// o termo já escrito. O Amigo fica por baixo, como segunda opção.

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../screens/client/assistant/amigo_bora_entrada.dart' show abrirAmigo;
import '../screens/farmacia/prescricao_enviar_screen.dart';
import '../services/assistant_service.dart';

/// A farmácia parceira a quem se pode pedir o que não está no catálogo.
class FarmaciaDaPesquisa {
  const FarmaciaDaPesquisa({required this.restaurantId, required this.nome});
  final String restaurantId;
  final String nome;
}

class PesquisaSemResultado extends StatelessWidget {
  const PesquisaSemResultado({
    super.key,
    required this.termo,
    this.loja,
    this.aoPedirAoAmigo,
    this.extra,
    this.farmacia,
    this.aoPedirAFarmacia,
  });

  /// O que o cliente escreveu.
  final String termo;

  /// Nome da loja (nulo na lupa da home).
  final String? loja;

  /// Trocável nos testes; por defeito abre o Amigo com a mensagem.
  final void Function(String mensagem)? aoPedirAoAmigo;

  /// Algo mais por baixo (ex.: sugestões de pesquisa na lupa).
  final Widget? extra;

  /// Farmácia parceira aberta que recebe pedidos especiais. Nulo = só o Amigo.
  final FarmaciaDaPesquisa? farmacia;

  /// Trocável nos testes; por defeito abre o PedidoLivreScreen com o termo.
  final void Function(FarmaciaDaPesquisa farmacia, String termo)? aoPedirAFarmacia;

  /// A mensagem que o Amigo recebe já escrita.
  static String mensagemParaAmigo(String termo, String? loja, {bool farmacia = false}) {
    final t = termo.trim();
    final l = (loja ?? '').trim();
    if (farmacia && l.isNotEmpty) {
      return 'Não encontrei "{0}" na {1}. Ajuda-me a pedir à farmácia ou diz-me onde mais há.'
          .trArgs([t, l]);
    }
    return l.isEmpty
        ? 'Não encontrei "{0}" na Bora. Procura noutras lojas ou propõe-me um Favor.'.trArgs([t])
        : 'Não encontrei "{0}" em {1}. Procura noutras lojas ou propõe-me um Favor.'.trArgs([t, l]);
  }

  void _pedirAFarmacia(BuildContext context, FarmaciaDaPesquisa f, String t) {
    final cb = aoPedirAFarmacia;
    if (cb != null) return cb(f, t);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PedidoLivreScreen(
        restaurantId: f.restaurantId,
        farmaciaNome: f.nome,
        descricaoInicial: t,
      ),
    ));
  }

  void _pedirAoAmigo(BuildContext context, String t) {
    final m = mensagemParaAmigo(t, farmacia?.nome ?? loja, farmacia: farmacia != null);
    final f = aoPedirAoAmigo;
    if (f != null) {
      f(m);
    } else {
      abrirAmigo(context, mensagem: m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = termo.trim();
    final aqui = (loja ?? '').trim().isNotEmpty || farmacia != null;
    final f = farmacia;
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
        if (f != null) ...[
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              key: const Key('pedir-a-farmacia'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              onPressed: () => _pedirAFarmacia(context, f, t),
              icon: const Icon(Icons.local_pharmacy_outlined, size: 22),
              label: Text(
                'Pedir à {0}'.trArgs([f.nome]),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A farmácia confirma se tem e o preço. Só pagas depois de confirmar.'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
        ValueListenableBuilder<bool>(
          valueListenable: AssistantFlags.enabled,
          builder: (context, ligado, _) {
            if (!ligado) {
              if (f != null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Experimenta outra palavra.'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              );
            }
            if (f != null) {
              // Segunda opção, por baixo do pedido à farmácia.
              return Padding(
                padding: const EdgeInsets.only(top: 20),
                child: OutlinedButton.icon(
                  key: const Key('pede-ao-amigo'),
                  onPressed: () => _pedirAoAmigo(context, t),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('Pede ao Amigo'.tr),
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
                  onPressed: () => _pedirAoAmigo(context, t),
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
