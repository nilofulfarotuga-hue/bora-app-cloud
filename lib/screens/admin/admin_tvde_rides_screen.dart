import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bora Motorista (TVDE) — Corridas: ao vivo + histórico + financeiro.
///
/// • Ao Vivo: corridas em curso (atualiza sozinho a cada 15s). Posição do
///   motorista vem de `driver_locations` (mesmo live-ops do delivery).
/// • Histórico: corridas terminadas/canceladas com financeiro por corrida
///   (tarifa total · parte do motorista · parte do Bora · cancelamento) e
///   exportação CSV (reaproveita AdminExportService).
///
/// Lê `admin_tvde_rides_list(scope, limite)` (RPC admin read-only, aditivo).
/// Idioma: PT-BR.
class AdminTvdeRidesScreen extends StatefulWidget {
  const AdminTvdeRidesScreen({super.key});

  @override
  State<AdminTvdeRidesScreen> createState() => _AdminTvdeRidesScreenState();
}

class _AdminTvdeRidesScreenState extends State<AdminTvdeRidesScreen> {
  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: 'Corridas — Bora Motorista'),
        body: Column(
          children: [
            Material(
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
                  _RidesList(scope: 'live'),
                  _RidesList(scope: 'history'),
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
  const _RidesList({required this.scope});
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
    _load();
    if (_isLive) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.rpc(
        'admin_tvde_rides_list',
        params: {'p_scope': widget.scope, 'p_limit': _isLive ? 200 : 500},
      );
      final list = (res as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _rows = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
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

  // ── Financeiro agregado (apenas histórico) ──
  ({int fare, int driver, int bora, int cancelled, int finished}) _totals() {
    var fare = 0, driver = 0, bora = 0, cancelled = 0, finished = 0;
    for (final r in _rows) {
      final status = r['status'] as String?;
      if (status == 'finalizada') {
        finished++;
        fare += (r['final_fare_cents'] as num?)?.toInt() ?? 0;
        driver += (r['driver_earn_cents'] as num?)?.toInt() ?? 0;
        bora += (r['bora_cut_cents'] as num?)?.toInt() ?? 0;
      } else if ((status != null && status.startsWith('cancel')) ||
          status == 'no_show' ||
          status == 'sem_motorista') {
        cancelled++;
      }
      // taxa de cancelamento conta para o Bora
      bora += (r['cancel_fee_cents'] as num?)?.toInt() ?? 0;
    }
    return (
      fare: fare,
      driver: driver,
      bora: bora,
      cancelled: cancelled,
      finished: finished
    );
  }

  Future<void> _exportCsv() async {
    if (_rows.isEmpty) {
      _toast('Nada para exportar.', AppColors.warning);
      return;
    }
    final headers = [
      'ID',
      'Estado',
      'Criada',
      'Origem',
      'Destino',
      'Distância (km)',
      'Tarifa (€)',
      'Motorista (€)',
      'Bora (€)',
      'Taxa cancelamento (€)',
      'Motivo cancelamento',
      'Cliente',
      'Motorista',
    ];
    final rows = _rows.map((r) {
      return <dynamic>[
        r['id'],
        _statusLabel(r['status'] as String?),
        _fmtDateTime(r['created_at']),
        r['origin_label'] ?? '',
        r['dest_label'] ?? '',
        r['final_distance_km'] ?? r['est_distance_km'] ?? '',
        _eurRaw(r['final_fare_cents'] ?? r['est_fare_cents']),
        _eurRaw(r['driver_earn_cents']),
        _eurRaw(r['bora_cut_cents']),
        _eurRaw(r['cancel_fee_cents']),
        r['cancel_reason'] ?? '',
        r['client_name'] ?? '',
        r['driver_name'] ?? '',
      ];
    }).toList();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    await AdminExportService.instance.exportCsv(
      filename: 'bora_motorista_corridas_$stamp.csv',
      headers: headers,
      rows: rows,
      subject: 'Bora Motorista — Histórico de corridas ($stamp)',
    );
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

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
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_isLive)
            _LiveHeader(count: _rows.length, onRefresh: _load)
          else
            _FinanceHeader(totals: _totals(), onExport: _exportCsv),
          const SizedBox(height: 8),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: Text('Nenhuma corrida aqui.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ..._rows.map((r) => _RideCard(data: r, live: _isLive)),
        ],
      ),
    );
  }
}

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({required this.count, required this.onRefresh});
  final int count;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.08),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count corrida(s) em curso · atualiza a cada 15s',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: onRefresh,
              tooltip: 'Atualizar agora',
            ),
          ],
        ),
      ),
    );
  }
}

