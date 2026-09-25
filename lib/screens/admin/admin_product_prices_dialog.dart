// Painel admin (PT-BR) — editor do par de preços de um produto de loja PARCEIRA.
//
// 2026-09-14 (missão parceiro-edita-preco): o painel editava só `products.price`
// e deixava `partner_shelf_price` para trás, e o parceiro passava a receber um
// valor que já não correspondia à etiqueta. Aqui mostram-se as duas colunas:
//   • Preço de balcão — o que o parceiro recebe (`partner_shelf_price`)
//   • Preço no app    — o que o cliente vê (`price`)
// Digitar num recalcula o outro pela regra da plataforma (PartnerPriceRules,
// percentagens lidas de platform_settings; app_markup_pct da loja quando
// existe). Grava pela RPC admin_update_product_prices, que recusa um par
// incoerente (partner_store_share(price) tem que devolver o balcão).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/partner_price_rules.dart';

/// Abre o diálogo. Devolve `true` quando gravou.
Future<bool> showAdminProductPricesDialog(
  BuildContext context, {
  required String productId,
  required String productName,
  required double currentPrice,
  double? currentShelfPrice,
  double? appMarkupPct,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _AdminProductPricesDialog(
      productId: productId,
      productName: productName,
      currentPrice: currentPrice,
      currentShelfPrice: currentShelfPrice,
      appMarkupPct: appMarkupPct,
    ),
  );
  return saved == true;
}

class _AdminProductPricesDialog extends StatefulWidget {
  const _AdminProductPricesDialog({
    required this.productId,
    required this.productName,
    required this.currentPrice,
    required this.currentShelfPrice,
    required this.appMarkupPct,
  });

  final String productId;
  final String productName;
  final double currentPrice;
  final double? currentShelfPrice;
  final double? appMarkupPct;

  @override
  State<_AdminProductPricesDialog> createState() =>
      _AdminProductPricesDialogState();
}

class _AdminProductPricesDialogState extends State<_AdminProductPricesDialog> {
  late final TextEditingController _shelfCtrl;
  late final TextEditingController _appCtrl;
  final _reasonCtrl = TextEditingController();

  PartnerPriceRules? _rules;
  bool _rulesLoading = true;
  bool _saving = false;
  String? _error;

  // Evita o eco: quando um campo escreve no outro, o listener do outro não
  // pode voltar a escrever no primeiro.
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _shelfCtrl = TextEditingController(
      text: widget.currentShelfPrice == null
          ? ''
          : _fmt(widget.currentShelfPrice!),
    );
    _appCtrl = TextEditingController(text: _fmt(widget.currentPrice));
    _shelfCtrl.addListener(_onShelfChanged);
    _appCtrl.addListener(_onAppChanged);
    _loadRules();
  }

  @override
  void dispose() {
    _shelfCtrl.dispose();
    _appCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() => _rulesLoading = true);
    final rules = await PartnerPriceRules.load(appMarkupPct: widget.appMarkupPct);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _rulesLoading = false;
      _error = rules == null
          ? 'Não foi possível ler as percentagens em platform_settings.'
          : null;
    });
    // Produto antigo sem balcão gravado: deriva o balcão do preço atual para
    // o Danilo ver logo quanto o parceiro está a receber hoje.
    if (rules != null && _shelfCtrl.text.trim().isEmpty) {
      _setSilently(_shelfCtrl, rules.shelfFromAppPrice(widget.currentPrice));
    }
  }

  void _onShelfChanged() {
    if (_syncing) return;
    final rules = _rules;
    final shelf = _parse(_shelfCtrl.text);
    if (rules == null || shelf == null) return;
    _setSilently(_appCtrl, rules.appPriceFromShelf(shelf));
  }

  void _onAppChanged() {
    if (_syncing) return;
    final rules = _rules;
    final app = _parse(_appCtrl.text);
    if (rules == null || app == null) return;
    _setSilently(_shelfCtrl, rules.shelfFromAppPrice(app));
  }

  void _setSilently(TextEditingController ctrl, double value) {
    _syncing = true;
    ctrl.text = _fmt(value);
    _syncing = false;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final shelf = _parse(_shelfCtrl.text);
    final app = _parse(_appCtrl.text);
    final reason = _reasonCtrl.text.trim();
    if (shelf == null || app == null || shelf < 0 || app < 0) {
      setState(() => _error = 'Preços inválidos.');
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
      await Supabase.instance.client.rpc('admin_update_product_prices', params: {
        'p_product_id': widget.productId,
        'p_shelf_price': shelf,
        'p_app_price': app,
        'p_reason': reason,
      });
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
    final rules = _rules;
    final shelf = _parse(_shelfCtrl.text);
    final app = _parse(_appCtrl.text);
    final ruleLabel = rules == null
        ? null
        : rules.usesStoreMarkup
            ? 'Regra desta loja: balcão + ${_pct(rules.appMarkupPct!)} '
                '(comissão paga pelo cliente).'
            : 'Regra da plataforma: balcão ÷ (1 − ${_pct(rules.visibleCommissionPct)}) '
                '× (1 + ${_pct(rules.hiddenMarkupPct)}).';

    return AlertDialog(
      title: Text('Preços — ${widget.productName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _shelfCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço de balcão (€) — o parceiro recebe',
                helperText: 'É o que o parceiro escreve na app dele.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _appCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço no app (€) — o cliente vê',
                helperText: 'Recalculado sozinho; pode digitar aqui também.',
              ),
            ),
            const SizedBox(height: 8),
            if (_rulesLoading)
              const Text('Lendo as percentagens da plataforma…',
                  style: TextStyle(fontSize: 12, color: AppColors.textSubtle))
            else if (ruleLabel != null)
              Text(ruleLabel,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSubtle)),
            if (rules != null && shelf != null && app != null) ...[
              const SizedBox(height: 4),
              Text(
                'Parceiro recebe ${formatEurPt(rules.shelfFromAppPrice(app))} '
                'de cada ${formatEurPt(app)} que o cliente paga.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motivo (mín 3)'),
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
          onPressed: (_saving || rules == null) ? null : _save,
          child: Text(_saving ? 'Salvando…' : 'Salvar'),
        ),
      ],
    );
  }

  static String _fmt(double v) => v.toStringAsFixed(2);

  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';

  static double? _parse(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }
}
