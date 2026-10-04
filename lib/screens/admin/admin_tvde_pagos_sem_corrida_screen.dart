import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';
import '../../utils/hora_lisboa_ext.dart';

/// Bora Motorista (TVDE) — Pagos sem corrida criada.
///
/// Cicatriz de 04/10/2026 (cliente Priscila): pacote ida-e-volta pago por
/// cartão no Safari, a corrida de ida nunca nasceu e ninguém soube. O servidor
/// passou a avisar em 2 minutos (`tvde_roundtrip_sweep_orfaos`); esta lista é
/// onde se vê e se resolve. Lê `admin_tvde_pagos_sem_corrida`. Idioma: PT-BR.
class AdminTvdePagosSemCorridaScreen extends StatefulWidget {
  const AdminTvdePagosSemCorridaScreen({super.key});

  @override
  State<AdminTvdePagosSemCorridaScreen> createState() =>
      _AdminTvdePagosSemCorridaScreenState();
}

class _AdminTvdePagosSemCorridaScreenState
    extends State<AdminTvdePagosSemCorridaScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String? _aReparar;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_tvde_pagos_sem_corrida', params: {'p_dias': 30});
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Liga o pacote pago à corrida de ida que o cliente tem à espera e chama
  /// motorista. Não mexe em dinheiro: o pagamento já existe.
  Future<void> _reparar(String creditId) async {
    setState(() => _aReparar = creditId);
    try {
      final res = await Supabase.instance.client.rpc(
          'admin_tvde_roundtrip_reparar',
          params: {'p_credit_id': creditId});
      final m = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (m['ok'] == true) {
        _toast('Corrida de ida ligada ao pacote. Motorista sendo chamado.');
      } else {
        _toast(switch (m['motivo']) {
          'sem_ida_pendente' =>
            'O cliente não tem corrida à espera. Fale com ele: peça para pedir de novo ou combine a corrida.',
          'vale_sem_pagamento_online' => 'Este pacote foi pago em dinheiro.',
          _ => 'Não deu para ligar: ${m['motivo'] ?? 'erro'}.',
        });
      }
    } catch (e) {
      _toast(humanizeAdminRpcError(e));
    } finally {
      if (mounted) setState(() => _aReparar = null);
    }
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pagos sem corrida criada',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
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
                  Text(humanizeAdminRpcError(snap.error!),
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
                    child: Text(
                      'Nenhum pagamento sem corrida nos últimos 30 dias.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: rows.length,
              itemBuilder: (_, i) => _card(rows[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> d) {
    final id = d['credit_id'].toString();
    final status = (d['status'] as String?) ?? '—';
    final paid = (d['paid_cents'] as num?)?.toInt() ?? 0;
    final porResolver = status == 'ativo' && d['return_ride_id'] == null;
    final temIdaPendente = d['ida_pendente_id'] != null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '€${(paid / 100).toStringAsFixed(2)} · pacote ida e volta',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                Text(
                  porResolver ? 'POR RESOLVER' : _rotuloStatus(status),
                  style: TextStyle(
                      color:
                          porResolver ? AppColors.error : AppColors.textSubtle,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _line('Cliente',
                '${d['cliente_nome'] ?? '—'} · ${d['cliente_contacto'] ?? 'sem contato'}'),
            _line('Pago em', _fmtDateTime(d['created_at'])),
            _line('Última rota tentada', (d['ultima_rota'] as String?) ?? '—'),
            _line(
                'Aviso enviado',
                d['alertado_em'] == null
                    ? 'ainda não'
                    : _fmtDateTime(d['alertado_em'])),
            if (d['return_ride_id'] != null)
              _line('Volta', 'já usada (a ida foi feita por fora)'),
            SelectableText('Pagamento: ${d['payment_intent_id']}',
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppColors.textSubtle)),
            if (porResolver) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _aReparar == null ? () => _reparar(id) : null,
                  icon: const Icon(Icons.link),
                  label: Text(temIdaPendente
                      ? 'Criar a corrida (ligar à ida que está à espera)'
                      : 'Tentar ligar à corrida do cliente'),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Reembolso: para devolver este pagamento, use o código acima no Stripe. '
                'O botão de reembolso direto ainda não existe para pacote sem corrida.',
                style: TextStyle(fontSize: 11, color: AppColors.textSubtle),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _rotuloStatus(String s) => switch (s) {
        'usado' => 'Volta usada',
        'anulado' => 'Reembolsado',
        'expirado' => 'Expirado',
        _ => s,
      };

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$label: $value',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLisboa();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
