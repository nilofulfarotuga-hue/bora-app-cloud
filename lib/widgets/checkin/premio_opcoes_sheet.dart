// lib/widgets/checkin/premio_opcoes_sheet.dart
//
// Ficha do artigo-prémio do check-in (Bloco D, 21/10/2026): o cliente escolhe os
// sabores (salgados da Keli) ou os acompanhamentos (Goola Bowl) e põe o prémio
// no carrinho a 0,00 €. Os extras pagos à parte somam-se ao preço da linha, como
// numa ficha normal. As opções vêm de `product_option_groups` do artigo-prémio.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../models/cart_item.dart';
import '../../models/product_option.dart';
import '../../services/checkin_premios_service.dart';
import '../../services/pricing_service.dart';
import '../../stores/cart_store.dart';
import '../../utils/euros.dart';

/// Abre a ficha; devolve `true` se o prémio entrou no carrinho.
Future<bool> mostrarPremioOpcoes(
  BuildContext context,
  ReservaPremio reserva, {
  required bool lojaParceira,
  Future<List<ProductOptionGroup>> Function(String produtoId)? carregarOpcoes,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => PremioOpcoesSheet(
      reserva: reserva,
      lojaParceira: lojaParceira,
      carregarOpcoes: carregarOpcoes,
    ),
  );
  return r == true;
}

Future<List<ProductOptionGroup>> _opcoesDoServidor(String produtoId) async {
  final res = await Supabase.instance.client
      .from('product_option_groups')
      .select(
          'id,product_id,name,description,is_required,min_choices,max_choices,sort_order,product_option_items(id,name,price_add,is_available,sort_order)')
      .eq('product_id', produtoId)
      .order('sort_order');
  return (res as List)
      .map((e) => ProductOptionGroup.fromMap(e as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

class PremioOpcoesSheet extends StatefulWidget {
  const PremioOpcoesSheet({
    super.key,
    required this.reserva,
    required this.lojaParceira,
    this.carregarOpcoes,
  });

  final ReservaPremio reserva;
  final bool lojaParceira;
  final Future<List<ProductOptionGroup>> Function(String produtoId)? carregarOpcoes;

  @override
  State<PremioOpcoesSheet> createState() => _PremioOpcoesSheetState();
}

class _PremioOpcoesSheetState extends State<PremioOpcoesSheet> {
  List<ProductOptionGroup> _grupos = const [];
  final Map<String, Set<String>> _sel = {};
  bool _aCarregar = true;
  bool _falhou = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final g = await (widget.carregarOpcoes ?? _opcoesDoServidor)(widget.reserva.produtoId);
      if (!mounted) return;
      setState(() {
        _grupos = g;
        _aCarregar = false;
      });
    } catch (e) {
      debugPrint('[PremioOpcoes] $e');
      if (!mounted) return;
      setState(() {
        _aCarregar = false;
        _falhou = true;
      });
    }
  }

  int _conta(ProductOptionGroup g) => _sel[g.id]?.length ?? 0;
  bool get _completo => _grupos.every((g) => _conta(g) >= g.minChoices);

  double get _extras {
    double s = 0;
    for (final g in _grupos) {
      final ids = _sel[g.id];
      if (ids == null) continue;
      for (final it in g.items) {
        if (ids.contains(it.id)) s += it.priceAdd;
      }
    }
    return s;
  }

  void _toca(ProductOptionGroup g, ProductOptionItem it) {
    if (!it.isAvailable) return;
    final set = _sel.putIfAbsent(g.id, () => <String>{});
    setState(() {
      if (g.maxChoices <= 1) {
        set
          ..clear()
          ..add(it.id);
      } else if (set.contains(it.id)) {
        set.remove(it.id);
      } else if (set.length < g.maxChoices) {
        set.add(it.id);
      }
    });
  }

  void _adicionar() {
    final escolhas = <SelectedOption>[];
    for (final g in _grupos) {
      final ids = _sel[g.id];
      if (ids == null || ids.isEmpty) continue;
      final nomes = g.items.where((it) => ids.contains(it.id)).map((it) => it.name).toList();
      if (nomes.isNotEmpty) escolhas.add(SelectedOption(group: g.name, items: nomes));
    }
    final r = widget.reserva;
    context.read<CartStore>().addItem(CartItem(
          productId: r.produtoId,
          name: r.nome,
          // O artigo vale 0 €; só os extras pagos à parte entram no preço.
          price: PricingService.applyMarkup(_extras, widget.lojaParceira),
          basePrice: 0,
          quantity: r.vale.quantidade,
          selectedOptions: escolhas,
        ));
    Navigator.of(context).pop(true);
  }

  String _dica(ProductOptionGroup g) {
    if (g.minChoices > 0 && g.minChoices == g.maxChoices) return 'Escolhe {0}'.trArgs([g.minChoices]);
    if (g.minChoices > 0) return 'Escolhe {0} a {1}'.trArgs([g.minChoices, g.maxChoices]);
    return 'Escolhe até {0}'.trArgs([g.maxChoices]);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reserva;
    final extras = PricingService.applyMarkup(_extras, widget.lojaParceira);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                key: const Key('premio_opcoes_sheet'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.card_giftcard, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O teu prémio do check-in'.tr,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(r.nome, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    if (r.lojaNome.isNotEmpty)
                      Text(r.lojaNome, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text(
                      'Grátis: só pagas a entrega e as taxas.'.tr,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    if (_aCarregar)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else if (_falhou)
                      Text(
                        'Não foi possível carregar as opções. Tenta de novo.'.tr,
                        style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                      )
                    else
                      for (final g in _grupos) ...[
                        Text(g.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text(_dica(g), style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final it in g.items)
                              ChoiceChip(
                                key: Key('premio_opcao_${it.id}'),
                                label: Text(it.priceAdd > 0
                                    ? '${it.name} (+${eur(PricingService.applyMarkup(it.priceAdd, widget.lojaParceira))})'
                                    : it.name),
                                selected: _sel[g.id]?.contains(it.id) ?? false,
                                onSelected: it.isAvailable ? (_) => _toca(g, it) : null,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton.icon(
                key: const Key('btn_premio_carrinho'),
                onPressed: (!_aCarregar && !_falhou && _completo) ? _adicionar : null,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text(
                  _completo || _aCarregar
                      ? 'Pôr no carrinho · €{0}'.trArgs([extras.toStringAsFixed(2)])
                      : 'Completa as escolhas obrigatórias'.tr,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
