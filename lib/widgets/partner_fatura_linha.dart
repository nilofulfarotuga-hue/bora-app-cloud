import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../services/partner_fatura_service.dart';
import '../utils/euros.dart';
import '../utils/nif_pt.dart';

/// Junto ao "Recebes", no cartão e no histórico do pedido da loja parceira
/// (28/10/2026): o que a loja fatura ao cliente e com que NIF.
///
///   Fatura ao cliente: 12,40 € (preço de balcão)
///   NIF 123 456 789 · Nome   [copiar]      ou      Consumidor final
///
/// A loja fatura os produtos; a Bora fatura o resto (entrega e taxas), cada
/// uma com o seu NIF. Textos em PT-PT. Sem dados do servidor, não mostra nada.
class PartnerFaturaLinha extends StatelessWidget {
  const PartnerFaturaLinha({super.key, required this.fatura});

  final FaturaDoPedido? fatura;

  @override
  Widget build(BuildContext context) {
    final f = fatura;
    if (f == null) return const SizedBox.shrink();
    final nome = f.nome;
    return Container(
      key: const Key('partner_fatura_linha'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fatura ao cliente: ${eur(f.valorEur)} (preço de balcão)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          if (f.temNif)
            Row(
              children: [
                Expanded(
                  child: Text(
                    nome == null
                        ? 'NIF ${formatarNif(f.nif)}'
                        : 'NIF ${formatarNif(f.nif)} · $nome',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  key: const Key('partner_fatura_copiar'),
                  tooltip: 'Copiar NIF',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: soDigitosNif(f.nif)));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('NIF copiado.')));
                  },
                ),
              ],
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 2),
              child: Text('Consumidor final', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
