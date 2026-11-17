// Botões no topo da loja: "Imprimir documentos" e "Personalizados" (missão a3-guarda-16-11, parte 2).
// Só aparecem se a loja tiver o serviço ligado (impressao_lojas, que a RLS esconde a quem não pode
// ver a loja). Sem resposta do servidor = não aparece nada. Molde: FarmaciaBotoesTopo.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../screens/impressao/impressao_enviar_screen.dart';
import '../../screens/impressao/personalizados_screen.dart';
import '../../services/impressao_service.dart';

class ImpressaoBotoesTopo extends StatefulWidget {
  const ImpressaoBotoesTopo({super.key, required this.restaurantId, required this.storeName, this.service});

  final String restaurantId;
  final String storeName;
  final ImpressaoService? service;

  @override
  State<ImpressaoBotoesTopo> createState() => _ImpressaoBotoesTopoState();
}

class _ImpressaoBotoesTopoState extends State<ImpressaoBotoesTopo> {
  late final ImpressaoService _svc = widget.service ?? ImpressaoService();
  ImpressaoLoja? _loja;

  @override
  void initState() {
    super.initState();
    _svc.loja(widget.restaurantId).then((l) {
      if (mounted) setState(() => _loja = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _loja;
    // o servidor (impressao_criar) exige o serviço ligado também para os personalizados
    if (l == null || !l.ligado) return const SizedBox.shrink();
    Widget cartao({required Key key, required IconData icone, required String titulo, required String sub, required Widget ecra}) =>
        Expanded(
          child: Material(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: key,
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecra)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icone, color: AppColors.primary, size: 28),
                  const SizedBox(height: 6),
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 2),
                ]),
              ),
            ),
          ),
        );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(children: [
        cartao(
            key: const ValueKey('impressao_imprimir_documentos'),
            icone: Icons.print,
            titulo: 'Imprimir documentos',
            sub: 'Tire uma foto ou envie o PDF e veja o preço',
            ecra: ImpressaoEnviarScreen(restaurantId: widget.restaurantId, lojaNome: widget.storeName),
          ),
        if (l.personalizados) const SizedBox(width: 10),
        if (l.personalizados)
          cartao(
            key: const ValueKey('impressao_personalizados'),
            icone: Icons.card_giftcard,
            titulo: 'Personalizados',
            sub: 'Canecas, t-shirts e mais com a sua foto',
            ecra: PersonalizadosScreen(restaurantId: widget.restaurantId, lojaNome: widget.storeName),
          ),
      ]),
    );
  }
}
