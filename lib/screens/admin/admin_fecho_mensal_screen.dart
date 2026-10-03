import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_order_detail_screen.dart';

/// Painel admin "Fecho do mês" (PT-BR, só o Danilo) — missão fecho-mensal-2026-09.
///
/// Tudo o que aparece vem do servidor; o Dart não soma dinheiro:
///  - `admin_monthly_closeout(ano, mes)` (B1): totais, parceiros, serviços,
///    estafetas, pedidos no prejuízo, TVDE de outros motoristas e o bloco
///    "para as Finanças" (faturas-recibo a emitir + texto corrido).
///  - `admin_resend_monthly_statement` (B3): reenviar o extrato mensal.
///  - `driver_monthly_invoice_summary` (B6A): recibos verdes dos estafetas.
///  - `admin_bora_invoices_month` / `admin_mark_bora_invoice` (B6B): faturas
///    da Bora por pedido (a partir de 01/10/2026), a lançar no Portal.
///  - `admin_dac7_report` (B6C): exportar DAC7 (só prepara, não envia).
class AdminFechoMensalScreen extends StatefulWidget {
  const AdminFechoMensalScreen({super.key, this.mesInicial});

  /// 'YYYY-MM'. Sem valor: o mês anterior (o que se fecha no dia 1).
  final String? mesInicial;

  @override
  State<AdminFechoMensalScreen> createState() => _AdminFechoMensalScreenState();
}

class _AdminFechoMensalScreenState extends State<AdminFechoMensalScreen> {
  final _sb = Supabase.instance.client;
  late int _ano;
  late int _mes;
  bool _loading = true;
  String? _erro;
  Map<String, dynamic>? _fecho;
  List<Map<String, dynamic>> _recibos = [];
  Map<String, dynamic>? _faturas;

  static const _meses = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
    'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ];

  @override
  void initState() {
    super.initState();
    final m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(widget.mesInicial ?? '');
    if (m != null) {
      _ano = int.parse(m.group(1)!);
      _mes = int.parse(m.group(2)!);
    } else {
      final agora = DateTime.now();
      final ant = DateTime(agora.year, agora.month - 1, 1);
      _ano = ant.year;
      _mes = ant.month;
    }
    _carregar();
  }

