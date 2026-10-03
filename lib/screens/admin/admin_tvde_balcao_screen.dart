import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bora Motorista — Corridas de Balcão (missão `central-corridas-balcao-2026-09-18`).
///
/// Cliente do Danilo liga sem ter a app: ele cria a corrida por aqui, em
/// dinheiro, com valor combinado (`agreed_fare_cents`/`agreed_driver_earn_cents`),
/// e ela entra no despacho normal como qualquer corrida TVDE.
///
/// [Nota de terreno] `admin_tvde_rides_list` (RPC read-only já existente) NÃO
/// devolve `source`/`agreed_*` — é junção com `auth.users`, que um cliente de
/// balcão nunca tem (não faz login). Por isso este ecrã faz DUAS leituras
/// extra, diretas e read-only, autorizadas pela RLS de admin
/// (`tvde_rides_select`/`users_select_admin`: `is_admin()`): uma para saber
/// que corridas são de balcão + o valor combinado, outra para o nome/telefone
/// do cliente quando a RPC vem vazia. Nada disto é escrita — só leitura para
/// completar o que a RPC ainda não sabe. Ver relatório da missão para a
/// proposta de estender `admin_tvde_rides_list` (fora do meu âmbito: SQL).
class AdminTvdeBalcaoScreen extends StatefulWidget {
  const AdminTvdeBalcaoScreen({super.key});

  @override
  State<AdminTvdeBalcaoScreen> createState() => _AdminTvdeBalcaoScreenState();
}

class _AdminTvdeBalcaoScreenState extends State<AdminTvdeBalcaoScreen> {
  final _refreshKeyLive = GlobalKey<_RidesListState>();
  final _refreshKeyHistory = GlobalKey<_RidesListState>();

