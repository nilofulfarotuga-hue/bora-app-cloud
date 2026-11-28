// Admin — Planos de limpeza e Bora Empresas (missão limpeza-planos-empresas-2026-11-28, Bloco F).
// PT-BR, hora de Lisboa (regra painel-admin-limpo).
//
// RPCs (todas com _admin_op_guard no servidor):
//   • admin_cleaning_plans_summary()                          → contadores do mês
//   • admin_list_cleaning_plans(p_status, p_segment, p_search) → planos
//   • admin_cleaning_plan_detail(p_plan_id)                    → visitas, cobranças, devoluções, auditoria
//   • admin_cleaning_plan_set_status(p_plan_id, p_status, p_motivo) → pausar/retomar/cancelar (auditado)
//   • admin_list_cleaning_plan_charges(p_status)               → cobranças (pago / falhou / devolvido)
//   • admin_set_cleaning_plan_price(...)                       → tabela de preços (auditado)
//   • admin_cleaners_activity_status()                         → código de atividade das profissionais
// Lê DEFENSIVAMENTE: enquanto o SQL do Bloco B não estiver aplicado, mostra o erro e não parte.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../utils/hora_lisboa_ext.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

String _eur(Object? c) {
  final n = c is num ? c : num.tryParse('${c ?? 0}') ?? 0;
  return '€ ${(n / 100).toStringAsFixed(2).replaceAll('.', ',')}';
}

String _quando(Object? iso) {
  final d = iso == null ? null : DateTime.tryParse('$iso');
  if (d == null) return '—';
  final l = d.toLisboa();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

const _estadosPlano = {
  'active': 'Ativo',
  'paused': 'Pausado',
  'pending_card': 'Sem cartão',
  'cancelled': 'Cancelado',
  'completed': 'Concluído',
};

const _estadosCobranca = {
  'scheduled': 'Agendada (aviso enviado)',
  'waiting_cleaner': 'Sem profissional (não cobra)',
  'pending': 'Pronta para cobrar',
  'processing': 'Cobrando',
  'succeeded': 'Pago',
  'failed': 'Falhou (vai tentar de novo)',
  'requires_action': 'Cliente precisa confirmar (3D Secure)',
  'failed_final': 'Falhou de vez',
  'cancelled': 'Sem cobrança',
};

class AdminCleaningPlansScreen extends StatelessWidget {
  const AdminCleaningPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: BoraScreenAppBar(
          title: 'Planos de limpeza e Bora Empresas',
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: 'Planos'),
            Tab(text: 'Cobranças'),
            Tab(text: 'Preços'),
            Tab(text: 'Código de atividade'),
          ]),
        ),
        body: TabBarView(children: [
          _AbaPlanos(),
          _AbaCobrancas(),
          _AbaPrecos(),
          _AbaAtividade(),
        ]),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro(this.msg, this.onRetry);
  final String msg;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Não foi possível carregar: $msg', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
          ]),
        ),
      );
}

// ── Planos ──────────────────────────────────────────────────────────────────

class _AbaPlanos extends StatefulWidget {
  const _AbaPlanos();
  @override
  State<_AbaPlanos> createState() => _AbaPlanosState();
}

