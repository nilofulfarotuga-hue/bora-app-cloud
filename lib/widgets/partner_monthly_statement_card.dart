import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

/// "Este mês" — extrato mensal da loja parceira (missão fecho-mensal-2026-09, B5).
///
/// Lê a RPC `partner_monthly_statement` (a mesma que vai por email no dia 1):
/// pedidos do mês um a um, acertos semanais com o estado de cada um, total pago
/// e saldo. O servidor só devolve dados da própria loja. Botão para descarregar
/// o extrato em PDF. Texto em PT-PT.
class PartnerMonthlyStatementCard extends StatefulWidget {
  const PartnerMonthlyStatementCard({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  State<PartnerMonthlyStatementCard> createState() =>
      _PartnerMonthlyStatementCardState();
}

class _PartnerMonthlyStatementCardState
    extends State<PartnerMonthlyStatementCard> {
  late DateTime _mes;
  bool _loading = true;
  String? _erro;
  Map<String, dynamic>? _ext;
  bool _abrirPedidos = false;

  @override
  void initState() {
    super.initState();
    final agora = DateTime.now();
    _mes = DateTime(agora.year, agora.month, 1);
    _carregar();
  }

  static double _n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _eur(dynamic v) =>
      '${_n(v).toStringAsFixed(2).replaceAll('.', ',')} €';
  static List<Map<String, dynamic>> _lista(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('partner_monthly_statement',
          params: {
            'p_partner_id': widget.restaurantId,
            'p_year': _mes.year,
            'p_month': _mes.month,
          });
      if (!mounted) return;
      setState(() => _ext = r is Map ? Map<String, dynamic>.from(r) : null);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar o extrato.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _mudarMes(int delta) {
    final novo = DateTime(_mes.year, _mes.month + delta, 1);
    final agora = DateTime.now();
    if (novo.isAfter(DateTime(agora.year, agora.month, 1))) return;
    setState(() => _mes = novo);
    _carregar();
  }

  bool get _eMesAtual {
    final agora = DateTime.now();
    return _mes.year == agora.year && _mes.month == agora.month;
  }

  String _estado(String? s) => switch (s) {
        'paid' => 'pago',
        'pending' => 'por pagar',
        null => '',
        _ => s,
      };

  Future<void> _descarregarPdf() async {
    final x = _ext;
    if (x == null) return;
    final p = Map<String, dynamic>.from(x['parceiro'] as Map);
    final per = Map<String, dynamic>.from(x['periodo'] as Map);
    final t = Map<String, dynamic>.from(x['totais'] as Map);
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text('Bora — Extrato de ${per['nome']} de ${per['ano']}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('${p['nome']}${p['nif'] != null ? ' · NIF ${p['nif']}' : ''}',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['Resumo', ''],
          data: [
            ['Pedidos entregues', '${t['pedidos']}'],
            ['Vendas', _eur(t['vendas'])],
            ['Comissão Bora', '-${_eur(t['comissao'])}'],
            ['A sua parte', _eur(t['parte_loja'])],
            ['Pago no mês (acertos semanais)', _eur(x['total_pago_no_mes'])],
            ['Saldo', _eur(x['saldo'])],
          ],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
          headerStyle: pw.TextStyle(
              color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 14),
        pw.Text('Pedidos do mês',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Data', 'N.º', 'Subtotal', 'Comissão', 'Recebe'],
          data: [
            for (final o in _lista(x['pedidos']))
              [
                '${o['data']}',
                '#${o['numero']}',
                _eur(o['subtotal']),
                '-${_eur(o['comissao'])}',
                _eur(o['recebeu']),
              ],
          ],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
          headerStyle: pw.TextStyle(
              color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 14),
        pw.Text('Acertos semanais',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Semana', 'Valor', 'Estado', 'Pago em'],
          data: [
            for (final a in _lista(x['acertos_semanais']))
              [
                '${a['semana']}',
                _eur(a['valor']),
                _estado(a['estado']?.toString()),
                '${a['pago_em'] ?? ''}',
              ],
          ],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
          headerStyle: pw.TextStyle(
              color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Bora App · extrato gerado na app',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ],
    ));
    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'extrato-bora-${per['ano']}-${per['mes'].toString().padLeft(2, '0')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = _ext;
    final t = x == null ? null : Map<String, dynamic>.from(x['totais'] as Map);
    final nomeMes = x == null ? '' : '${x['periodo']['nome']} de ${x['periodo']['ano']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                    tooltip: 'Mês anterior',
                    onPressed: () => _mudarMes(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Column(
                    children: [
                      Text(_eMesAtual ? 'Este mês' : 'Extrato do mês',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                      Text(nomeMes,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                IconButton(
                    tooltip: 'Mês seguinte',
                    onPressed: _eMesAtual ? null : () => _mudarMes(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()))
            else if (_erro != null)
              Text(_erro!, style: const TextStyle(color: Colors.red))
            else if (x != null && t != null) ...[
              _linha('Pedidos entregues', '${t['pedidos']}'),
              _linha('Vendas', _eur(t['vendas'])),
              _linha('Comissão Bora', '−${_eur(t['comissao'])}'),
              _linha('A sua parte', _eur(t['parte_loja']), forte: true),
              _linha('Pago no mês', _eur(x['total_pago_no_mes'])),
              _linha('Saldo', _eur(x['saldo']), forte: true),
              if (_lista(x['acertos_semanais']).isNotEmpty) ...[
                const Divider(),
                for (final a in _lista(x['acertos_semanais']))
                  _linha('Semana ${a['semana']}',
                      '${_eur(a['valor'])} · ${_estado(a['estado']?.toString())}'),
              ],
              if (_lista(x['pedidos']).isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _abrirPedidos = !_abrirPedidos),
                  child: Text(_abrirPedidos
                      ? 'Esconder pedidos'
                      : 'Ver os ${_lista(x['pedidos']).length} pedidos'),
                ),
              if (_abrirPedidos)
                for (final o in _lista(x['pedidos']))
                  _linha('${o['data']} · #${o['numero']}',
                      '${_eur(o['subtotal'])} → ${_eur(o['recebeu'])}'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _descarregarPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Descarregar extrato (PDF)'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linha(String a, String b, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(a, style: const TextStyle(fontSize: 14))),
            Text(b,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: forte ? FontWeight.w800 : FontWeight.w500,
                    color: forte ? AppColors.primary : null)),
          ],
        ),
      );
}