class _FinanceHeader extends StatelessWidget {
  const _FinanceHeader({required this.totals, required this.onExport});
  final ({int fare, int driver, int bora, int cancelled, int finished}) totals;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Financeiro (corridas listadas)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                OutlinedButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('CSV'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _stat('Concluídas', '${totals.finished}', AppColors.primary),
                _stat('Tarifa total', _eur(totals.fare), AppColors.textPrimary),
                _stat('Parte motorista', _eur(totals.driver), Colors.blue),
                _stat('Parte Bora', _eur(totals.bora), AppColors.primary),
                _stat('Canceladas', '${totals.cancelled}', AppColors.error),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  const _RideCard({required this.data, required this.live});
  final Map<String, dynamic> data;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String?;
    final client = (data['client_name'] as String?)?.trim();
    final clientPhone = (data['client_phone'] as String?)?.trim();
    final driver = (data['driver_name'] as String?)?.trim();
    final fareCents =
        (data['final_fare_cents'] ?? data['est_fare_cents']) as num?;
    final driverCents = (data['driver_earn_cents'] as num?)?.toInt();
    final boraCents = (data['bora_cut_cents'] as num?)?.toInt();
    final cancelReason = (data['cancel_reason'] as String?)?.trim();
    final cancelFee = (data['cancel_fee_cents'] as num?)?.toInt() ?? 0;
    final usedSubscriptionRide = data['used_subscription_ride'] == true;
    final locUpdated = data['driver_loc_updated_at'];
    // Back-to-back: corrida aceita em fila enquanto o motorista termina outra.
    final isQueued = data['is_queued'] == true;
    // Paradas adicionais (CAMPO-02). Lê direto do mapa da RPC; se a RPC ainda
    // não trouxer estas colunas, ficam 0 e o bloco não aparece (sem crash).
    final extraStopsCount = (data['extra_stops_count'] as num?)?.toInt() ?? 0;
    final extraStopsFee = (data['extra_stops_fee_cents'] as num?)?.toInt() ?? 0;
    final extraStopsDriver =
        (data['extra_stops_driver_cents'] as num?)?.toInt() ?? 0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RideStatusChip(status: status),
                if (isQueued && live) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Em fila (back-to-back)',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent)),
                  ),
                ],
                const Spacer(),
                if (usedSubscriptionRide) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Coberta pelo plano',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  fareCents == null
                      ? '—'
                      : _eur(fareCents.toInt()),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _route(data['origin_label'] as String?,
                data['dest_label'] as String?),
            const SizedBox(height: 8),
            _kv(Icons.person_outline, 'Cliente',
                (client != null && client.isNotEmpty) ? client : '—',
                extra: clientPhone),
            _kv(Icons.local_taxi, 'Motorista',
                (driver != null && driver.isNotEmpty)
                    ? driver
                    : (live ? 'À procura de motorista…' : '—')),
            if (live && locUpdated != null)
              _kv(Icons.my_location, 'Posição',
                  'atualizada ${_fmtDateTime(locUpdated)} (via driver_locations)'),
            if (extraStopsCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _StopsSummary(
                  count: extraStopsCount,
                  feeCents: extraStopsFee,
                  driverCents: extraStopsDriver,
                  rideId: data['id']?.toString(),
                ),
              ),
            if (!live && status == 'finalizada') ...[
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _money('Motorista', driverCents, Colors.blue),
                  ),
                  Expanded(
                    child: _money('Bora', boraCents, AppColors.primary),
                  ),
                ],
              ),
            ],
            if (cancelReason != null && cancelReason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Cancelamento: ${_cancelReasonLabel(cancelReason)}'
                  '${cancelFee > 0 ? ' · taxa ${_eur(cancelFee)}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_fmtDateTime(data['created_at']),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSubtle)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _route(String? origin, String? dest) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.trip_origin, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
              child: Text(origin ?? '—',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
        ]),
        Row(children: [
          const Icon(Icons.place, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Expanded(
              child: Text(dest ?? '—',
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis)),
        ]),
      ],
    );
  }

  Widget _kv(IconData icon, String key, String value, {String? extra}) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSubtle),
          const SizedBox(width: 6),
          Text('$key: ',
              style:
                  const TextStyle(fontSize: 12.5, color: AppColors.textSubtle)),
          Expanded(
            child: Text(
              extra != null && extra.isNotEmpty ? '$value · $extra' : value,
              style: const TextStyle(fontSize: 12.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _money(String label, int? cents, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        Text(_eur(cents ?? 0),
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: color)),
      ],
    );
  }
}