  Future<void> _novaCorrida() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateCounterRideDialog(),
    );
    if (created == true && mounted) {
      _refreshKeyLive.currentState?.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: const BoraScreenAppBar(title: 'Corridas de Balcão'),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _novaCorrida,
          icon: const Icon(Icons.add),
          label: const Text('Nova corrida'),
        ),
        body: Column(
          children: [
            const Material(
              color: Colors.white,
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  Tab(text: 'Ao Vivo'),
                  Tab(text: 'Histórico'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _RidesList(key: _refreshKeyLive, scope: 'live'),
                  _RidesList(key: _refreshKeyHistory, scope: 'history'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RidesList extends StatefulWidget {
  const _RidesList({super.key, required this.scope});
  final String scope; // live | history

  @override
  State<_RidesList> createState() => _RidesListState();
}

class _RidesListState extends State<_RidesList>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  Timer? _timer;

  bool get _isLive => widget.scope == 'live';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
    if (_isLive) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_tvde_rides_list',
        params: {'p_scope': widget.scope, 'p_limit': _isLive ? 200 : 500},
      );
      final list = ((res as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rows = const [];
          _loading = false;
          _error = null;
        });
        return;
      }

      final ids = list.map((r) => r['id'].toString()).toList();
      // Leitura extra 1: source + valor combinado (a RPC não os devolve).
      final extra = await Supabase.instance.client
          .from('tvde_rides')
          .select('id, source, agreed_fare_cents, agreed_driver_earn_cents')
          .inFilter('id', ids);
      final extraById = {
        for (final e in (extra as List))
          (e as Map)['id'].toString(): Map<String, dynamic>.from(e)
      };

      final balcao = list.where((r) {
        final ex = extraById[r['id'].toString()];
        return ex != null && ex['source'] == 'balcao';
      }).map((r) {
        final ex = extraById[r['id'].toString()]!;
        return {
          ...r,
          'agreed_fare_cents': ex['agreed_fare_cents'],
          'agreed_driver_earn_cents': ex['agreed_driver_earn_cents'],
        };
      }).toList();

      // Leitura extra 2: nome/telefone quando a RPC veio vazia (cliente de
      // balcão não tem conta em auth.users — a RPC só sabe ler de lá).
      final semNome = balcao
          .where((r) => (r['client_name'] as String?)?.trim().isEmpty ?? true)
          .map((r) => r['client_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();
      if (semNome.isNotEmpty) {
        final users = await Supabase.instance.client
            .from('users')
            .select('id, name, phone')
            .inFilter('id', semNome);
        final byId = {
          for (final u in (users as List))
            (u as Map)['id'].toString(): Map<String, dynamic>.from(u)
        };
        for (final r in balcao) {
          final u = byId[r['client_id']?.toString()];
          if (u == null) continue;
          if ((r['client_name'] as String?)?.trim().isEmpty ?? true) {
            r['client_name'] = u['name'];
          }
          if ((r['client_phone'] as String?)?.trim().isEmpty ?? true) {
            r['client_phone'] = u['phone'];
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = balcao;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reassign(Map<String, dynamic> ride) async {
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ReassignDialog(ride: ride),
    );
    if (!mounted || res == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res['queued'] == true
          ? 'Corrida colocada na fila do motorista.'
          : 'Corrida atribuída ao motorista.'),
    ));
    await load();
  }

  Future<void> _cancel(Map<String, dynamic> ride) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelDialog(),
    );
    if (motivo == null) return; // cancelou o diálogo
    try {
      await Supabase.instance.client.rpc('tvde_cancel_ride', params: {
        'p_ride_id': ride['id'],
        'p_actor': 'cliente',
        'p_reason': motivo.trim().isEmpty
            ? 'Corrida de balcão cancelada pelo admin'
            : 'Corrida de balcão cancelada pelo admin: ${motivo.trim()}',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrida cancelada.')));
      await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não deu para cancelar: $e')));
    }
  }

  static const _reassignable = {
    'solicitada',
    'sem_motorista',
    'motorista_atribuido',
    'motorista_a_caminho',
    'motorista_chegou',
  };
  static const _cancelable = {
    'solicitada',
    'sem_motorista',
    'motorista_atribuido',
    'motorista_a_caminho',
    'motorista_chegou',
    'em_andamento',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.error_outline, size: 44, color: AppColors.error),
          const SizedBox(height: 12),
          Text('Erro:\n$_error', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          Card(
            elevation: 0,
            color: AppColors.info.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.phone_in_talk, color: AppColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_rows.length} corrida(s) de balcão'
                      '${_isLive ? ' · atualiza a cada 15s' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Text('Nenhuma corrida de balcão aqui.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ..._rows.map((r) {
              final status = r['status'] as String?;
              return _BalcaoRideCard(
                data: r,
                live: _isLive,
                onReassign: (_isLive && _reassignable.contains(status))
                    ? () => _reassign(r)
                    : null,
                onCancel: (_isLive && _cancelable.contains(status))
                    ? () => _cancel(r)
                    : null,
              );
            }),
        ],
      ),
    );
  }
}

class _BalcaoRideCard extends StatelessWidget {
  const _BalcaoRideCard({
    required this.data,
    required this.live,
    this.onReassign,
    this.onCancel,
  });

  final Map<String, dynamic> data;
  final bool live;
  final VoidCallback? onReassign;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String?;
    final client = (data['client_name'] as String?)?.trim();
    final clientPhone = (data['client_phone'] as String?)?.trim();
    final driver = (data['driver_name'] as String?)?.trim();
    final agreedFare = (data['agreed_fare_cents'] as num?)?.toInt();
    final agreedDriver = (data['agreed_driver_earn_cents'] as num?)?.toInt();
    final fareCents = agreedFare ??
        ((data['final_fare_cents'] ?? data['est_fare_cents']) as num?)
            ?.toInt();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusChip(status: status),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Balcão',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.info)),
                ),
                const Spacer(),
                Text(fareCents == null ? '—' : _eur(fareCents),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                '${data['origin_label'] ?? '?'} → ${data['dest_label'] ?? '?'}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 14, color: AppColors.textSubtle),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Cliente: ${(client == null || client.isEmpty) ? '—' : client}'
                    '${(clientPhone != null && clientPhone.isNotEmpty) ? ' · $clientPhone' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(Icons.local_taxi,
                      size: 14, color: AppColors.textSubtle),
                  const SizedBox(width: 6),
                  Text(
                    'Motorista: ${(driver == null || driver.isEmpty) ? (live ? 'à procura…' : '—') : driver}'
                    '${agreedDriver != null ? ' · ganha ${_eur(agreedDriver)}' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (onReassign != null || onCancel != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (onReassign != null)
                      OutlinedButton.icon(
                        onPressed: onReassign,
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: const Text('Reatribuir'),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                      ),
                    if (onCancel != null)
                      OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: AppColors.error),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'solicitada' => ('Solicitada', AppColors.warning),
      'motorista_atribuido' => ('Motorista atribuído', Colors.blue),
      'motorista_a_caminho' => ('A caminho', Colors.blue),
      'motorista_chegou' => ('Chegou', Colors.indigo),
      'em_andamento' => ('Em andamento', AppColors.primary),
      'finalizada' => ('Finalizada', AppColors.primary),
      'cancelada_cliente' => ('Cancelada', AppColors.error),
      'cancelada_motorista' => ('Cancelada (motorista)', AppColors.error),
      'no_show' => ('No-show', AppColors.error),
      'sem_motorista' => ('Sem motorista', AppColors.error),
      _ => (status ?? '—', AppColors.textSecondary),
    };
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

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();
  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _motivo = TextEditingController();
  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar corrida de balcão'),
      content: TextField(
        controller: _motivo,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Motivo (fica no histórico)',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        FilledButton(
          style:
              FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.of(context).pop(_motivo.text),
          child: const Text('Cancelar corrida'),
        ),
      ],
    );
  }
}

