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

  /// Histórico da reserva (PT-BR): quem devolveu, com que motivo, e de quem para quem foi
  /// trocada. [24/09/2026] Antes, uma reserva que mudava de mãos não deixava rasto visível
  /// no painel — a única forma de saber era ir ao banco.
  Future<void> _historico(Map<String, dynamic> r) async {
    final rideId = r['id']?.toString() ?? r['ride_id']?.toString();
    if (rideId == null) return;
    List<Map<String, dynamic>> eventos = const [];
    Map<String, String> nomes = const {};
    try {
      final res = await Supabase.instance.client
          .from('tvde_ride_events')
          .select('created_at, status, actor, meta')
          .eq('ride_id', rideId)
          .order('created_at', ascending: false)
          .limit(60);
      eventos = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      // Nomes dos motoristas que aparecem nos eventos, para não mostrar só uuid.
      final ids = <String>{};
      for (final e in eventos) {
        final m = e['meta'];
        if (m is Map) {
          for (final k in const ['driver_id', 'de', 'para']) {
            final v = m[k]?.toString();
            if (v != null && v.isNotEmpty) ids.add(v);
          }
        }
      }
      if (ids.isNotEmpty) {
        final ds = await Supabase.instance.client
            .from('drivers')
            .select('user_id, name')
            .inFilter('user_id', ids.toList());
        nomes = {
          for (final d in (ds as List).whereType<Map>())
            d['user_id'].toString(): (d['name'] ?? '').toString(),
        };
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(humanizeAdminRpcError(e))));
      return;
    }
    if (!mounted) return;

    String quem(Object? id) {
      final s = id?.toString();
      if (s == null || s.isEmpty) return '—';
      final n = nomes[s];
      return (n != null && n.isNotEmpty) ? n : '${s.substring(0, 8)}…';
    }

    String descrever(Map<String, dynamic> e) {
      final meta = e['meta'] is Map
          ? Map<String, dynamic>.from(e['meta'] as Map)
          : <String, dynamic>{};
      switch (e['status']?.toString()) {
        case 'reserva_devolvida':
          return 'Devolvida por ${quem(meta['driver_id'])}'
              '${meta['motivo'] != null ? ' · motivo: ${meta['motivo']}' : ''}'
              '${meta['estava'] != null ? ' (estava ${meta['estava']})' : ''}';
        case 'reserva_motorista_trocado':
          return 'Motorista trocado: ${quem(meta['de'])} → ${quem(meta['para'])}';
        case 'volta_marcada':
          return 'Volta do pacote marcada para ${_quando(meta['return_at']?.toString())}';
        default:
          return '${e['status']} · ${e['actor'] ?? '—'}';
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controle) => ListView(
          controller: controle,
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Text('Histórico da reserva',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: Spacing.sm),
            if (eventos.isEmpty) const Text('Sem eventos registrados.'),
            for (final e in eventos)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_quando(e['created_at']?.toString()),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSubtle)),
                    Text(descrever(e), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Marca (ou muda) a hora da volta do pacote, pelo painel.
  ///
  /// [24/09/2026] A cliente quis ida às 16h36 e volta às 21h40 e a app não deixava; ficou
  /// com a ida marcada para a hora da volta e foi preciso arranjar à mão na base. Agora o
  /// Danilo faz isto daqui: escolhe o dia e a hora, e o servidor trata do resto (cancela a
  /// marcação anterior sem taxa, cria a nova perna e procura motorista).
  Future<void> _marcarVolta(Map<String, dynamic> r) async {
    final creditId = r['roundtrip_credit_id']?.toString();
    if (creditId == null) return;
    final ida = DateTime.tryParse(r['scheduled_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final sugestao = ida.add(const Duration(hours: 2));

    final dia = await showDatePicker(
      context: context,
      initialDate: sugestao,
      firstDate: ida,
      lastDate: ida.add(const Duration(hours: 12)),
      helpText: 'Dia da volta',
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(sugestao),
      helpText: 'Hora da volta',
    );
    if (hora == null || !mounted) return;

    final quando = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    await _acao(
      'admin_tvde_roundtrip_set_return',
      {'p_credit_id': creditId, 'p_return_at': quando.toUtc().toIso8601String()},
      'Volta marcada para ${_quando(quando.toUtc().toIso8601String())}.',
    );
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
    // [Oferta sobreposta 20/09 · Bloco 5] quanto falta para a oferta em voo
    // expirar (o servidor devolve `reservation_offer_expires_at`).
    final expira = DateTime.tryParse(
        r['reservation_offer_expires_at']?.toString() ?? '');
    final faltaSeg =
        expira == null ? null : expira.difference(DateTime.now()).inSeconds;
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
          // [24/09] Diz-se qual das duas pernas do pacote é esta, e a que vale pertence —
          // duas reservas soltas na lista não deixavam ver que eram a mesma viagem.
          if (r['roundtrip_credit_id'] != null) ...[
            Row(
              children: [
                Icon(r['is_return_leg'] == true
                        ? Icons.u_turn_left
                        : Icons.arrow_forward,
                    size: 14, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Text(
                  r['is_return_leg'] == true
                      ? 'Volta do pacote'
                      : 'Ida do pacote',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'vale ${r['roundtrip_credit_id'].toString().substring(0, 8)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
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
                  ? 'oferta a tocar a $ofertaPara'
                      '${faltaSeg == null ? '' : faltaSeg > 0 ? ' · expira em ${faltaSeg}s' : ' · expirada, a rodar'}'
                  : '— (nenhum ainda)')),
          _kv('Trajeto',
              '${r['origin_label'] ?? '?'} → ${r['dest_label'] ?? '?'}'),
          _kv('Pagamento',
              '${r['payment_method'] ?? 'cash'}'
              '${r['payment_status'] != null ? ' · ${r['payment_status']}' : ''}'),
          // [Ida-e-volta marcada · 23/09] pacote: que perna é, a outra perna,
          // "volta marcada" ou "cliente chama", estado do vale. Cada perna é
          // um cartão próprio com Trocar motorista / Cancelar.
          for (final l in pacoteLinhasPtBr(r, _quando)) _kv(l.$1, l.$2),
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
                // [24/09] Pacote ida-e-volta: marcar ou mudar a hora da volta a partir
                // daqui. Só aparece na perna da IDA, que é quem manda no vale.
                if (r['roundtrip_credit_id'] != null && r['is_return_leg'] != true)
                  TextButton.icon(
                    onPressed: () => _marcarVolta(r),
                    icon: const Icon(Icons.u_turn_left, size: 18),
                    label: Text(r['return_scheduled_at'] == null
                        ? 'Marcar volta'
                        : 'Alterar hora da volta'),
                  ),
                TextButton.icon(
                  onPressed: () => _historico(r),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Histórico'),
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

/// [Ida-e-volta marcada · 23/09] Linhas (rótulo, valor) do pacote ida-e-volta
/// de uma reserva, em PT-BR. Vazio quando a reserva não é de um pacote.
/// [quando] formata datas (o mesmo formatador do cartão).
List<(String, String)> pacoteLinhasPtBr(
    Map<String, dynamic> r, String Function(String?) quando) {
  final pacote = r['pacote'];
  if (pacote is! Map) return const [];
  final ehVolta = r['is_return_leg'] == true;
  final perna = r['perna_ligada'] is Map
      ? Map<String, dynamic>.from(r['perna_ligada'] as Map)
      : null;
  final pago = ((pacote['paid_cents'] as num?)?.toInt() ?? 0) / 100;
  final linhas = <(String, String)>[
    ('Pacote',
        'ida-e-volta · esta é a ${ehVolta ? 'VOLTA' : 'IDA'} · '
            '€${pago.toStringAsFixed(2)} ${pacote['pago_online'] == true ? 'pago online' : 'em dinheiro'}'),
  ];
  String estadoPerna(Map<String, dynamic> p) {
    final motorista = p['driver_name']?.toString();
    return '${p['status']}'
        '${p['reservation_status'] != null ? ' / ${p['reservation_status']}' : ''}'
        '${motorista != null ? ' · $motorista' : ''}';
  }

  if (ehVolta) {
    linhas.add(('Ida ligada', perna == null ? '—' : estadoPerna(perna)));
  } else {
    final modo = pacote['return_mode']?.toString();
    if (modo == 'marcada') {
      linhas.add((
        'Volta',
        'marcada para ${quando(pacote['return_scheduled_at']?.toString())}'
            '${perna != null ? ' · ${estadoPerna(perna)}' : ''}'
      ));
    } else if (modo == 'cliente_chama') {
      linhas.add(('Volta', 'cliente chama quando terminar (vale)'));
    } else {
      linhas.add((
        'Volta',
        perna == null ? 'vale do pacote' : 'pedida · ${estadoPerna(perna)}'
      ));
    }
  }
  const estados = {
    'reservado': 'reservado (ida ainda por fazer)',
    'ativo': 'ativo (cliente pode pedir a volta)',
    'usado': 'usado (volta pedida ou marcada)',
    'expirado': 'expirado',
    'anulado': 'anulado (ida cancelada — reembolso do pacote)',
  };
  final st = pacote['status']?.toString();
  linhas.add(('Vale da volta', estados[st] ?? (st ?? '—')));
  return linhas;
}