/// Resumo das paradas adicionais de uma corrida + botão que abre o detalhe
/// (RPC `admin_tvde_ride_stops`). total = taxa do cliente por todas as paradas,
/// motorista = ganho do motorista, Bora = total − motorista.
class _StopsSummary extends StatelessWidget {
  const _StopsSummary({
    required this.count,
    required this.feeCents,
    required this.driverCents,
    required this.rideId,
  });
  final int count;
  final int feeCents;
  final int driverCents;
  final String? rideId;

  @override
  Widget build(BuildContext context) {
    final boraCents = feeCents - driverCents;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_location_alt_outlined,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paradas: $count · ${_eur(feeCents)}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(
                  'motorista ${_eur(driverCents)} · Bora ${_eur(boraCents)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (rideId != null)
            TextButton.icon(
              onPressed: () => _showStops(context, rideId!),
              icon: const Icon(Icons.list_alt, size: 16),
              label: const Text('Ver paradas'),
            ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchStops(String rideId) async {
    final res = await Supabase.instance.client.rpc(
      'admin_tvde_ride_stops',
      params: {'p_ride_id': rideId},
    );
    final list = (res as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _showStops(BuildContext context, String rideId) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520, maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_location_alt_outlined,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Paradas da corrida',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Fechar',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _fetchStops(rideId),
                    builder: (ctx, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Erro ao carregar paradas:\n${snap.error}',
                              style: const TextStyle(color: AppColors.error)),
                        );
                      }
                      final stops = snap.data ?? const [];
                      if (stops.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Sem paradas registadas.',
                              style: TextStyle(color: AppColors.textSecondary)),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: stops.length,
                        separatorBuilder: (_, __) => const Divider(height: 14),
                        itemBuilder: (_, i) => _stopTile(stops[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stopTile(Map<String, dynamic> s) {
    final seq = (s['seq'] as num?)?.toInt();
    final label = (s['label'] as String?)?.trim();
    final segKm = (s['segment_km'] as num?)?.toDouble();
    final feeC = (s['fee_cents'] as num?)?.toInt() ?? 0;
    final drvC = (s['driver_cents'] as num?)?.toInt() ?? 0;
    final reached = s['reached_at'] != null;
    final removed = s['removed_at'] != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
          child: Text(seq?.toString() ?? '·',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (label != null && label.isNotEmpty) ? label : 'Parada sem nome',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  decoration: removed ? TextDecoration.lineThrough : null,
                  color: removed ? AppColors.textSubtle : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_eur(feeC)} · motorista ${_eur(drvC)}'
                '${segKm != null ? ' · ${segKm.toStringAsFixed(1)} km' : ''}',
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _tag(reached ? 'Motorista chegou' : 'Não chegou',
                      reached ? AppColors.primary : AppColors.warning),
                  if (removed) _tag('Removida', AppColors.error),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _RideStatusChip extends StatelessWidget {
  const _RideStatusChip({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusStyle(status);
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

// ── Helpers partilhados ──
(String, Color) _statusStyle(String? s) => switch (s) {
      // Corrida criada mas estacionada: o dispatch IGNORA este estado, por isso
      // NÃO está a chamar motorista. Rótulo distinto de "Solicitada" de propósito.
      'aguarda_pagamento' => ('Aguardando pagamento', Colors.orange),
      'solicitada' => ('Solicitada', AppColors.warning),
      'motorista_atribuido' => ('Motorista atribuído', Colors.blue),
      'motorista_a_caminho' => ('A caminho', Colors.blue),
      'motorista_chegou' => ('Chegou', Colors.indigo),
      'em_andamento' => ('Em andamento', AppColors.primary),
      'finalizada' => ('Finalizada', AppColors.primary),
      'cancelada_cliente' => ('Cancelada (cliente)', AppColors.error),
      'cancelada_motorista' => ('Cancelada (motorista)', AppColors.error),
      'no_show' => ('No-show', AppColors.error),
      'sem_motorista' => ('Sem motorista', AppColors.error),
      _ => (s ?? '—', AppColors.textSecondary),
    };

String _statusLabel(String? s) => _statusStyle(s).$1;

/// Motivos de cancelamento gravados por máquina — traduzidos para o admin
/// (PT-BR) em vez de aparecer a string crua. `payment_failed` vem do app
/// (cliente recusou/não concluiu); `payment_timeout` vem do cron que limpa as
/// corridas presas em `aguarda_pagamento`.
String _cancelReasonLabel(String reason) => switch (reason) {
      'payment_failed' => 'Pagamento não concluído',
      'payment_timeout' => 'Pagamento expirou (limpeza automática)',
      _ => reason,
    };

String _eur(int cents) => '€${(cents / 100).toStringAsFixed(2)}';

String _eurRaw(dynamic cents) {
  final n = (cents as num?)?.toInt() ?? 0;
  return (n / 100).toStringAsFixed(2);
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
