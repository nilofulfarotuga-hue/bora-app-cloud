import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import '../../utils/hora_lisboa_ext.dart';

/// Limpeza doméstica — Admin: todas as reservas de limpeza.
/// Filtros por estado/pesquisa, cancelar (admin_cancel_cleaning) e
/// reagendar (admin_reschedule_cleaning). Idioma: PT-BR.
class AdminCleaningBookingsScreen extends StatefulWidget {
  const AdminCleaningBookingsScreen({super.key, this.pesquisaInicial});

  /// Texto já posto na pesquisa (ex.: o email do cliente, vindo da ficha
  /// "Reservas" do cliente).
  final String? pesquisaInicial;

  @override
  State<AdminCleaningBookingsScreen> createState() =>
      _AdminCleaningBookingsScreenState();
}

class _AdminCleaningBookingsScreenState
    extends State<AdminCleaningBookingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  String? _statusFilter;
  final _searchCtrl = TextEditingController();

  static const _statusLabels = <String, String>{
    'scheduled': 'Agendada',
    'accepted': 'Confirmada',
    'on_the_way': 'A caminho',
    'in_progress': 'Em andamento',
    'done': 'Aguarda cliente',
    'completed': 'Concluída',
    'cancelled_client': 'Cancelada (cliente)',
    'cancelled_cleaner': 'Cancelada (profissional)',
    'cancelled_no_cleaner': 'Cancelada (sem profissional)',
  };

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.pesquisaInicial ?? '';
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res =
        await Supabase.instance.client.rpc('admin_list_cleanings', params: {
      'p_status': _statusFilter,
      'p_search':
          _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    });
    final list = (res as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _cancel(Map<String, dynamic> b) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar esta limpeza?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Cancelamento administrativo: sem taxa para o cliente. '
                'Cliente e profissional são notificados.'),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Cancelar limpeza')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => Supabase.instance.client.rpc('admin_cancel_cleaning',
            params: {'p_booking_id': b['id'], 'p_reason': reasonCtrl.text}),
        'Limpeza cancelada.');
  }

  /// Avançar o estado quando a profissional esqueceu um botão (2026-10-03).
  /// RPC `admin_set_cleaning_status` — só avança, com motivo e auditoria. Não
  /// mexe em dinheiro: o pagamento só se liberta na confirmação (cliente ou
  /// automática às 24 h), como antes.
  Future<void> _advance(Map<String, dynamic> b) async {
    final status = (b['status'] as String?) ?? '';
    const ordem = ['accepted', 'on_the_way', 'in_progress', 'done'];
    const nomes = {
      'on_the_way': 'A caminho',
      'in_progress': 'Em andamento',
      'done': 'Terminada (cliente confirma)',
    };
    final i = ordem.indexOf(status);
    if (i < 0 || i >= ordem.length - 1) return;
    final opcoes = ordem.sublist(i + 1);
    var escolha = opcoes.last;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Avançar estado da limpeza'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in opcoes)
                RadioListTile<String>(
                  value: o,
                  groupValue: escolha,
                  title: Text(nomes[o] ?? o),
                  onChanged: (v) => setD(() => escolha = v ?? escolha),
                ),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                    labelText: 'Motivo (obrigatório)',
                    hintText: 'Ex.: a profissional confirmou por telefone'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Avançar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
        () => Supabase.instance.client.rpc('admin_set_cleaning_status', params: {
              'p_booking_id': b['id'],
              'p_to': escolha,
              'p_reason': reasonCtrl.text.trim(),
            }),
        'Estado atualizado.');
  }

  /// Conversa da limpeza (lista via admin_list_cleaning_messages, com
  /// auditoria). Desde 2026-10-03 a Bora também escreve
  /// (`admin_send_cleaning_message`) — cliente e profissional recebem push.
  Future<void> _viewChat(Map<String, dynamic> b) async {
    List<Map<String, dynamic>> msgs = const [];
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_cleaning_messages', params: {'p_booking_id': b['id']});
      msgs = ((res as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanizeAdminRpcError(e)),
          backgroundColor: AppColors.error));
      return;
    }
    if (!mounted) return;
    final msgCtrl = TextEditingController();
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conversa'),
        content: SizedBox(
          width: double.maxFinite,
          child: msgs.isEmpty
              ? const Text('Sem mensagens nesta limpeza.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in msgs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(
                          alignment: m['sender_role'] == 'client'
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: m['sender_role'] == 'client'
                                  ? AppColors.surface
                                  : AppColors.primaryWash,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  switch (m['sender_role']) {
                                    'client' => 'Cliente',
                                    'admin' => 'Bora',
                                    _ => 'Profissional',
                                  },
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSubtle),
                                ),
                                Text('${m['message'] ?? ''}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextField(
            controller: msgCtrl,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
                labelText: 'Escrever como Bora',
                hintText: 'Cliente e profissional recebem notificação'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Fechar')),
          FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Enviar')),
        ],
      ),
    );
    final texto = msgCtrl.text.trim();
    if (enviar != true || texto.isEmpty || !mounted) return;
    await _run(
        () => Supabase.instance.client.rpc('admin_send_cleaning_message',
            params: {'p_booking_id': b['id'], 'p_message': texto}),
        'Mensagem enviada.');
  }

  Future<void> _reschedule(Map<String, dynamic> b) async {
    final current =
        DateTime.tryParse(b['scheduled_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    final newAt =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _run(() => Supabase.instance.client.rpc('admin_reschedule_cleaning',
            params: {
          'p_booking_id': b['id'],
          'p_new_scheduled_at': newAt.toUtc().toIso8601String(),
        }),
        'Limpeza reagendada.');
  }

  /// Manda de novo o pedido de MB Way para o telemóvel do cliente (19/10/2026).
  /// RPC `cleaning_request_payment` → Edge `cleaning-request-payment`. O valor
  /// é sempre o total da reserva; nada aqui muda preços.
  Future<void> _requestPayment(Map<String, dynamic> b) async {
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client
          .rpc('cleaning_request_payment', params: {'p_booking_id': b['id']});
      if (!mounted) return;
      final r = (res is Map) ? Map<String, dynamic>.from(res) : const {};
      final ok = r['ok'] == true;
      final msg = ok
          ? 'Pedido MB Way disparado (${r['tentativa']}ª tentativa). Se já '
              'houver um pedido à espera do cliente, não é criado outro.'
          : switch (r['error']) {
              'not_requestable' =>
                'Esta limpeza não está pendente de pagamento em MB Way.',
              'vault_missing' => 'Falta a chave do servidor no cofre do banco.',
              _ => 'Não deu para pedir: ${r['error'] ?? 'erro desconhecido'}',
            };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: ok ? AppColors.primary : AppColors.error));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanizeAdminRpcError(e)),
          backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Exportar (CSV) as limpezas do filtro atual, com distância, taxa de
  /// deslocação e equipa (19/11/2026).
  Future<void> _exportar() async {
    final rows = await _future;
    if (!mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nada para exportar.')));
      return;
    }
    String eur(dynamic c) =>
        (((c as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',');
    await AdminExportService.instance.exportCsv(
      filename: 'bora_limpezas.csv',
      headers: const [
        'ID', 'Data', 'Estado', 'Cliente', 'Profissional', 'Cidade',
        'Pagamento', 'Estado pagamento', 'Total (EUR)', 'Ganho profissional (EUR)',
        'Bora (EUR)', 'Km de estrada', 'Taxa deslocação (EUR)',
        'Equipa (grupo)', 'Vaga', 'Nº profissionais', 'Parte da profissional (EUR)',
        'Total da equipa (EUR)',
      ],
      rows: rows
          .map((r) => <dynamic>[
                r['id'],
                r['scheduled_at'],
                r['status'],
                r['client_email'] ?? '',
                r['cleaner_name'] ?? '',
                r['address_city'] ?? '',
                r['payment_method'],
                r['payment_status'],
                eur(r['total_cents']),
                eur(r['cleaner_earnings_cents']),
                eur(r['bora_fee_cents']),
                r['travel_distance_km'] ?? '',
                eur(r['travel_fee_cents']),
                r['team_group_id'] ?? '',
                r['team_slot'] ?? 1,
                r['team_size'] ?? 1,
                eur(r['share_cents'] ?? r['total_cents']),
                eur(r['team_total_cents'] ?? r['total_cents']),
              ])
          .toList(),
      subject: 'Limpezas Bora',
    );
  }

  /// Equipa / atribuição à mão (19/11/2026): escolhe uma profissional
  /// aprovada para ESTA vaga (admin_assign_cleaning_cleaner, auditado).
  Future<void> _assign(Map<String, dynamic> b) async {
    List<Map<String, dynamic>> lista = const [];
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_cleaners', params: {'p_status': 'approved'});
      lista = ((res as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanizeAdminRpcError(e)),
          backgroundColor: AppColors.error));
      return;
    }
    if (!mounted) return;
    final vaga = (b['team_size'] as num? ?? 1) > 1
        ? ' (vaga ${b['team_slot']} de ${b['team_size']})'
        : '';
    final escolhida = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Atribuir profissional$vaga'),
        children: [
          for (final c in lista)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text(
                  '${c['name'] ?? '—'} · raio ${(c['service_radius_km'] as num?)?.round() ?? '—'} km'),
            ),
          if (lista.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nenhuma profissional aprovada.'),
            ),
        ],
      ),
    );
    if (escolhida == null || !mounted) return;
    await _run(
        () => Supabase.instance.client.rpc('admin_assign_cleaning_cleaner',
                params: {
                  'p_booking_id': b['id'],
                  'p_cleaner_id': escolhida['id'],
                  'p_motivo': 'painel admin',
                }),
        'Profissional atribuída: ${escolhida['name']}$vaga');
  }

  Future<void> _run(Future<dynamic> Function() fn, String successMsg) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMsg), backgroundColor: AppColors.primary));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(humanizeAdminRpcError(e)),
          backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Limpezas',
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar por estado',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _refresh();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Todas')),
              for (final e in _statusLabels.entries)
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Exportar (CSV)',
            onPressed: _exportar,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por e-mail, profissional, endereço ou ID…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _refresh();
                  },
                ),
              ),
              onSubmitted: (_) => _refresh(),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(Icons.error_outline,
                            size: 44, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('Erro:\n${snap.error}',
                            textAlign: TextAlign.center),
                      ],
                    );
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('Nenhuma limpeza neste filtro.',
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _BookingCard(
                      data: rows[i],
                      busy: _busy,
                      statusLabels: _statusLabels,
                      onCancel: () => _cancel(rows[i]),
                      onReschedule: () => _reschedule(rows[i]),
                      onViewChat: () => _viewChat(rows[i]),
                      onAdvance: () => _advance(rows[i]),
                      onRequestPayment: () => _requestPayment(rows[i]),
                      onAssign: () => _assign(rows[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.data,
    required this.busy,
    required this.statusLabels,
    required this.onCancel,
    required this.onReschedule,
    required this.onViewChat,
    required this.onAdvance,
    required this.onRequestPayment,
    required this.onAssign,
  });

  final Map<String, dynamic> data;
  final VoidCallback onAssign;
  final bool busy;
  final Map<String, String> statusLabels;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onViewChat;
  final VoidCallback onAdvance;
  final VoidCallback onRequestPayment;

  String _euro(dynamic cents) =>
      '€${(((cents as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? '';
    final active = const [
      'scheduled', 'accepted', 'on_the_way', 'in_progress'
    ].contains(status);
    final type = switch (data['cleaning_type']) {
      'deep' => 'Profunda',
      'post_works' => 'Pós-obras',
      _ => 'Standard',
    };
    final size = data['pricing_mode'] == 'hourly'
        ? '${data['hours'] ?? 0}h por hora'
        : switch (data['home_size']) {
            't0_t1' => 'T0/T1',
            't2' => 'T2',
            't3' => 'T3',
            't4plus' => 'T4+',
            _ => '—',
          };
    final payment = switch (data['payment_method']) {
      'card' => 'Cartão',
      'mbway' => 'MB Way',
      'premio' => 'Prêmio do check-in (Bora paga)',
      _ => 'Dinheiro',
    };
    // 19/10/2026: com MB Way/cartão a profissional só é chamada depois de pago.
    final porPagarMbway = data['payment_method'] == 'mbway' &&
        data['payment_status'] == 'unpaid' &&
        !status.startsWith('cancelled');

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cleaning_services,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$type · $size',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                _StatusChip(
                    label: statusLabels[status] ?? status,
                    active: active,
                    cancelled: status.startsWith('cancelled')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtDate(data['scheduled_at'])} · ${_euro(data['total_cents'])} · $payment '
              '(${data['payment_status'] ?? '—'})',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            Text(
              'Cliente: ${data['client_email'] ?? '—'}\n'
              'Profissional: ${data['cleaner_name'] ?? 'por atribuir'}\n'
              '${data['address_street'] ?? ''}, ${data['address_city'] ?? ''} '
              '${data['address_postal'] ?? ''}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
            // Limpeza longe (19/11/2026): km de ESTRADA e taxa de deslocação
            // (vai inteira para a profissional, já dentro do total).
            if (data['travel_distance_km'] != null ||
                ((data['travel_fee_cents'] as num?) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Distância: ${data['travel_distance_km'] ?? '—'} km de estrada · '
                  'taxa de deslocação ${_euro(data['travel_fee_cents'])}'
                  '${((data['team_size'] as num?) ?? 1) > 1 ? ' (por profissional)' : ''}',
                  key: const Key('admin_limpeza_deslocacao'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            // Equipa (19/11/2026): cada vaga é uma reserva; a vaga 1 tem o
            // total da equipa (o que o cliente paga) e as outras 0.
            if (((data['team_size'] as num?) ?? 1) > 1)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Equipa: vaga ${data['team_slot']} de ${data['team_size']} '
                  '(grupo ${(data['team_group_id'] as String? ?? '').split('-').first}) · '
                  'parte desta profissional ${_euro(data['share_cents'])} · '
                  'total da equipa ${_euro(data['team_total_cents'])}',
                  key: const Key('admin_limpeza_equipa'),
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            if ((data['recurrence'] as String? ?? 'single') != 'single')
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Recorrência: ${data['recurrence'] == 'weekly' ? 'semanal' : 'quinzenal'}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            if (data['payment_method'] != 'cash') _PagamentoLinha(data: data),
            // RASTRO DO PAGAMENTO (2026-09-05) — é isto que se olha quando um
            // cliente diz que foi cobrado duas vezes. A chave de idempotência é
            // a que impede a repetição de rede de criar uma segunda reserva; se
            // aparecerem DUAS reservas com a MESMA chave, isso é um bug nosso.
            // O id do pagamento é o que se cola na Stripe para ver a cobrança e
            // se já existe estorno. Tudo isto já vinha da RPC, só não se via.
            _RastroPagamento(
              paymentIntentId: data['stripe_payment_intent_id'] as String?,
              idempotencyKey: data['idempotency_key'] as String?,
              cancelFeeCents: data['cancel_fee_cents'],
              paymentStatus: data['payment_status'] as String?,
              totalCents: data['total_cents'],
              cancelReason: data['cancel_reason'] as String?,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onViewChat,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('Ver conversa'),
              ),
            ),
            if (const ['scheduled', 'accepted'].contains(status)) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onAssign,
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(data['cleaner_name'] == null
                      ? 'Atribuir profissional à mão'
                      : 'Trocar profissional'),
                ),
              ),
            ],
            if (porPagarMbway) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onRequestPayment,
                  icon: const Icon(Icons.phone_iphone, size: 18),
                  label: const Text('Pedir pagamento MB Way'),
                ),
              ),
            ],
            if (const ['accepted', 'on_the_way', 'in_progress']
                .contains(status)) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onAdvance,
                  icon: const Icon(Icons.fast_forward, size: 18),
                  label: const Text('Avançar estado (a profissional esqueceu)'),
                ),
              ),
            ],
            if (active) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onReschedule,
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: const Text('Reagendar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onCancel,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Cancelar'),
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

