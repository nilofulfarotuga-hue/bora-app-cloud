// Contas claras (20/09/2026) — A FOLHA DO DONO (painel admin, PT-BR).
//
// Responde no dia e no mês: quanto entrou e por que meio, quanto saiu, quanto
// está retido, a quem a Bora deve e quem deve à Bora — com nome, valor e o botão
// de marcar pago. Tudo vem de UMA RPC (admin_extrato_dono); a tela não calcula
// nada. Valor que o servidor não souber aparece como "—".
//
// Botões: acerto de estafeta → admin_marcar_acerto_pago; acerto de parceiro →
// admin_set_partner_settlement_status; talão → tela de Reembolsos (dois caminhos);
// carteira negativa → perdoar dívida (admin_forgive_wallet_debt). TVDE não tem
// botão porque ainda não existe acerto de TVDE (achado desta missão).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import 'admin_receipts_screen.dart';
import 'admin_vigia_dinheiro_screen.dart';

class AdminExtratoDonoScreen extends StatefulWidget {
  const AdminExtratoDonoScreen({super.key});

  @override
  State<AdminExtratoDonoScreen> createState() => _AdminExtratoDonoScreenState();
}

enum _Periodo { hoje, semana, mes, personalizado }

class _AdminExtratoDonoScreenState extends State<AdminExtratoDonoScreen> {
  _Periodo _periodo = _Periodo.mes;
  DateTime _de = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _ate = DateTime.now();
  Map<String, dynamic>? _x;
  bool _loading = true;
  String? _erro;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _dataPt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// "12,34 €" a partir de cêntimos do servidor; null → "—".
  static String eur(dynamic cents) {
    if (cents == null) return '—';
    final n = (cents as num).toInt();
    final abs = n.abs();
    return '${n < 0 ? '-' : ''}${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')} €';
  }

  void _setPeriodo(_Periodo p) {
    final hoje = DateTime.now();
    setState(() {
      _periodo = p;
      switch (p) {
        case _Periodo.hoje:
          _de = DateTime(hoje.year, hoje.month, hoje.day);
          _ate = _de;
          break;
        case _Periodo.semana:
          final seg = DateTime(hoje.year, hoje.month, hoje.day)
              .subtract(Duration(days: hoje.weekday - 1));
          _de = seg;
          _ate = DateTime(hoje.year, hoje.month, hoje.day);
          break;
        case _Periodo.mes:
          _de = DateTime(hoje.year, hoje.month, 1);
          _ate = DateTime(hoje.year, hoje.month, hoje.day);
          break;
        case _Periodo.personalizado:
          break;
      }
    });
    _load();
  }

  Future<void> _escolherDatas() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _de, end: _ate),
    );
    if (r == null) return;
    setState(() {
      _periodo = _Periodo.personalizado;
      _de = r.start;
      _ate = r.end;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final r = await Supabase.instance.client.rpc('admin_extrato_dono',
          params: {'p_de': _iso(_de), 'p_ate': _iso(_ate)});
      final m = Map<String, dynamic>.from(r as Map);
      if (m['ok'] != true) throw Exception(m['error'] ?? 'sem resposta');
      if (!mounted) return;
      setState(() {
        _x = m;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _erro = e.toString();
      });
    }
  }

  // ─── ações ──────────────────────────────────────────────────────────────

  Future<void> _marcarPago(Map<String, dynamic> l, {required bool boraPaga}) async {
    final accao = l['accao'] as Map?;
    final tipo = l['tipo'] as String?;
    if (tipo == 'talao') {
      await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdminReceiptsScreen()));
      _load();
      return;
    }
    if (accao == null) return;
    final rpc = accao['rpc'] as String? ?? '';
    final metodoCtrl = TextEditingController(text: 'mbway');
    final refCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(boraPaga ? 'Marcar como pago' : 'Marcar como recebido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l['quem'] ?? '—'} · ${eur(l['cents'])}\n${l['motivo'] ?? ''}'),
            const SizedBox(height: 12),
            if (rpc.startsWith('admin_marcar_acerto_pago'))
              TextField(
                controller: metodoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Método (mbway / cash / transferencia)',
                    border: OutlineInputBorder()),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                  labelText: 'Referência (opcional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final sb = Supabase.instance.client;
      if (rpc.startsWith('admin_marcar_acerto_pago')) {
        await sb.rpc('admin_marcar_acerto_pago', params: {
          'p_user_id': accao['p_user_id'],
          'p_semana': accao['p_semana'],
          'p_metodo': metodoCtrl.text.trim().isEmpty ? null : metodoCtrl.text.trim(),
          'p_referencia': refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
        });
      } else if (rpc.startsWith('admin_set_partner_settlement_status')) {
        await sb.rpc('admin_set_partner_settlement_status', params: {
          'p_settlement_id': accao['p_settlement_id'],
          'p_new_status': accao['p_new_status'],
          'p_payment_reference': refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
          'p_notes': 'Marcado na folha do dono (contas claras)',
        });
      } else if (rpc.startsWith('admin_forgive_wallet_debt')) {
        await sb.rpc('admin_forgive_wallet_debt', params: {
          'p_user_id': accao['p_user_id'],
          'p_reason': refCtrl.text.trim().isEmpty
              ? 'Perdoado na folha do dono (contas claras)'
              : refCtrl.text.trim(),
        });
      } else {
        throw Exception('Sem ação automática para $rpc');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Feito ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportarCsv() async {
    final x = _x;
    if (x == null) return;
    final b = StringBuffer();
    b.writeln('secao;tipo;quem;motivo;valor_eur;quando;meio;ref');
    for (final l in (x['saidas'] as Map)['linhas'] as List) {
      final m = l as Map;
      b.writeln('saida;${m['tipo']};${m['quem']};;${eur(m['cents'])};${m['quando_txt'] ?? ''};${m['meio'] ?? ''};${m['ref'] ?? ''}');
    }
    for (final l in x['bora_deve'] as List) {
      final m = l as Map;
      b.writeln('bora_deve;${m['tipo']};${m['quem']};${m['motivo']};${eur(m['cents'])};;;${m['ref'] ?? ''}');
    }
    for (final l in x['devem_a_bora'] as List) {
      final m = l as Map;
      b.writeln('devem_a_bora;${m['tipo']};${m['quem']};${m['motivo']};${eur(m['cents'])};;;${m['ref'] ?? ''}');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copiado para a área de transferência')));
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Contas claras — a folha do dono'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              tooltip: 'Vigia do dinheiro (achados)',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminVigiaDinheiroScreen())),
              icon: const Icon(Icons.shield_outlined)),
          IconButton(
              tooltip: 'Exportar CSV',
              onPressed: _x == null ? null : _exportarCsv,
              icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: 'Atualizar',
              onPressed: _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          _periodoBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _erro != null
                    ? Center(child: Text('Erro: $_erro'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            _entradasCard(),
                            const SizedBox(height: 12),
                            _saidasCard(),
                            const SizedBox(height: 12),
                            _retidoCard(),
                            const SizedBox(height: 12),
                            _listaCard('A quem a Bora deve',
                                _x!['bora_deve'] as List, AppColors.error,
                                boraPaga: true),
                            const SizedBox(height: 12),
                            _listaCard('Quem deve à Bora',
                                _x!['devem_a_bora'] as List, AppColors.success,
                                boraPaga: false),
                            const SizedBox(height: 12),
                            _arcasCard(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _periodoBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                    label: const Text('Hoje'),
                    selected: _periodo == _Periodo.hoje,
                    onSelected: (_) => _setPeriodo(_Periodo.hoje)),
                ChoiceChip(
                    label: const Text('Esta semana'),
                    selected: _periodo == _Periodo.semana,
                    onSelected: (_) => _setPeriodo(_Periodo.semana)),
                ChoiceChip(
                    label: const Text('Este mês'),
                    selected: _periodo == _Periodo.mes,
                    onSelected: (_) => _setPeriodo(_Periodo.mes)),
                ActionChip(
                    label: Text(_periodo == _Periodo.personalizado
                        ? '${_dataPt(_de)} → ${_dataPt(_ate)}'
                        : 'Escolher datas'),
                    onPressed: _escolherDatas),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String t, {Widget? trailing}) => Row(children: [
        Expanded(
            child: Text(t,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
        if (trailing != null) trailing,
      ]);

  Widget _linha(String k, String v, {bool bold = false, Color? cor}) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
          Text(v,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: cor)),
        ]),
      );

  static String _meio(String? m) => switch (m) {
        'cash' => 'Dinheiro (nas mãos de quem entregou)',
        'mbway' => 'MB Way',
        'card' => 'Cartão',
        _ => m ?? '—',
      };

  static String _origem(String? o) => switch (o) {
        'pedido' => 'Pedidos (entregas)',
        'corrida' => 'Corridas TVDE',
        'limpeza' => 'Limpezas',
        'lavagem' => 'Lavagens',
        _ => o ?? '—',
      };

  Widget _entradasCard() {
    final e = Map<String, dynamic>.from(_x!['entradas'] as Map);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo('Entrou — ${_dataPt(_de)} → ${_dataPt(_ate)}',
              trailing: Text(eur(e['total_cents']),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.success))),
          const SizedBox(height: 6),
          _linha('Pago na app (cartão + MB Way) — chegou à Bora', eur(e['online_cents']), bold: true),
          _linha('Pago em dinheiro — ficou nas mãos de quem entregou',
              eur(e['dinheiro_em_mao_de_terceiros_cents']), bold: true),
          _linha('Parte da Bora registada nesses trabalhos', eur(e['parte_bora_registada_cents'])),
          const Divider(height: 18),
          const Text('Por meio', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          for (final m in (e['por_meio'] as List? ?? const []))
            _linha('${_meio((m as Map)['meio'] as String?)} · ${m['n']}', eur(m['cents'])),
          const SizedBox(height: 6),
          const Text('Por origem', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          for (final o in (e['por_origem'] as List? ?? const []))
            _linha('${_origem((o as Map)['origem'] as String?)} · ${o['n']} · parte da Bora ${eur(o['parte_bora_cents'])}',
                eur(o['cents'])),
        ]),
      ),
    );
  }

  Widget _saidasCard() {
    final s = Map<String, dynamic>.from(_x!['saidas'] as Map);
    final linhas = (s['linhas'] as List? ?? const []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo('Saiu — ${s['n'] ?? 0} pagamentos',
              trailing: Text(eur(s['total_cents']),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.error))),
          const SizedBox(height: 4),
          const Text(
              'Acertos pagos, reembolsos a clientes, talões pagos e créditos dados, no período.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const Divider(height: 18),
          if (linhas.isEmpty)
            const Text('Nada saiu neste período.',
                style: TextStyle(color: AppColors.textSecondary)),
          for (final l in linhas)
            _linha(
                '${(l as Map)['quando_txt'] ?? ''} · ${l['tipo']} · ${l['quem'] ?? '—'}'
                '${l['meio'] != null ? ' · ${l['meio']}' : ''}',
                eur(l['cents'])),
        ]),
      ),
    );
  }

  Widget _retidoCard() {
    final r = Map<String, dynamic>.from(_x!['retido'] as Map);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo('Retido (hoje, fora do período)'),
          _linha('A Bora deve e ainda não pagou', eur(r['bora_deve_cents']),
              bold: true, cor: AppColors.error),
          _linha('Devem à Bora e ainda não entrou', eur(r['devem_a_bora_cents']),
              bold: true, cor: AppColors.success),
          const SizedBox(height: 4),
          const Text(
              'Inclui os saldos das carteiras dos clientes (crédito que podem gastar) e o TVDE, que ainda não entra no acerto semanal.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _listaCard(String titulo, List linhas, Color cor, {required bool boraPaga}) {
    final total = linhas.fold<int>(0, (s, l) => s + (((l as Map)['cents'] as num?)?.toInt() ?? 0));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo(titulo,
              trailing: Text(eur(total),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: cor))),
          const Divider(height: 18),
          if (linhas.isEmpty)
            const Text('Ninguém.', style: TextStyle(color: AppColors.textSecondary)),
          for (final l in linhas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${(l as Map)['quem'] ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${l['motivo'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ]),
                ),
                Text(eur(l['cents']),
                    style: TextStyle(fontWeight: FontWeight.w800, color: cor)),
                const SizedBox(width: 8),
                if (l['accao'] != null || l['tipo'] == 'talao')
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _marcarPago(Map<String, dynamic>.from(l), boraPaga: boraPaga),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact),
                    child: Text(l['tipo'] == 'talao'
                        ? 'Ver talão'
                        : (boraPaga ? 'Marcar pago' : 'Marcar recebido')),
                  )
                else
                  Text(l['tipo'] == 'tvde' ? 'sem acerto TVDE' : '',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _arcasCard() {
    final a = Map<String, dynamic>.from(_x!['arcas'] as Map);
    final carteirasBatem = a['carteiras_saldo_cents'] == a['carteiras_historico_cents'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _titulo('As arcas, hoje'),
          _linha('Carteiras dos clientes — saldo', eur(a['carteiras_saldo_cents'])),
          _linha('Carteiras dos clientes — soma do histórico', eur(a['carteiras_historico_cents']),
              cor: carteirasBatem ? AppColors.success : AppColors.error),
          _linha('Estafetas — saldo vitalício das entregas', eur(a['estafetas_saldo_cents'])),
          _linha('TVDE — saldo (negativo = a Bora deve)', eur(a['tvde_saldo_cents'])),
          _linha('Comissão da Bora no livro-razão (pedidos pagos)', eur(a['ledger_comissao_cents'])),
          _linha('Achados do vigia por resolver', '${a['achados_abertos'] ?? '—'}',
              bold: true,
              cor: ((a['achados_abertos'] as num?) ?? 0) > 0 ? AppColors.warning : AppColors.success),
          if (!carteirasBatem)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                  'Carteiras: histórico e saldo não batem em pelo menos uma pessoa (a Isabel é caso conhecido, fechado por decisão sua). O vigia lista quem.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ),
        ]),
      ),
    );
  }
}
