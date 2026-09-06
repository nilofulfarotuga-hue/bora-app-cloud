import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — Pacotes ida-e-volta (€8).
///
/// Lê `admin_tvde_roundtrips(p_limit)` — RPC admin read-only que já existia em
/// produção mas não tinha ecrã nenhum a chamá-la (os vales estavam invisíveis
/// para o admin). Idioma: PT-BR.
class AdminTvdeRoundtripsScreen extends StatefulWidget {
  const AdminTvdeRoundtripsScreen({super.key});

  @override
  State<AdminTvdeRoundtripsScreen> createState() =>
      _AdminTvdeRoundtripsScreenState();
}

class _AdminTvdeRoundtripsScreenState extends State<AdminTvdeRoundtripsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_tvde_roundtrips', params: {'p_limit': 100});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Ida e volta — Bora Motorista',
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
                      'Nenhum pacote ida-e-volta comprado ainda.',
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
              itemBuilder: (_, i) => _RoundtripCard(data: rows[i]),
            );
          },
        ),
      ),
    );
  }
}

class _RoundtripCard extends StatelessWidget {
  const _RoundtripCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? '—';
    final paid = (data['paid_cents'] as num?)?.toInt() ?? 0;
    final hasReturn = data['return_ride_id'] != null;
    final expiresAt = data['expires_at'];
    final expired = _isExpired(expiresAt);

    final (label, color) = switch (status) {
      'usado' => ('Volta usada', AppColors.primary),
      'ativo' when expired => ('Expirado', AppColors.textSubtle),
      'ativo' => ('Por usar', AppColors.accent),
      'expirado' => ('Expirado', AppColors.textSubtle),
      _ => (status, AppColors.textSubtle),
    };

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
                  child: Text('€${(paid / 100).toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _line('Cliente', _shortId(data['client_id'])),
            _line('Corrida de ida', _shortId(data['outbound_ride_id'])),
            _line('Corrida de volta',
                hasReturn ? _shortId(data['return_ride_id']) : 'ainda não usada'),
            _line('Comprado em', _fmtDateTime(data['created_at'])),
            _line('Válido até', _fmtDateTime(expiresAt)),
            // RASTRO DO PAGAMENTO (2026-09-05) — é isto que se olha quando um
            // cliente diz que pagou o pacote duas vezes. Dois pacotes com ids
            // DIFERENTES e datas coladas = cobrança dupla. Pacotes pagos em
            // dinheiro não têm pagamento na Stripe e não mostram esta linha.
            if ((data['payment_intent_id'] as String?)?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: SelectableText(
                  'Pagamento: ${data['payment_intent_id']}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.textSubtle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$label: $value',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      );
}

bool _isExpired(dynamic iso) {
  if (iso == null) return false;
  final d = DateTime.tryParse(iso.toString());
  return d != null && d.isBefore(DateTime.now());
}

String _shortId(dynamic id) {
  if (id == null) return '—';
  final s = id.toString();
  return s.length <= 8 ? s : '${s.substring(0, 8)}…';
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