/// "Pagamento: pago / pedido enviado (n vezes, hora) / por pagar" (19/10/2026).
/// Com MB Way ou cartão, a profissional só é chamada quando isto diz "pago".
class _PagamentoLinha extends StatelessWidget {
  const _PagamentoLinha({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final ps = (data['payment_status'] as String?) ?? 'unpaid';
    final n = (data['payment_request_count'] as num?)?.toInt() ?? 0;
    final String texto;
    final Color cor;
    if (ps == 'held' || ps == 'released') {
      texto = 'pago';
      cor = AppColors.primary;
    } else if (ps != 'unpaid') {
      texto = ps;
      cor = AppColors.textSecondary;
    } else if (n > 0) {
      final vezes = n == 1 ? '1 vez' : '$n vezes';
      texto = 'pedido enviado ($vezes, último em '
          '${_fmtDate(data['payment_requested_at'])})';
      cor = AppColors.warning;
    } else {
      texto = 'por pagar';
      cor = AppColors.error;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('Pagamento: $texto',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: cor)),
    );
  }
}

/// Rótulo da linha do dinheiro que volta ao cliente no rastro do pagamento
/// (painel, PT-BR). `null` = não há nada a devolver.
///
/// M10 b2 (09/11/2026, ordem do Danilo de 08/11): "Parar a série" devolve à
/// Carteira Bora — o servidor credita na hora (`cancel_cleaning_series` →
/// `wallet_credit_refund_split`, transação `refund_credit_free` com o id da
/// limpeza, visível no painel em Wallets > transações do cliente). Não há estorno na
/// Stripe nesse caso.
String? rotuloDevolucaoLimpeza({
  required String? cancelReason,
  required String? paymentStatus,
  required int taxaCents,
}) {
  if (cancelReason == 'serie_terminada' && paymentStatus == 'estornado') {
    return 'Voltou à Carteira Bora';
  }
  if (paymentStatus == 'estornado' || taxaCents > 0) {
    return 'Deve voltar ao cliente';
  }
  return null;
}

