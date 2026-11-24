// Painel admin — Farmácias: "Taxas ao cliente" de cada farmácia (23/11/2026, missão
// farmacia-rego-2026-11-23, Adendo 2 do Danilo). PT-BR.
// Mostra e deixa editar o que é da loja: margem dentro do preço (restaurants.app_markup_pct),
// pedido mínimo e taxa de pedido pequeno (overrides; vazio = valor geral das Configurações).
// O exemplo "pedido de 10 € de balcão a 2 km" é calculado pelo SERVIDOR (pricing_calculate_loja,
// small_order_fee_calc, partner_store_share): o painel nunca promete uma regra que o servidor
// ainda não aplica. A gravação é direta na loja (só admin; fica na auditoria da loja).
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/admin_farmacias_service.dart';

String _euros(double v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';
String _eurosCents(int c) => _euros(c / 100);

String _pct(double fracao) {
  final v = fracao * 100;
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ',');
}

/// Lê "15", "15%", "15,5" → 0.15 / 0.155. Vazio → null. Inválido → NaN.
double? lerPercentagem(String t) {
  final s = t.replaceAll('%', '').replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v > 50) return double.nan;
  return v / 100;
}

/// Lê "1,39" / "15" (euros) → cêntimos. Vazio → null. Inválido → -1.
int? lerEurosCents(String t) {
  final s = t.replaceAll('€', '').replaceAll(',', '.').trim();
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v > 200) return -1;
  return (v * 100).round();
}

/// Linhas de texto das taxas (puras, testáveis).
List<String> linhasTaxasFarmacia(TaxasFarmacia t) => [
      t.temMargem
          ? 'Margem dentro do preço: ${_pct(t.margem!)} % (o cliente vê o balcão + ${_pct(t.margem!)} % no '
              'preço do produto, sem linha à parte; a farmácia recebe o balcão; a diferença fica para a Bora)'
          : 'Sem margem: o preço na app é o da farmácia e ela recebe tudo',
      'Pedido pequeno: ${_eurosCents(t.taxaPedidoPequenoEfetivaCents)} abaixo de ${_eurosCents(t.pedidoMinimoEfetivoCents)}'
          '${t.pedidoMinimoCents == null && t.taxaPedidoPequenoCents == null ? ' (valores gerais das Configurações)' : ' (valor desta loja)'}',
      // A taxa de serviço, a entrega e o saco vêm do servidor (exemplo abaixo): as farmácias sem margem
      // levam ${pharmacy_service_fee_fixed_cents} + ${client_service_fee_pct}; com margem, só a % (AUTORIZO 23/11).
      'Taxa de serviço, entrega e saco: veja o exemplo calculado pelo servidor',
    ];

class AdminFarmaciaTaxas extends StatefulWidget {
  const AdminFarmaciaTaxas({super.key, required this.restaurantId, this.servico});

  final String restaurantId;
  final AdminFarmaciasService? servico;

  @override
  State<AdminFarmaciaTaxas> createState() => _AdminFarmaciaTaxasState();
}

