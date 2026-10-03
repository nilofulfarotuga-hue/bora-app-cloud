// Painel admin (PT-BR) — venda ao peso de um produto (2026-09-18).
//
// Liga/desliga `sold_by_weight` e edita `shelf_price_per_kg` (o preço por
// quilo que o parceiro recebe). Ao salvar, a função `set_product_weight_pricing`
// do servidor recalcula o preço da porção base (200 g) e reconstrói o grupo
// obrigatório "Escolhe a quantidade" (200/300/400/500 g e 1 kg) com as
// percentagens de platform_settings — a mesma função que a app do parceiro
// usa, para não haver duas verdades. Aqui só se mostra a prévia com
// PartnerPriceRules/WeightPortions.

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/partner_price_rules.dart';
import '../../services/weight_portions.dart';

/// Abre o diálogo. Devolve `true` quando gravou.
Future<bool> showAdminProductWeightDialog(
  BuildContext context, {
  required String productId,
  required String productName,
  required bool soldByWeight,
  double? shelfPricePerKg,
  required bool isPartner,
  double? appMarkupPct,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _AdminProductWeightDialog(
      productId: productId,
      productName: productName,
      soldByWeight: soldByWeight,
      shelfPricePerKg: shelfPricePerKg,
      isPartner: isPartner,
      appMarkupPct: appMarkupPct,
    ),
  );
  return saved == true;
}

class _AdminProductWeightDialog extends StatefulWidget {
  const _AdminProductWeightDialog({
    required this.productId,
    required this.productName,
    required this.soldByWeight,
    required this.shelfPricePerKg,
    required this.isPartner,
    required this.appMarkupPct,
  });

  final String productId;
  final String productName;
  final bool soldByWeight;
  final double? shelfPricePerKg;
  final bool isPartner;
  final double? appMarkupPct;

  @override
  State<_AdminProductWeightDialog> createState() =>
      _AdminProductWeightDialogState();
}

class _AdminProductWeightDialogState extends State<_AdminProductWeightDialog> {
  late bool _on;
  late final TextEditingController _kgCtrl;
  final _reasonCtrl = TextEditingController();
  PartnerPriceRules? _rules;
  bool _rulesLoading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _on = widget.soldByWeight;
    _kgCtrl = TextEditingController(
      text: widget.shelfPricePerKg == null
          ? ''
          : widget.shelfPricePerKg!.toStringAsFixed(2),
    );
    _kgCtrl.addListener(() => setState(() {}));
    if (widget.isPartner) _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _rulesLoading = true);
    final rules = await PartnerPriceRules.load(appMarkupPct: widget.appMarkupPct);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _rulesLoading = false;
    });
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final kg = _parse(_kgCtrl.text);
    final reason = _reasonCtrl.text.trim();
    if (_on && (kg == null || kg <= 0)) {
      setState(() => _error = 'Informe o preço por kg (maior que zero).');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'Motivo obrigatório (mín. 3 caracteres).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await WeightPortions.apply(
        productId: widget.productId,
        soldByWeight: _on,
        shelfPricePerKg: _on ? kg : null,
        reason: reason,
      );
      if (res['success'] != true) {
        throw StateError('o servidor não confirmou');
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Erro ao salvar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final kg = _parse(_kgCtrl.text);
    final rules = widget.isPartner ? _rules : null;
    final canPreview = kg != null && kg > 0 && (!widget.isPartner || rules != null);

    return AlertDialog(
      title: Text('Venda ao peso — ${widget.productName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vendido ao peso'),
              subtitle: const Text(
                  'O cliente escolhe 200 g, 300 g, 400 g, 500 g ou 1 kg. '
                  'O preço da linha vira a porção de 200 g.'),
              value: _on,
              onChanged: _saving ? null : (v) => setState(() => _on = v),
            ),
            if (_on) ...[
              TextField(
                controller: _kgCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.isPartner
                      ? 'Preço por kg de balcão (€) — o parceiro recebe'
                      : 'Preço por kg (€)',
                  helperText: 'As porções e o preço no app são recalculados '
                      'sozinhos ao salvar.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.isPartner && _rulesLoading)
                const Text('Lendo as percentagens da plataforma…',
                    style: TextStyle(fontSize: 12)),
              if (widget.isPartner && !_rulesLoading && rules == null)
                Row(children: [
                  const Expanded(
                      child: Text(
                          'Não foi possível ler as percentagens da plataforma.',
                          style: TextStyle(fontSize: 12))),
                  TextButton(
                      onPressed: _loadRules, child: const Text('Tentar de novo')),
                ]),
              if (canPreview)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cliente vê: ${formatEurPt(WeightPortions.clientPriceFor(kg, 1000, rules))} por kg',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      for (final p in WeightPortions.preview(kg, rules))
                        Text('${p.label} — ${formatEurPt(p.price)}',
                            style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Desligar remove o grupo "Escolhe a quantidade". O preço da '
                  'linha fica como está — ajuste-o depois em "Editar preço".',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motivo (mín. 3)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvando…' : 'Salvar'),
        ),
      ],
    );
  }
}
