import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';
import '../models/order_model.dart';
import '../services/ajustes_peso_service.dart';

/// Ajustes ao peso no ecrã do pedido do cliente (acompanhamento e recibo),
/// 31/10/2026. Lê `order_weight_adjustments` do pedido e mostra uma linha por
/// produto ao quilo que o estafeta pesou:
///
///   4× Banana da Madeira
///   Ajustado ao peso: 1,12 € → 1,40 €
///
/// Sem linhas (ou só linhas que voltaram ao preço previsto) não desenha nada.
/// A tabela não está no realtime: volta a ler quando o estado do pedido muda
/// e quando chega o push `order_weight_adjusted` com a app aberta
/// (`AjustesPesoService.avisos`).
class AjustesPesoPedido extends StatefulWidget {
  const AjustesPesoPedido({
    super.key,
    required this.orderId,
    required this.status,
    this.margem = const EdgeInsets.only(bottom: Spacing.md),
  });

  final String orderId;

  /// Muda o estado, volta-se a ler.
  final OrderStatus status;
  final EdgeInsetsGeometry margem;

  @override
  State<AjustesPesoPedido> createState() => _AjustesPesoPedidoState();
}

class _AjustesPesoPedidoState extends State<AjustesPesoPedido> {
  List<AjustePeso> _ajustes = const <AjustePeso>[];

  @override
  void initState() {
    super.initState();
    AjustesPesoService.avisos.addListener(_aoAviso);
    _carregar();
  }

  @override
  void didUpdateWidget(covariant AjustesPesoPedido old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId || old.status != widget.status) {
      _carregar();
    }
  }

  @override
  void dispose() {
    AjustesPesoService.avisos.removeListener(_aoAviso);
    super.dispose();
  }

  void _aoAviso() {
    final de = AjustesPesoService.ultimoPedidoAvisado;
    if (de == null || de.isEmpty || de == widget.orderId) _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await AjustesPesoService.instance.doPedido(widget.orderId);
      if (!mounted) return;
      setState(() => _ajustes = lista);
    } catch (e) {
      debugPrint('[AjustesPesoPedido] ${widget.orderId}: $e');
    }
  }

  @override
  Widget build(BuildContext context) =>
      AjustesPesoLista(ajustes: _ajustes, margem: widget.margem);
}

/// A parte que se vê, sem rede (testável): só as linhas em que o valor mudou.
/// Letra de 16 px (adendo 4 · item 9: texto novo do cliente nunca abaixo).
class AjustesPesoLista extends StatelessWidget {
  const AjustesPesoLista({
    super.key,
    required this.ajustes,
    this.margem = EdgeInsets.zero,
  });

  final List<AjustePeso> ajustes;
  final EdgeInsetsGeometry margem;

  /// "Ajustado ao peso: 1,12 € → 1,40 €", já no idioma ativo.
  static String linha(AjustePeso a) =>
      'Ajustado ao peso: {0}'.trArgs([a.deAteTexto]);

  @override
  Widget build(BuildContext context) {
    final mudados = AjustesPesoService.soMudados(ajustes);
    if (mudados.isEmpty) return const SizedBox.shrink();
    final cinza = Colors.grey.shade600;
    return Padding(
      padding: margem,
      child: Container(
        key: const Key('ajustes_peso_pedido'),
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < mudados.length; i++) ...[
              if (i > 0) const SizedBox(height: Spacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.scale_outlined, size: 20, color: cinza),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mudados[i].itemName != null)
                          Text(
                            '${mudados[i].qty}× ${mudados[i].itemName}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        Text(
                          linha(mudados[i]),
                          style: TextStyle(fontSize: 16, color: cinza),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