class _AbaPlanosState extends State<_AbaPlanos> {
  final _sb = Supabase.instance.client;
  Map<String, dynamic>? _resumo;
  List<Map<String, dynamic>> _planos = const [];
  String? _status = 'active';
  String? _segmento;
  final _pesquisa = TextEditingController();
  bool _loading = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pesquisa.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final r = await _sb.rpc('admin_cleaning_plans_summary');
      final l = await _sb.rpc('admin_list_cleaning_plans', params: {
        'p_status': _status,
        'p_segment': _segmento,
        'p_search': _pesquisa.text.trim().isEmpty ? null : _pesquisa.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _resumo = r is Map ? Map<String, dynamic>.from(r) : null;
        _planos = [for (final p in (l as List? ?? const [])) if (p is Map) Map<String, dynamic>.from(p)];
      });
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mudarEstado(Map<String, dynamic> p, String estado) async {
    final motivo = TextEditingController();
    final rotulo = {'paused': 'Pausar', 'active': 'Retomar', 'cancelled': 'Cancelar'}[estado]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$rotulo o plano?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(estado == 'active'
              ? 'O plano volta a gerar as limpezas e a cobrar 24 h antes de cada uma (com profissional confirmada).'
              : 'As limpezas a mais de 24 h são desmarcadas. As já pagas voltam ao CARTÃO do cliente (estorno automático pela Stripe). O cliente recebe aviso.'),
          TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (fica na auditoria)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(rotulo)),
        ],
      ),
    );
    if (ok != true || motivo.text.trim().isEmpty) return;
    try {
      await _sb.rpc('admin_cleaning_plan_set_status',
          params: {'p_plan_id': p['id'], 'p_status': estado, 'p_motivo': motivo.text.trim()});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Plano: $rotulo feito.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  void _detalhe(Map<String, dynamic> p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DetalhePlano(planId: '${p['id']}')));
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) return _Erro(_erro!, _load);
    final r = _resumo ?? const {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          Wrap(spacing: Spacing.sm, runSpacing: Spacing.sm, children: [
            _Cartao('Ativos', '${r['ativos'] ?? 0}', 'casa ${r['ativos_casa'] ?? 0} · empresa ${r['ativos_empresa'] ?? 0}'),
            _Cartao('Cobrado no mês', _eur(r['cobrado_mes_cents']), 'devolvido ${_eur(r['devolvido_mes_cents'])}'),
            _Cartao('Cobranças com problema', '${r['cobrancas_falhadas'] ?? 0}', 'falharam de vez no mês: ${r['cobrancas_falhadas_de_vez_mes'] ?? 0}'),
            _Cartao('Sem profissional a 24 h', '${r['sem_profissional'] ?? 0}', 'não cobradas até alguém aceitar'),
            _Cartao('Devoluções pendentes', '${r['devolucoes_pendentes'] ?? 0}', 'falhadas: ${r['devolucoes_falhadas'] ?? 0}'),
            _Cartao('Sem cartão / pausados', '${r['sem_cartao'] ?? 0} / ${r['pausados'] ?? 0}', 'cancelados: ${r['cancelados'] ?? 0}'),
          ]),
          const SizedBox(height: Spacing.lg),
          Wrap(spacing: Spacing.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<String?>(
              value: _status,
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos os estados')),
                for (final e in _estadosPlano.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) {
                setState(() => _status = v);
                _load();
              },
            ),
            DropdownButton<String?>(
              value: _segmento,
              items: const [
                DropdownMenuItem(value: null, child: Text('Casas e empresas')),
                DropdownMenuItem(value: 'casa', child: Text('Só casas')),
                DropdownMenuItem(value: 'empresa', child: Text('Só Bora Empresas')),
              ],
              onChanged: (v) {
                setState(() => _segmento = v);
                _load();
              },
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _pesquisa,
                decoration: const InputDecoration(labelText: 'Buscar (nome, email, NIF, morada)', isDense: true),
                onSubmitted: (_) => _load(),
              ),
            ),
            IconButton(
              tooltip: 'Exportar (CSV) para a área de transferência',
              icon: const Icon(Icons.download),
              onPressed: () {
                final linhas = ['id;cliente;email;segmento;frequencia;estado;preco_visita;pago;empresa;nif'];
                for (final p in _planos) {
                  linhas.add([p['id'], p['client_name'], p['client_email'], p['segment'], p['frequency'], p['status'],
                    p['total_per_visit_cents'], p['paid_cents'], p['company_name'] ?? '', p['billing_nif'] ?? ''].join(';'));
                }
                Clipboard.setData(ClipboardData(text: linhas.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_planos.length} planos copiados (CSV).')));
              },
            ),
          ]),
          const SizedBox(height: Spacing.sm),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _planos.isEmpty) const Padding(padding: EdgeInsets.all(Spacing.lg), child: Text('Nenhum plano com estes filtros.')),
          for (final p in _planos)
            Card(
              child: ListTile(
                onTap: () => _detalhe(p),
                title: Text('${p['segment'] == 'empresa' ? 'Empresa · ${p['company_name'] ?? ''}' : 'Casa'} · ${p['client_name'] ?? p['client_email'] ?? ''}'),
                subtitle: Text('${p['label'] ?? p['frequency']} · ${_eur(p['total_per_visit_cents'])}/limpeza · '
                    '${_estadosPlano[p['status']] ?? p['status']} · próxima ${_quando(p['next_visit_at'])} · '
                    'profissional ${p['cleaner_name'] ?? '—'} · pago ${_eur(p['paid_cents'])}'
                    '${(p['charges_failing'] ?? 0) != 0 ? ' · ⚠ ${p['charges_failing']} cobrança(s) com problema' : ''}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (e) => _mudarEstado(p, e),
                  itemBuilder: (_) => [
                    if (p['status'] == 'active') const PopupMenuItem(value: 'paused', child: Text('Pausar')),
                    if (p['status'] == 'paused') const PopupMenuItem(value: 'active', child: Text('Retomar')),
                    if (p['status'] == 'active' || p['status'] == 'paused' || p['status'] == 'pending_card')
                      const PopupMenuItem(value: 'cancelled', child: Text('Cancelar')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao(this.titulo, this.valor, this.sub);
  final String titulo;
  final String valor;
  final String sub;
  @override
  Widget build(BuildContext context) => Container(
        width: 210,
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(sub, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ]),
      );
}

class _DetalhePlano extends StatefulWidget {
  const _DetalhePlano({required this.planId});
  final String planId;
  @override
  State<_DetalhePlano> createState() => _DetalhePlanoState();
}

class _DetalhePlanoState extends State<_DetalhePlano> {
  Map<String, dynamic>? _d;
  String? _erro;

  @override
  void initState() {
    super.initState();
    Supabase.instance.client.rpc('admin_cleaning_plan_detail', params: {'p_plan_id': widget.planId}).then((r) {
      if (mounted) setState(() => _d = r is Map ? Map<String, dynamic>.from(r) : null);
    }).catchError((Object e) {
      if (mounted) setState(() => _erro = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Plano de limpeza'),
      body: _erro != null
          ? Center(child: Text(_erro!))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(Spacing.lg), children: [
                  Text('${d['client']?['name'] ?? ''} · ${d['client']?['email'] ?? ''} · ${d['client']?['phone'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${d['label'] ?? d['frequency']} · dias ${d['days_of_week']} · ${d['visit_time']} · ${d['hours']} h · equipe ${d['team_size']}'),
                  Text('Cliente paga ${_eur(d['client_cents_per_hour'])}/h · profissional recebe ${_eur(d['pro_cents_per_hour'])}/h (congelado no plano)'),
                  Text('Cobrança: ${d['billing_mode'] == 'monthly' ? 'o mês de uma vez' : 'a cada limpeza (24 h antes)'} · cartão ${d['card_brand'] ?? ''} •••• ${d['card_last4'] ?? '—'} · conta Stripe ${d['stripe_account']}'),
                  if (d['segment'] == 'empresa')
                    Text('Empresa ${d['company_name']} · NIF ${d['billing_nif']} · ${d['billing_email']} · ${d['space_type']} · ${d['area_m2'] ?? '?'} m² · tarefas ${d['tasks']}'),
                  Text('Morada: ${d['address_street']}, ${d['address_city']} ${d['address_postal']}'),
                  const Divider(),
                  const Text('Visitas', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final v in (d['all_visits'] as List? ?? const []))
                    Text('${_quando(v['scheduled_at'])} · vaga ${v['slot']} · ${v['status']} · ${v['payment_status']} · '
                        'cliente ${_eur(v['share_cents'])} · profissional ${_eur(v['cleaner_earnings_cents'])} · Bora ${_eur(v['bora_fee_cents'])}'
                        '${v['cleaner_name'] != null ? ' · ${v['cleaner_name']}' : ''}${v['cancel_reason'] != null ? ' · ${v['cancel_reason']}' : ''}'),
                  const Divider(),
                  const Text('Cobranças', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final c in (d['all_charges'] as List? ?? const []))
                    Text('${_quando(c['created_at'])} · ${c['kind']} · ${_eur(c['amount_cents'])} · ${_estadosCobranca[c['status']] ?? c['status']} · '
                        'tentativas ${c['attempts']}${c['last_error'] != null ? ' · ${c['last_error']}' : ''}${c['stripe_payment_intent_id'] != null ? ' · ${c['stripe_payment_intent_id']}' : ''}'),
                  const Divider(),
                  const Text('Devoluções', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final r in (d['all_refunds'] as List? ?? const []))
                    Text('${_quando(r['created_at'])} · ${r['method'] == 'wallet' ? 'Carteira' : 'Cartão'} · ${_eur(r['amount_cents'])} · ${r['status']} · ${r['reason'] ?? ''}'),
                  const Divider(),
                  const Text('Auditoria', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final a in (d['audit'] as List? ?? const []))
                    Text('${_quando(a['at'])} · ${a['admin_email'] ?? ''} · ${a['action']} · ${a['details']}'),
                ]),
    );
  }
}

// ── Cobranças ───────────────────────────────────────────────────────────────

class _AbaCobrancas extends StatefulWidget {
  const _AbaCobrancas();
  @override
  State<_AbaCobrancas> createState() => _AbaCobrancasState();
}

class _AbaCobrancasState extends State<_AbaCobrancas> {
  String? _status;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    try {
      final l = await Supabase.instance.client.rpc('admin_list_cleaning_plan_charges', params: {'p_status': _status});
      if (mounted) setState(() => _rows = [for (final r in (l as List? ?? const [])) if (r is Map) Map<String, dynamic>.from(r)]);
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) return _Erro(_erro!, _load);
    return ListView(padding: const EdgeInsets.all(Spacing.lg), children: [
      DropdownButton<String?>(
        value: _status,
        items: [
          const DropdownMenuItem(value: null, child: Text('Todas')),
          for (final e in _estadosCobranca.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          setState(() => _status = v);
          _load();
        },
      ),
      if (_loading) const LinearProgressIndicator(),
      if (!_loading && _rows.isEmpty) const Padding(padding: EdgeInsets.all(Spacing.lg), child: Text('Nenhuma cobrança.')),
      for (final c in _rows)
        ListTile(
          title: Text('${_eur(c['amount_cents'])} · ${_estadosCobranca[c['status']] ?? c['status']}'
              '${(c['refunded_cents'] ?? 0) != 0 ? ' · devolvido ${_eur(c['refunded_cents'])}' : ''}'),
          subtitle: Text('${c['client_name'] ?? c['client_email'] ?? ''}${c['company_name'] != null ? ' · ${c['company_name']}' : ''} · '
              '${c['kind'] == 'month' ? 'mês' : 'limpeza'} · criada ${_quando(c['created_at'])} · cobrar depois de ${_quando(c['charge_after'])}'
              '${c['paid_at'] != null ? ' · paga ${_quando(c['paid_at'])}' : ''} · tentativas ${c['attempts']}'
              '${c['last_error'] != null ? ' · ${c['last_error']}' : ''}'),
        ),
    ]);
  }
}

// ── Preços (editável, auditado) ─────────────────────────────────────────────

class _AbaPrecos extends StatefulWidget {
  const _AbaPrecos();
  @override
  State<_AbaPrecos> createState() => _AbaPrecosState();
}

class _AbaPrecosState extends State<_AbaPrecos> {
  List<Map<String, dynamic>> _rows = const [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Supabase.instance.client.from('cleaning_plan_prices').select().order('segment').order('sort');
      if (mounted) setState(() => _rows = [for (final r in l) Map<String, dynamic>.from(r)]);
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  Future<void> _editar(Map<String, dynamic> r) async {
    final cli = TextEditingController(text: ((r['client_cents_per_hour'] as num) / 100).toStringAsFixed(2));
    final pro = TextEditingController(text: ((r['pro_cents_per_hour'] as num) / 100).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r['segment'] == 'empresa' ? 'Bora Empresas' : 'Casas'} · ${r['label_pt']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('⚠️ Mexe em dinheiro. Vale só para PLANOS NOVOS (os planos existentes ficam com o preço congelado). A mudança fica na auditoria.'),
          TextField(controller: cli, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cliente paga (€/h)')),
          TextField(controller: pro, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Profissional recebe (€/h)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    int? cents(String s) {
      final v = double.tryParse(s.replaceAll(',', '.').trim());
      return v == null ? null : (v * 100).round();
    }
    final c = cents(cli.text), p = cents(pro.text);
    if (c == null || p == null) return;
    try {
      await Supabase.instance.client.rpc('admin_set_cleaning_plan_price', params: {
        'p_segment': r['segment'], 'p_frequency': r['frequency'],
        'p_client_cents_per_hour': c, 'p_pro_cents_per_hour': p, 'p_min_hours': null,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) return _Erro(_erro!, _load);
    return ListView(padding: const EdgeInsets.all(Spacing.lg), children: [
      const Text('Preço por hora por frequência. A Bora fica com a diferença; a taxa da Stripe é paga pela Bora.',
          style: TextStyle(color: AppColors.textSecondary)),
      for (final r in _rows)
        ListTile(
          title: Text('${r['segment'] == 'empresa' ? 'Bora Empresas' : 'Casas'} · ${r['label_pt']}'),
          subtitle: Text('Cliente ${_eur(r['client_cents_per_hour'])}/h · profissional ${_eur(r['pro_cents_per_hour'])}/h · '
              'Bora ${_eur((r['client_cents_per_hour'] as num) - (r['pro_cents_per_hour'] as num))}/h · mínimo ${r['min_hours']} h'
              '${r['products_included'] == true ? ' · produtos incluídos' : ''}'),
          trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _editar(r)),
        ),
    ]);
  }
}

// ── Código de atividade das profissionais (Bloco E) ─────────────────────────

class _AbaAtividade extends StatefulWidget {
  const _AbaAtividade();
  @override
  State<_AbaAtividade> createState() => _AbaAtividadeState();
}

class _AbaAtividadeState extends State<_AbaAtividade> {
  List<Map<String, dynamic>> _rows = const [];
  String? _erro;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Supabase.instance.client.rpc('admin_cleaners_activity_status');
      if (mounted) setState(() => _rows = [for (final r in (l as List? ?? const [])) if (r is Map) Map<String, dynamic>.from(r)]);
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) return _Erro(_erro!, _load);
    return ListView(padding: const EdgeInsets.all(Spacing.lg), children: [
      const Text('CAE certo: 81210 (limpeza geral em edifícios). A aprovação continua sendo sua; ninguém já aprovado é bloqueado.',
          style: TextStyle(color: AppColors.textSecondary)),
      for (final r in _rows)
        ListTile(
          leading: Icon(r['codigo_certo'] == true ? Icons.verified : Icons.warning_amber,
              color: r['codigo_certo'] == true ? AppColors.primary : AppColors.warning),
          title: Text('${r['name'] ?? ''} · ${r['approval_status'] ?? ''}'),
          subtitle: Text('${r['estado'] ?? ''} · códigos ${(r['codigos'] as List? ?? const []).join(', ')}'
              '${r['verificado_em'] != null ? ' · lido ${_quando(r['verificado_em'])}' : ''}'),
        ),
    ]);
  }
}