class _AdminFarmaciaTaxasState extends State<AdminFarmaciaTaxas> {
  late final AdminFarmaciasService _svc = widget.servico ?? AdminFarmaciasService();
  TaxasFarmacia? _t;
  ExemploTaxasFarmacia? _ex;
  String? _erro;
  bool _aLer = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (mounted) setState(() => _aLer = true);
    try {
      final t = await _svc.taxasLoja(widget.restaurantId);
      final ex = await _svc.exemploServidor(widget.restaurantId, margem: t.margem);
      if (!mounted) return;
      setState(() {
        _t = t;
        _ex = ex;
        _erro = null;
        _aLer = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _aLer = false;
      });
    }
  }

  Future<void> _editar() async {
    final t = _t;
    if (t == null) return;
    final margem = TextEditingController(text: t.margem == null ? '' : _pct(t.margem!));
    final minimo = TextEditingController(
        text: t.pedidoMinimoCents == null ? '' : (t.pedidoMinimoCents! / 100).toStringAsFixed(2).replaceAll('.', ','));
    final taxa = TextEditingController(
        text: t.taxaPedidoPequenoCents == null ? '' : (t.taxaPedidoPequenoCents! / 100).toStringAsFixed(2).replaceAll('.', ','));
    String? erro;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Taxas ao cliente desta farmácia'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Atenção: isto muda o que o cliente paga e o que a farmácia recebe. '
                    'Só salve com a ordem do Danilo ("autorizo" com data).',
                    style: TextStyle(color: AppColors.error, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(
                  controller: margem,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Margem dentro do preço do produto',
                    suffixText: '%',
                    helperText: 'Vazio = sem margem (preço da farmácia, ela recebe tudo). Ex.: 15',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minimo,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Pedido mínimo sem taxa',
                    suffixText: '€',
                    helperText: 'Vazio = geral (${_eurosCents(t.pedidoMinimoGeralCents)})',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: taxa,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Taxa de pedido pequeno',
                    suffixText: '€',
                    helperText: 'Vazio = geral (${_eurosCents(t.taxaPedidoPequenoGeralCents)})',
                  ),
                ),
                if (erro != null) ...[
                  const SizedBox(height: 8),
                  Text(erro!, style: const TextStyle(color: AppColors.error)),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final m = lerPercentagem(margem.text);
                final mi = lerEurosCents(minimo.text);
                final tx = lerEurosCents(taxa.text);
                if (m != null && m.isNaN) {
                  set(() => erro = 'Margem: escreva uma percentagem entre 0 e 50 (ex.: 15), ou deixe vazio.');
                  return;
                }
                if (mi == -1 || tx == -1) {
                  set(() => erro = 'Valores em euros, ex.: 15 ou 1,39 (ou vazio para o valor geral).');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final m = lerPercentagem(margem.text);
    try {
      await _svc.definirTaxas(
        widget.restaurantId,
        margem: (m == null || m == 0) ? null : m,
        pedidoMinimoCents: lerEurosCents(minimo.text),
        taxaPedidoPequenoCents: lerEurosCents(taxa.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Taxas salvas.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    const pequeno = TextStyle(color: AppColors.textSecondary, fontSize: 12);
    final t = _t;
    final ex = _ex;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Taxas ao cliente', style: TextStyle(fontWeight: FontWeight.w700))),
        TextButton.icon(
          onPressed: t == null ? null : _editar,
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Editar'),
        ),
      ]),
      if (_aLer && t == null)
        const Text('A ler…', style: pequeno)
      else if (_erro != null && t == null)
        Row(children: [
          Expanded(child: Text(_erro!, style: const TextStyle(color: AppColors.error))),
          TextButton(onPressed: _carregar, child: const Text('Tentar de novo')),
        ])
      else if (t != null) ...[
        for (final l in linhasTaxasFarmacia(t)) Text('• $l'),
        if (ex != null) ...[
          const SizedBox(height: 6),
          Text(
            'Exemplo calculado pelo servidor agora (1 produto de ${_euros(ex.balcao)} de balcão, 2 km): '
            'produto ${_euros(ex.produto)} + serviço ${_euros(ex.taxaServico)} + entrega ${_euros(ex.entrega)}'
            '${ex.saco > 0 ? ' + saco ${_euros(ex.saco)}' : ''}'
            '${ex.pedidoPequeno > 0 ? ' + pedido pequeno ${_euros(ex.pedidoPequeno)}' : ''}'
            ' = cliente paga ${_euros(ex.clientePaga)} · farmácia recebe ${_euros(ex.farmaciaRecebe)} · '
            'entregador ${_euros(ex.estafeta)} · fica para a Bora ${_euros(ex.bora)}',
            style: pequeno,
          ),
        ],
      ],
    ]);
  }
}
