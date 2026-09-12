import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — RESERVAS (corridas agendadas).
///
/// Autoridade total do Danilo: ver todas, criar à mão, cancelar, trocar o
/// motorista e forçar nova chamada. Idioma: PT-BR.
///
/// Lê `admin_tvde_reservations_list`. As ações usam as RPCs de admin
/// (`admin_tvde_reservation_*`), todas travadas por `is_admin()` no servidor.
/// O relógio continua a ser do cron `tvde-reservations-sweep` — este ecrã não
/// faz contas de tempo, só mostra e manda.
class AdminTvdeReservasScreen extends StatefulWidget {
  const AdminTvdeReservasScreen({super.key});

  @override
  State<AdminTvdeReservasScreen> createState() =>
      _AdminTvdeReservasScreenState();
}

class _AdminTvdeReservasScreenState extends State<AdminTvdeReservasScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _escopo = 'futuras';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'admin_tvde_reservations_list',
      params: {'p_scope': _escopo, 'p_limit': 200},
    );
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

  // ── Ações de admin ──────────────────────────────────────────────────────

  Future<void> _acao(
    String rpc,
    Map<String, dynamic> params,
    String sucesso,
  ) async {
    try {
      await Supabase.instance.client.rpc(rpc, params: params);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(sucesso)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeAdminRpcError(e))));
    }
  }

  Future<void> _cancelar(Map<String, dynamic> r) async {
    final ok = await _confirmar(
      'Cancelar esta reserva?',
      'O cliente é avisado. Se a reserva foi paga com cartão ou MB Way, o '
          'reembolso é feito automaticamente pelo servidor.',
    );
    if (ok != true) return;
    await _acao(
      'admin_tvde_reservation_cancel',
      {'p_ride_id': r['id'], 'p_reason': 'cancelada_pelo_admin'},
      'Reserva cancelada.',
    );
  }

  Future<void> _forcarBusca(Map<String, dynamic> r) async {
    final ok = await _confirmar(
      'Forçar nova chamada?',
      'Limpa o motorista atual e a lista de já tentados, e volta a chamar '
          'do início. Quem estava com a reserva é avisado que a perdeu.',
    );
    if (ok != true) return;
    await _acao(
      'admin_tvde_reservation_force_search',
      {'p_ride_id': r['id']},
      'Nova chamada disparada.',
    );
  }

  Future<void> _trocarMotorista(Map<String, dynamic> r) async {
    final motoristas = await _carregarMotoristas();
    if (!mounted || motoristas.isEmpty) return;

    final escolhido = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Text('Escolha o motorista',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final m in motoristas)
              ListTile(
                leading: Icon(
                  m['is_online'] == true
                      ? Icons.circle
                      : Icons.circle_outlined,
                  size: 12,
                  color: m['is_online'] == true
                      ? AppColors.primary
                      : AppColors.textSubtle,
                ),
                title: Text(m['name']?.toString() ?? '(sem nome)'),
                subtitle: Text(m['is_online'] == true
                    ? 'online agora'
                    : 'offline'),
                onTap: () =>
                    Navigator.pop(context, m['user_id']?.toString()),
              ),
          ],
        ),
      ),
    );
    if (escolhido == null) return;
    await _acao(
      'admin_tvde_reservation_set_driver',
      {'p_ride_id': r['id'], 'p_driver_id': escolhido},
      'Motorista trocado. Ele foi avisado.',
    );
  }

  Future<List<Map<String, dynamic>>> _carregarMotoristas() async {
    try {
      final res = await Supabase.instance.client
          .from('drivers')
          .select('user_id, name, is_online')
          .eq('approval_status', 'approved')
          .order('is_online', ascending: false);
      return (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(humanizeAdminRpcError(e))));
      }
      return const [];
    }
  }

  Future<bool?> _confirmar(String titulo, String texto) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Voltar')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmar')),
          ],
        ),
      );

  // ── Criar reserva à mão ─────────────────────────────────────────────────

  Future<void> _criar() async {
    final criada = await showDialog<bool>(
      context: context,
      builder: (_) => const _CriarReservaDialog(),
    );
    if (criada == true) await _refresh();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  static const _meses = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez'
  ];

  String _quando(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_meses[d.month - 1]} · $hh:$mm';
  }

  String _estadoPtBr(String? s) {
    switch (s) {
      case 'aguarda_pagamento':
        return 'aguardando pagamento';
      case 'a_procurar':
        return 'procurando motorista';
      case 'atribuida':
        return 'motorista confirmado';
      case 'ativada':
        return 'a caminho';
      case 'sem_motorista':
        return 'sem motorista';
      case 'cancelada':
        return 'cancelada';
      default:
        return s ?? '—';
    }
  }

  Color _corEstado(String? s) {
    switch (s) {
      case 'atribuida':
      case 'ativada':
        return AppColors.primary;
      case 'sem_motorista':
      case 'cancelada':
        return AppColors.error;
      case 'aguarda_pagamento':
        return AppColors.accent;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'TVDE — Reservas'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _criar,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nova reserva'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'futuras', label: Text('Futuras')),
                ButtonSegment(value: 'problemas', label: Text('Problemas')),
                ButtonSegment(value: 'todas', label: Text('Todas')),
              ],
              selected: {_escopo},
              onSelectionChanged: (s) {
                setState(() => _escopo = s.first);
                _refresh();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Text(humanizeAdminRpcError(snap.error!)),
                    ),
                  );
                }
                final linhas = snap.data ?? const [];
                if (linhas.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      children: const [
                        SizedBox(height: 140),
                        Center(child: Text('Nenhuma reserva neste filtro.')),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        Spacing.lg, 0, Spacing.lg, 90),
                    itemCount: linhas.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: Spacing.md),
                    itemBuilder: (_, i) => _cartao(linhas[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartao(Map<String, dynamic> r) {
    final estado = r['reservation_status']?.toString();
    final preco =
        ((r['est_fare_cents'] as num?)?.toInt() ?? 0) / 100;
    final motorista = r['driver_name']?.toString();
    final ofertaPara = r['offer_driver_name']?.toString();
    final viva = estado != 'cancelada';
    final tentados = (r['reservation_tried_driver_ids'] as List?)?.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event, size: 18, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  _quando(r['scheduled_at']?.toString()),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Text('€${preco.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          _kv('Cliente', r['client_name']?.toString() ?? '—'),
          _kv('Motorista',
              motorista ?? (ofertaPara != null
                  ? 'oferta enviada para $ofertaPara'
                  : '— (nenhum ainda)')),
          _kv('Trajeto',
              '${r['origin_label'] ?? '?'} → ${r['dest_label'] ?? '?'}'),
          _kv('Pagamento',
              '${r['payment_method'] ?? 'cash'}'
              '${r['payment_status'] != null ? ' · ${r['payment_status']}' : ''}'),
          if (tentados > 0) _kv('Já tentados', '$tentados motorista(s)'),
          // [Bloco 4.6 — 2026-09-05] Travão por rota. Desde o caso do Valdemir
          // (03→04/09) o travão deixou de ser fixo em 20 min e passa a ser o
          // tempo de condução do motorista até o cliente, com margem. Aqui
          // mostramos os três números que explicam qualquer reserva presa:
          // quantos minutos, a que horas entra, e se a conta vem de uma posição
          // fresca ou se caiu no valor fixo por falta de sinal.
          if (r['lock_minutes'] != null) ...[
            _kv('Trava (rota)', '${r['lock_minutes']} min antes'),
            if (r['lock_at'] != null)
              _kv('Trava entra às', _quando(r['lock_at']?.toString())),
            _kv(
              'Base do cálculo',
              r['driver_position_age_min'] == null
                  ? 'sem posição do motorista — usou o valor fixo'
                  : (r['driver_position_age_min'] as num) <= 30
                      ? 'posição de há ${r['driver_position_age_min']} min — rota real'
                      : 'posição de há ${r['driver_position_age_min']} min '
                          '(velha demais) — usou o valor fixo',
            ),
          ],
          if (r['reservation_driver_ready_at'] != null)
            _kv('Confirmou "A caminho"',
                _quando(r['reservation_driver_ready_at']?.toString())),
          if (r['cancel_reason'] != null)
            _kv('Motivo', r['cancel_reason'].toString()),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: 5),
            decoration: BoxDecoration(
              color: _corEstado(estado).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _estadoPtBr(estado),
              style: TextStyle(
                  color: _corEstado(estado),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (viva) ...[
            const Divider(height: Spacing.xl),
            Wrap(
              spacing: Spacing.sm,
              children: [
                TextButton.icon(
                  onPressed: () => _trocarMotorista(r),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Trocar motorista'),
                ),
                TextButton.icon(
                  onPressed: () => _forcarBusca(r),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Forçar chamada'),
                ),
                TextButton.icon(
                  onPressed: () => _cancelar(r),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.error),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: Text('$k:',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSubtle)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );
}

/// Criar reserva à mão. Só DINHEIRO — cobrar cartão/MB Way exigiria um
/// PaymentIntent autorizado pelo próprio cliente, que o admin não pode fazer.
class _CriarReservaDialog extends StatefulWidget {
  const _CriarReservaDialog();

  @override
  State<_CriarReservaDialog> createState() => _CriarReservaDialogState();
}

class _CriarReservaDialogState extends State<_CriarReservaDialog> {
  final _clienteId = TextEditingController();
  final _origem = TextEditingController();
  final _origemLat = TextEditingController(text: '40.5373');
  final _origemLng = TextEditingController(text: '-7.2676');
  final _destino = TextEditingController();
  final _destLat = TextEditingController(text: '40.5373');
  final _destLng = TextEditingController(text: '-7.2676');
  final _km = TextEditingController(text: '5');
  DateTime? _quando;
  bool _gravando = false;

  @override
  void dispose() {
    for (final c in [
      _clienteId,
      _origem,
      _origemLat,
      _origemLng,
      _destino,
      _destLat,
      _destLng,
      _km
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherQuando() async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: agora.add(const Duration(hours: 1)),
      firstDate: agora,
      lastDate: agora.add(const Duration(days: 60)),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(
        context: context, initialTime: TimeOfDay.now());
    if (hora == null || !mounted) return;
    setState(() => _quando = DateTime(
        data.year, data.month, data.day, hora.hour, hora.minute));
  }

  Future<void> _gravar() async {
    if (_quando == null || _clienteId.text.trim().isEmpty) return;
    setState(() => _gravando = true);
    try {
      await Supabase.instance.client
          .rpc('admin_tvde_reservation_create', params: {
        'p_client_id': _clienteId.text.trim(),
        'p_origin_lat': double.tryParse(_origemLat.text) ?? 0,
        'p_origin_lng': double.tryParse(_origemLng.text) ?? 0,
        'p_origin_label': _origem.text.trim(),
        'p_dest_lat': double.tryParse(_destLat.text) ?? 0,
        'p_dest_lng': double.tryParse(_destLng.text) ?? 0,
        'p_dest_label': _destino.text.trim(),
        'p_est_distance_km': double.tryParse(_km.text) ?? 1,
        'p_scheduled_at': _quando!.toUtc().toIso8601String(),
        'p_note': null,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gravando = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeAdminRpcError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova reserva (dinheiro)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _campo(_clienteId, 'ID do cliente (UUID)'),
            _campo(_origem, 'Endereço de recolha'),
            Row(children: [
              Expanded(child: _campo(_origemLat, 'Lat recolha')),
              const SizedBox(width: Spacing.sm),
              Expanded(child: _campo(_origemLng, 'Lng recolha')),
            ]),
            _campo(_destino, 'Endereço de destino'),
            Row(children: [
              Expanded(child: _campo(_destLat, 'Lat destino')),
              const SizedBox(width: Spacing.sm),
              Expanded(child: _campo(_destLng, 'Lng destino')),
            ]),
            _campo(_km, 'Distância (km)'),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              onPressed: _escolherQuando,
              icon: const Icon(Icons.event),
              label: Text(_quando == null
                  ? 'Escolher data e hora'
                  : _quando.toString().substring(0, 16)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        TextButton(
          onPressed: _gravando ? null : _gravar,
          child: Text(_gravando ? 'Gravando…' : 'Criar'),
        ),
      ],
    );
  }

  Widget _campo(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
              labelText: label, isDense: true, border: const OutlineInputBorder()),
        ),
      );
}