/// Reatribuir corrida de balcão — mesma RPC `admin_tvde_reassign_ride` usada
/// no ecrã geral de Corridas (livre → direto; ocupado → entra na fila dele).
class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({required this.ride});
  final Map<String, dynamic> ride;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  List<Map<String, dynamic>> _drivers = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _selectedUserId;
  final _motivo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    try {
      final res =
          await Supabase.instance.client.rpc('admin_tvde_drivers_list');
      final list = ((res as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((d) =>
              d['approval_status'] == 'approved' &&
              d['is_banned'] != true &&
              d['user_id'] != null &&
              d['user_id'] != widget.ride['driver_id'])
          .toList()
        ..sort((a, b) {
          int peso(Map<String, dynamic> d) {
            final online = d['is_online'] == true;
            final ativas = (d['active_rides'] as num?)?.toInt() ?? 0;
            if (!online) return 2;
            return ativas == 0 ? 0 : 1;
          }
          final c = peso(a).compareTo(peso(b));
          return c != 0
              ? c
              : (a['name'] as String? ?? '')
                  .compareTo(b['name'] as String? ?? '');
        });
      if (!mounted) return;
      setState(() {
        _drivers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final uid = _selectedUserId;
    if (uid == null || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await Supabase.instance.client
          .rpc('admin_tvde_reassign_ride', params: {
        'p_ride_id': widget.ride['id'],
        'p_driver_id': uid,
        'p_motivo': _motivo.text.trim().isEmpty
            ? 'corrida de balcão reatribuída pelo admin'
            : _motivo.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context)
          .pop(res is Map ? Map<String, dynamic>.from(res) : {'ok': true});
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() {
        _sending = false;
        _error = msg.contains('queue_full')
            ? 'A fila desse motorista já está cheia.'
            : msg.contains('ride_not_reassignable')
                ? 'Esta corrida já não pode ser reatribuída.'
                : 'Não deu: $msg';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reatribuir corrida de balcão'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator()))
            else if (_drivers.isEmpty)
              const Text('Nenhum motorista de passageiros aprovado.')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in _drivers)
                      RadioListTile<String>(
                        dense: true,
                        value: d['user_id'].toString(),
                        groupValue: _selectedUserId,
                        onChanged: _sending
                            ? null
                            : (v) => setState(() => _selectedUserId = v),
                        title: Text(
                            '${d['name'] ?? '—'}${d['is_online'] == true ? '' : ' (offline)'}',
                            style: const TextStyle(fontSize: 13.5)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _motivo,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _sending ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: (_selectedUserId == null || _sending) ? null : _confirm,
          child: Text(_sending ? 'A reatribuir…' : 'Reatribuir'),
        ),
      ],
    );
  }
}

/// Criar corrida de balcão — chama SEMPRE `admin_tvde_create_counter_ride`
/// (nunca INSERT direto): a RPC procura o cliente pelo telefone (nunca
/// duplica), resolve moradas guardadas por apelido, e usa os valores das
/// definições da plataforma por defeito.
class _CreateCounterRideDialog extends StatefulWidget {
  const _CreateCounterRideDialog();
  @override
  State<_CreateCounterRideDialog> createState() =>
      _CreateCounterRideDialogState();
}

class _CreateCounterRideDialogState extends State<_CreateCounterRideDialog> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _origin = TextEditingController();
  final _dest = TextEditingController();
  final _fare = TextEditingController();
  final _driverEarn = TextEditingController();
  final _note = TextEditingController();

  ll.LatLng? _originCoords;
  ll.LatLng? _destCoords;

  Map<String, dynamic>? _matchedClient;
  bool _searchingClient = false;
  Timer? _debounce;

  List<Map<String, dynamic>> _savedPlaces = const [];
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDefaults();
    _phone.addListener(_onPhoneChanged);
  }

  Future<void> _loadDefaults() async {
    try {
      final fare = await Supabase.instance.client
          .rpc('get_setting', params: {'p_key': 'tvde_balcao_default_fare_cents'});
      final driver = await Supabase.instance.client.rpc('get_setting',
          params: {'p_key': 'tvde_balcao_default_driver_cents'});
      if (!mounted) return;
      setState(() {
        _fare.text = (_asInt(fare) ?? 500).toString();
        _driverEarn.text = (_asInt(driver) ?? 400).toString();
      });
    } catch (_) {
      _fare.text = '500';
      _driverEarn.text = '400';
    }
  }

  int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  void _onPhoneChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _searchClient);
  }

  Future<void> _searchClient() async {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) {
      if (mounted) {
        setState(() {
          _matchedClient = null;
          _savedPlaces = const [];
        });
      }
      return;
    }
    setState(() => _searchingClient = true);
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('id, name, phone')
          .ilike('phone', '%$digits%')
          .limit(5);
      final list = (res as List).cast<Map>().toList();
      final exact = list.firstWhere(
        (u) => (u['phone'] as String?)
                ?.replaceAll(RegExp(r'[^0-9]'), '') ==
            digits,
        orElse: () => list.isNotEmpty ? list.first : {},
      );
      final matched =
          exact.isNotEmpty ? Map<String, dynamic>.from(exact) : null;
      if (!mounted) return;
      setState(() {
        _matchedClient = matched;
        _searchingClient = false;
      });
      if (matched != null) {
        final places = await Supabase.instance.client
            .from('tvde_client_places')
            .select('id, label, address, lat, lng')
            .eq('client_id', matched['id']);
        if (!mounted) return;
        setState(() =>
            _savedPlaces = (places as List).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      } else {
        setState(() => _savedPlaces = const []);
      }
    } catch (_) {
      if (mounted) setState(() => _searchingClient = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _phone.dispose();
    _name.dispose();
    _origin.dispose();
    _dest.dispose();
    _fare.dispose();
    _driverEarn.dispose();
    _note.dispose();
    super.dispose();
  }

  void _useSavedPlace(Map<String, dynamic> place, {required bool isOrigin}) {
    final coords = ll.LatLng(
        (place['lat'] as num).toDouble(), (place['lng'] as num).toDouble());
    setState(() {
      if (isOrigin) {
        _origin.text = '${place['label']} — ${place['address']}';
        _originCoords = coords;
      } else {
        _dest.text = '${place['label']} — ${place['address']}';
        _destCoords = coords;
      }
    });
  }

  Future<void> _submit() async {
    if (_sending) return;
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      setState(() => _error = 'Telefone é obrigatório.');
      return;
    }
    if (_originCoords == null || _destCoords == null) {
      setState(() =>
          _error = 'Escolhe origem e destino (sugestão do mapa ou morada guardada).');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await Supabase.instance.client
          .rpc('admin_tvde_create_counter_ride', params: {
        if (_matchedClient != null) 'p_client_id': _matchedClient!['id'],
        'p_client_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'p_client_phone': _phone.text.trim(),
        'p_origin_label': _origin.text.trim(),
        'p_origin_lat': _originCoords!.latitude,
        'p_origin_lng': _originCoords!.longitude,
        'p_dest_label': _dest.text.trim(),
        'p_dest_lat': _destCoords!.latitude,
        'p_dest_lng': _destCoords!.longitude,
        'p_fare_cents': int.tryParse(_fare.text.trim()),
        'p_driver_earn_cents': int.tryParse(_driverEarn.text.trim()),
        'p_note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      final msg = '$e';
      setState(() {
        _sending = false;
        _error = msg.contains('ride_in_progress')
            ? 'Este cliente já tem uma corrida em curso.'
            : msg.contains('morada_por_resolver')
                ? 'Escolhe origem/destino de uma sugestão do mapa ou de uma morada guardada.'
                : msg.contains('cliente_sem_telefone')
                    ? 'Falta o telefone do cliente.'
                    : 'Não deu: $msg';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final originPlaces =
        _savedPlaces; // apelidos guardados — origem e destino usam a mesma lista
    return AlertDialog(
      title: const Text('Nova corrida de balcão'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefone do cliente',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchingClient
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)))
                      : (_matchedClient != null
                          ? const Icon(Icons.check_circle,
                              color: AppColors.primary)
                          : null),
                ),
              ),
              const SizedBox(height: 4),
              if (_matchedClient != null)
                Text(
                    'Cliente existente: ${_matchedClient!['name'] ?? 'sem nome'}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600))
              else
                const Text(
                    'Nenhum cliente com este telefone — vai criar um novo.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.sm),
              if (_matchedClient == null)
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nome do cliente',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: Spacing.sm),
              if (originPlaces.isNotEmpty) ...[
                const Text('Moradas guardadas deste cliente',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final p in originPlaces) ...[
                      ActionChip(
                        label: Text('${p['label']} → origem'),
                        onPressed: () => _useSavedPlace(p, isOrigin: true),
                      ),
                      ActionChip(
                        label: Text('${p['label']} → destino'),
                        onPressed: () => _useSavedPlace(p, isOrigin: false),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Spacing.sm),
              ],
              AddressAutocompleteField(
                controller: _origin,
                labelText: 'Origem',
                onSelected: (addr, coords) =>
                    setState(() => _originCoords = coords),
              ),
              const SizedBox(height: Spacing.sm),
              AddressAutocompleteField(
                controller: _dest,
                labelText: 'Destino',
                onSelected: (addr, coords) =>
                    setState(() => _destCoords = coords),
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fare,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cobrar ao cliente (cêntimos)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _driverEarn,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Ganho motorista (cêntimos)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: Text(_sending ? 'A criar…' : 'Criar corrida'),
        ),
      ],
    );
  }
}

String _eur(int cents) => '€${(cents / 100).toStringAsFixed(2)}';