/// O rastro do dinheiro de uma reserva de limpeza, em PT-BR, para o Danilo.
///
/// Serve para responder a UMA pergunta concreta: "este cliente diz que pagou
/// duas vezes — pagou?". Mostra a chave de idempotência (duas reservas com a
/// mesma chave = bug nosso), o id do pagamento na Stripe (é o que se cola lá
/// para ver a cobrança e se já há estorno), quanto se reteve no cancelamento e
/// quanto deveria voltar. Só leitura: accionar um estorno daqui é outra coisa
/// e está explicado no relatório de 05/09.
class _RastroPagamento extends StatelessWidget {
  const _RastroPagamento({
    required this.paymentIntentId,
    required this.idempotencyKey,
    required this.cancelFeeCents,
    required this.paymentStatus,
    required this.totalCents,
    this.cancelReason,
  });

  final String? paymentIntentId;
  final String? idempotencyKey;
  final dynamic cancelFeeCents;
  final String? paymentStatus;
  final dynamic totalCents;
  final String? cancelReason;

  static String _eur(dynamic cents) {
    final c = (cents is num) ? cents.toInt() : int.tryParse('$cents') ?? 0;
    return '€${(c / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    // Nada para mostrar numa reserva em dinheiro que nunca tocou na Stripe.
    if (paymentIntentId == null && idempotencyKey == null) {
      return const SizedBox.shrink();
    }
    final taxa = (cancelFeeCents is num) ? cancelFeeCents.toInt() : 0;
    final total = (totalCents is num) ? totalCents.toInt() : 0;
    final devolver = total - taxa;

    Widget linha(String rotulo, String valor, {bool mono = false}) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 132,
                child: Text(rotulo,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
              ),
              Expanded(
                child: SelectableText(
                  valor,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: mono ? 'monospace' : null,
                      color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.textSubtle.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rastro do pagamento',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          if (paymentIntentId != null)
            linha('Pagamento (Stripe)', paymentIntentId!, mono: true),
          if (idempotencyKey != null)
            linha('Chave da marcação', idempotencyKey!, mono: true),
          linha('Situação', paymentStatus ?? '—'),
          if (taxa > 0)
            linha('Retido no cancelamento', _eur(taxa)),
          if (rotuloDevolucaoLimpeza(
                  cancelReason: cancelReason,
                  paymentStatus: paymentStatus,
                  taxaCents: taxa) case final rotulo?)
            linha(rotulo, _eur(devolver < 0 ? 0 : devolver)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.active,
    required this.cancelled,
  });
  final String label;
  final bool active;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final color = cancelled
        ? AppColors.error
        : active
            ? AppColors.primary
            : AppColors.textSubtle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLisboa();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