  static double _n(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _eur(dynamic v) =>
      '€ ${_n(v).toStringAsFixed(2).replaceAll('.', ',')}';
  static List<Map<String, dynamic>> _lista(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  static Map<String, dynamic> _mapa(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  bool get _modeloNovo => DateTime(_ano, _mes).isAfter(DateTime(2026, 9));

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final f = await _sb.rpc('admin_monthly_closeout',
          params: {'p_year': _ano, 'p_month': _mes});
      final r = await _sb.rpc('driver_monthly_invoice_summary',
          params: {'p_year': _ano, 'p_month': _mes});
      Map<String, dynamic>? fat;
      if (_modeloNovo) {
        fat = _mapa(await _sb.rpc('admin_bora_invoices_month',
            params: {'p_year': _ano, 'p_month': _mes}));
      }
      if (!mounted) return;
      setState(() {
        _fecho = _mapa(f);
        _recibos = _lista(_mapa(r)['estafetas']);
        _faturas = fat;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não consegui carregar o fecho: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _aviso(String msg, {bool erro = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? Colors.red.shade700 : AppColors.primary,
    ));
  }

  Future<void> _escolherMes() async {
    final agora = DateTime.now();
    final opcoes = List.generate(
        18, (i) => DateTime(agora.year, agora.month - i, 1));
    final escolhido = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in opcoes)
              ListTile(
                title: Text('${_meses[d.month - 1]} de ${d.year}'),
                trailing: d.year == _ano && d.month == _mes
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (escolhido == null) return;
    setState(() {
      _ano = escolhido.year;
      _mes = escolhido.month;
    });
    _carregar();
  }

  Future<void> _reenviar({String? partnerId, String? nome}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reenviar extrato do mês?'),
        content: Text(partnerId == null
            ? 'Vai mandar outra vez o extrato de ${_meses[_mes - 1]} a TODAS as lojas com pedidos, e o resumo para você.'
            : 'Vai mandar outra vez o extrato de ${_meses[_mes - 1]} para $nome.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reenviar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.rpc('admin_resend_monthly_statement', params: {
        'p_year': _ano,
        'p_month': _mes,
        'p_partner_id': partnerId,
      });
      _aviso('Pedido de envio feito. Atualize daqui a uns segundos.');
      await Future.delayed(const Duration(seconds: 4));
      if (mounted) _carregar();
    } catch (e) {
      _aviso('Falhou: $e', erro: true);
    }
  }

  // ─────────────────────────── exportações ───────────────────────────

  Future<void> _exportarCsv() async {
    final f = _fecho;
    if (f == null) return;
    final t = _mapa(f['totais']);
    final fin = _mapa(f['para_as_financas']);
    final rows = <List<dynamic>>[
      ['Totais', 'Pedidos entregues', t['pedidos_entregues'], ''],
      ['Totais', 'Pago pelos clientes', _n(t['pago_pelos_clientes']).toStringAsFixed(2), ''],
      ['Totais', 'Custo da mercadoria', _n(t['custo_mercadoria']).toStringAsFixed(2), ''],
      ['Totais', 'Receita própria Bora', _n(t['receita_propria_bora']).toStringAsFixed(2), ''],
      ['Totais', 'Pago a estafetas', _n(t['pago_a_estafetas']).toStringAsFixed(2), ''],
      ['Totais', 'Lucro', _n(t['lucro']).toStringAsFixed(2), ''],
      ['Totais', 'TVDE outros motoristas (parte Bora)', _n(fin['parte_bora_tvde_outros']).toStringAsFixed(2), ''],
      for (final e in _mapa(fin['rubricas']).entries)
        ['Rubrica', e.key, _n(e.value).toStringAsFixed(2), ''],
      for (final x in _lista(fin['faturas_recibo']))
        ['Fatura-recibo', x['destinatario'], _n(x['valor']).toStringAsFixed(2), x['nif'] ?? 'sem NIF'],
      for (final p in _lista(f['parceiros']))
        ['Parceiro', p['nome'], _n(p['parte_loja']).toStringAsFixed(2),
          'pedidos ${p['pedidos']} · comissão ${_n(p['comissao_total']).toStringAsFixed(2)} · pago ${_n(p['pago_no_mes']).toStringAsFixed(2)} · pendente ${_n(p['pendente']).toStringAsFixed(2)}'],
      for (final e in _lista(f['estafetas']))
        ['Estafeta', e['nome'], _n(e['ganho']).toStringAsFixed(2),
          'entregas ${e['entregas']} · em mão ${_n(e['dinheiro_recebido_em_mao']).toStringAsFixed(2)} · talões ${_n(e['taloes_adiantados']).toStringAsFixed(2)}'],
      for (final p in _lista(f['pedidos_no_prejuizo']))
        ['Prejuízo', '${p['loja']} ${p['data']}', _n(p['resultado']).toStringAsFixed(2), '${p['motivo']} · ${p['order_id']}'],
    ];
    await AdminExportService.instance.exportCsv(
      filename: 'fecho-$_ano-${_mes.toString().padLeft(2, '0')}.csv',
      headers: const ['Bloco', 'Item', 'Valor (EUR)', 'Detalhe'],
      rows: rows,
      subject: 'Fecho de ${_meses[_mes - 1]} $_ano',
    );
  }

  Future<void> _exportarPdf() async {
    final f = _fecho;
    if (f == null) return;
    final t = _mapa(f['totais']);
    final fin = _mapa(f['para_as_financas']);
    await AdminExportService.instance.exportPdfTable(
      title: 'Fecho de ${_meses[_mes - 1]} $_ano',
      subtitle: (fin['texto'] ?? '').toString(),
      filename: 'fecho-$_ano-${_mes.toString().padLeft(2, '0')}.pdf',
      headers: const ['Item', 'Valor'],
      rows: [
        ['Pedidos entregues', '${t['pedidos_entregues']}'],
        ['Pago pelos clientes', _eur(t['pago_pelos_clientes'])],
        ['Custo da mercadoria', _eur(t['custo_mercadoria'])],
        ['Receita própria Bora', _eur(t['receita_propria_bora'])],
        ['Pago a estafetas', _eur(t['pago_a_estafetas'])],
        ['Lucro', _eur(t['lucro'])],
        ['TVDE outros motoristas (parte Bora)', _eur(fin['parte_bora_tvde_outros'])],
        ['Total a declarar', _eur(fin['total_a_declarar'])],
        for (final x in _lista(fin['faturas_recibo']))
          ['Fatura-recibo: ${x['destinatario']}${x['nif'] != null ? ' (NIF ${x['nif']})' : ''}', _eur(x['valor'])],
      ],
    );
  }

  Future<void> _exportarDac7() async {
    try {
      final r = _mapa(await _sb.rpc('admin_dac7_report', params: {'p_ano': _ano}));
      String c(dynamic v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      String eu(dynamic cents) =>
          (_n(cents) / 100).toStringAsFixed(2).replaceAll('.', ',');
      final b = StringBuffer(
          'Tipo;ID;Nome;Nome comercial;NIF;Morada;Data nascimento;IBAN;País;T1;T2;T3;T4;Total;Comissões Bora;Operações;Campos em falta\n');
      for (final l in _lista(r['linhas'])) {
        b.writeln([
          c(l['tipo']), c(l['id']), c(l['nome']), c(l['nome_comercial']),
          c(l['nif']), c(l['morada']), c(l['data_nascimento']), c(l['iban']),
          c(l['pais']), eu(l['trimestre_1_cents']), eu(l['trimestre_2_cents']),
          eu(l['trimestre_3_cents']), eu(l['trimestre_4_cents']),
          eu(l['total_cents']), eu(l['comissoes_bora_cents']),
          '${l['transacoes'] ?? 0}',
          c((l['campos_em_falta'] is List ? (l['campos_em_falta'] as List).join(', ') : '')),
        ].join(';'));
      }
      await AdminExportService.instance.exportCsvText(
          filename: 'dac7-$_ano.csv', csv: b.toString(), subject: 'DAC7 $_ano');
      final fm = _lista(r['falta_morada']).length;
      final fn = _lista(r['falta_nif']).length;
      _aviso('DAC7 $_ano exportado (só preparado, não enviado). Falta morada: $fm · falta NIF: $fn');
    } catch (e) {
      _aviso('DAC7 falhou: $e', erro: true);
    }
  }

  Future<void> _marcarDia(String data) async {
    final ids = _lista(_faturas?['linhas'])
        .where((l) => l['data'] == data && l['estado'] == 'por_lancar')
        .map((l) => l['id'])
        .toList();
    if (ids.isEmpty) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Marcar ${ids.length} fatura(s) de $data como lançadas'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'N.º do documento no Portal (opcional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Marcar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _sb.rpc('admin_mark_bora_invoice', params: {
        'p_ids': ids,
        'p_numero': ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
      });
      _carregar();
    } catch (e) {
      _aviso('Falhou: $e', erro: true);
    }
  }

  // ─────────────────────────── ecrã ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Fecho do mês',
        actions: [
          IconButton(
              tooltip: 'Exportar CSV',
              onPressed: _fecho == null ? null : _exportarCsv,
              icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: 'Exportar PDF',
              onPressed: _fecho == null ? null : _exportarPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            OutlinedButton.icon(
              onPressed: _escolherMes,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('${_meses[_mes - 1]} de $_ano'),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()))
            else if (_erro != null)
              Text(_erro!, style: const TextStyle(color: Colors.red))
            else if (_fecho != null)
              ..._conteudo(_fecho!),
          ],
        ),
      ),
    );
  }

  List<Widget> _conteudo(Map<String, dynamic> f) {
    final t = _mapa(f['totais']);
    final fin = _mapa(f['para_as_financas']);
    final metodo = _mapa(t['por_metodo']);
    final serv = _mapa(f['servicos_totais']);
    final tvde = _mapa(f['tvde_outros_motoristas']);
    final mand = _mapa(f['modelo_a_partir_de_2026_10']);
    return [
      _secao('Resumo do mês', [
        _linha('Pedidos entregues (reais)', '${t['pedidos_entregues'] ?? 0}'),
        _linha('Pago pelos clientes', _eur(t['pago_pelos_clientes'])),
        _linha('Custo da mercadoria', _eur(t['custo_mercadoria'])),
        _linha('Receita própria da Bora', _eur(t['receita_propria_bora']), forte: true),
        _linha('Pago a estafetas', _eur(t['pago_a_estafetas'])),
        _linha('Lucro', _eur(t['lucro']), forte: true),
        if (_n(t['pedidos_com_custo_estimado']) > 0)
          _nota('${t['pedidos_com_custo_estimado']} pedido(s) sem talão — custo estimado pelo catálogo.'),
        const Divider(),
        for (final e in metodo.entries)
          _linha('${_nomeMetodo(e.key)} (${_mapa(e.value)['pedidos']})',
              '${_eur(_mapa(e.value)['pago'])}${_n(_mapa(e.value)['stripe_estimado']) > 0 ? ' · Stripe ~${_eur(_mapa(e.value)['stripe_estimado'])}' : ''}'),
        const Divider(),
        _linha('Marcações (serviços)', '${serv['marcacoes'] ?? 0} · ${_eur(serv['pago_pelos_clientes'])}'),
        _linha('Serviços: Bora reteve', _eur(serv['bora_reteve'])),
        _linha('Serviços: taxa Stripe', _eur(serv['taxa_stripe'])),
        _linha('TVDE de outros motoristas (parte Bora)',
            '${_eur(tvde['parte_bora'])} · ${tvde['corridas'] ?? 0} corridas'),
      ]),
      _secao('Para as Finanças', [
        Text((fin['regime'] ?? '').toString(),
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        for (final e in _mapa(fin['rubricas']).entries)
          _linha(_nomeRubrica(e.key), _eur(e.value)),
        _linha('Total a declarar', _eur(fin['total_a_declarar']), forte: true),
        const SizedBox(height: 8),
        const Text('Faturas-recibo a emitir',
            style: TextStyle(fontWeight: FontWeight.w700)),
        for (final x in _lista(fin['faturas_recibo']))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${x['destinatario']}'),
            subtitle: Text(x['nif'] != null
                ? 'NIF ${x['nif']} · ${x['descricao']}'
                : (x['falta_nif'] == true
                    ? 'FALTA NIF · ${x['descricao']}'
                    : '${x['descricao']}')),
            trailing: Text(_eur(x['valor']),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        const SizedBox(height: 8),
        SelectableText((fin['texto'] ?? '').toString(),
            style: const TextStyle(fontSize: 13, height: 1.4)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: (fin['texto'] ?? '').toString()));
              _aviso('Texto copiado.');
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar texto'),
          ),
        ),
      ]),
      _secao('Parceiros', [
        for (final p in _lista(f['parceiros'])) _parceiro(p),
        if (_lista(f['parceiros']).isEmpty) _nota('Nenhuma loja parceira com pedidos neste mês.'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _reenviar(),
            icon: const Icon(Icons.forward_to_inbox_outlined),
            label: const Text('Reenviar extrato a todas'),
          ),
        ),
        for (final s in _lista(f['servicos']))
          _linha('${s['nome']} (serviços · ${s['marcacoes']} marc.)',
              '${_eur(s['liquido_prestador'])} · ${s['estado'] == 'paid' ? 'pago' : s['estado']}'),
      ]),
      _secao('Estafetas', [
        for (final e in _lista(f['estafetas']))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${e['nome'] ?? e['user_id']} · ${e['entregas']} entregas'),
            subtitle: Text(
                'Dinheiro em mão ${_eur(e['dinheiro_recebido_em_mao'])} · talões ${_eur(e['taloes_adiantados'])}'),
            trailing: Text(_eur(e['ganho']),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        if (_recibos.isNotEmpty) ...[
          const Divider(),
          Text(_modeloNovo
              ? 'Recibos verdes dos estafetas'
              : 'Recibos verdes (o modelo começa a 01/10/2026 — este mês é só referência)',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final r in _recibos)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  r['recibo_passado'] == true ? Icons.check_circle : Icons.pending_outlined,
                  color: r['recibo_passado'] == true ? AppColors.primary : Colors.orange),
              title: Text('${r['nome'] ?? '?'} — ${_eur(r['total_a_faturar'])}'),
              subtitle: Text(r['recibo_passado'] == true
                  ? 'Recibo n.º ${r['recibo_numero']} de ${r['recibo_data']}'
                  : 'NIF ${r['nif'] ?? 'em falta'} · atividade ${r['atividade_aberta'] == true ? 'confirmada' : 'por confirmar'} · recibo por passar'),
            ),
        ],
      ]),
      _secao('Pedidos no prejuízo', [
        for (final p in _lista(f['pedidos_no_prejuizo']))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${p['loja']} · ${p['data']}'),
            subtitle: Text(
                '${p['motivo']}\nPago ${_eur(p['pago'])} · mercadoria ${_eur(p['mercadoria'])} · estafeta ${_eur(p['estafeta'])}'),
            isThreeLine: true,
            trailing: Text(_eur(p['resultado']),
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    AdminOrderDetailScreen(orderId: p['order_id'].toString()))),
          ),
        if (_lista(f['pedidos_no_prejuizo']).isEmpty) _nota('Nenhum pedido no prejuízo.'),
      ]),
      _secao('Faturas da Bora por pedido', [
        if (!_modeloNovo)
          _nota('Começa em 01/10/2026. Setembro foi declarado à mão (4 faturas-recibo).')
        else ...[
          _nota((_faturas?['nota'] ?? '').toString()),
          for (final d in _lista(_faturas?['por_dia']))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${d['data']} · ${d['documentos']} documento(s)'),
              subtitle: Text(_n(d['por_lancar']) > 0
                  ? '${d['por_lancar']} por lançar no Portal'
                  : 'Tudo lançado'),
              trailing: Text(_eur(d['total']),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: _n(d['por_lancar']) > 0
                  ? () => _marcarDia(d['data'].toString())
                  : null,
            ),
          if (_lista(_faturas?['por_dia']).isEmpty) _nota('Ainda sem pedidos entregues neste mês.'),
        ],
      ]),
      _secao('Modelo novo (a partir de 01/10/2026)', [
        _linha('Receita Bora', _eur(mand['receita_bora']), forte: true),
        for (final e in _mapa(mand['cobrado_por_conta_de_terceiros']).entries)
          _linha('Cobrado por conta de terceiros: ${_nomeRubrica(e.key)}', _eur(e.value)),
        _nota((mand['nota'] ?? '').toString()),
      ]),
      _secao('DAC7', [
        _nota('Relatório anual das plataformas digitais (vendedores e prestadores: nome, NIF, morada, total por trimestre, n.º de operações). Só prepara o ficheiro — não envia nada.'),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _exportarDac7,
            icon: const Icon(Icons.file_download_outlined),
            label: Text('Exportar DAC7 $_ano'),
          ),
        ),
      ]),
    ];
  }

  Widget _parceiro(Map<String, dynamic> p) {
    final ext = _mapa(p['extrato']);
    final estado = ext['estado']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${p['nome']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${p['pedidos']} pedidos · vendas ${_eur(p['vendas_brutas'])} · comissão ${_eur(p['comissao_total'])}'),
            Text('Parte da loja ${_eur(p['parte_loja'])} · pago no mês ${_eur(p['pago_no_mes'])} · pendente ${_eur(p['pendente'])}'),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  estado == 'sent' ? Icons.mark_email_read_outlined : Icons.mail_outline,
                  size: 18,
                  color: estado == 'sent' ? AppColors.primary : Colors.black45,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    estado == null
                        ? 'Extrato ainda não enviado'
                        : estado == 'sent'
                            ? 'Extrato enviado'
                            : 'Extrato: $estado${ext['erro'] != null ? ' — ${ext['erro']}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => _reenviar(
                      partnerId: p['partner_id']?.toString(),
                      nome: p['nome']?.toString()),
                  child: Text(estado == 'sent' ? 'Reenviar' : 'Enviar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _nomeMetodo(String k) => switch (k) {
        'cash' => 'Dinheiro',
        'mbway' => 'MB Way',
        'card' => 'Cartão',
        _ => k,
      };

  static String _nomeRubrica(String k) => switch (k) {
        'entrega' => 'Entrega',
        'taxa_servico' => 'Taxa de serviço',
        'sacos' => 'Sacos',
        'taxa_pedido_pequeno' => 'Taxa de pedido pequeno',
        'comissao_lojas_parceiras' => 'Comissão das lojas parceiras',
        'margem_nao_parceiros' => 'Margem dos não-parceiros',
        'ajustes_descontos' => 'Ajustes e descontos (tokens/carteira)',
        'estafetas' => 'estafetas',
        'lojas_parceiras' => 'lojas parceiras',
        'mercadoria_nao_parceiros' => 'mercadoria (não-parceiros)',
        _ => k,
      };

  Widget _secao(String titulo, List<Widget> filhos) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titulo,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...filhos,
            ],
          ),
        ),
      );

  Widget _linha(String a, String b, {bool forte = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(a)),
            Text(b,
                style: TextStyle(
                    fontWeight: forte ? FontWeight.w800 : FontWeight.w500,
                    color: forte ? AppColors.primary : null)),
          ],
        ),
      );

  Widget _nota(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(s, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      );
}
