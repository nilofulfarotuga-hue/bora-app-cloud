import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Item 50 (paridade-admin-360): Config Reservas Pro no admin — visão global
/// das regras de pacing por restaurante (admin_list_pacing_rules), autoridade
/// para ativar/desativar regras (admin_toggle_pacing_rule, auditado) e fila
/// de espera de hoje (admin_list_waitlist_today). A edição fina das regras
/// continua no parceiro (partner_pacing_rules_screen), que é o dono.
class AdminReservationsConfigScreen extends StatefulWidget {
  const AdminReservationsConfigScreen({super.key});
  @override
  State<AdminReservationsConfigScreen> createState() =>
      _AdminReservationsConfigScreenState();
}

class _AdminReservationsConfigScreenState
    extends State<AdminReservationsConfigScreen> {
  List<_PacingRule> _rules = const [];
  List<_WaitlistRow> _waitlist = const [];
  bool _loading = true;
  String? _error;

  static const _dias = [
    'Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = Supabase.instance.client;
      final rulesRes = await client.rpc('admin_list_pacing_rules');
      final wlRes = await client.rpc('admin_list_waitlist_today');
      if (mounted) {
        setState(() {
          _rules = (rulesRes as List)
              .map((e) =>
                  _PacingRule.fromJson((e as Map).cast<String, dynamic>()))
              .toList();
          _waitlist = (wlRes as List)
              .map((e) =>
                  _WaitlistRow.fromJson((e as Map).cast<String, dynamic>()))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(_PacingRule r, bool active) async {
    try {
      await Supabase.instance.client.rpc('admin_toggle_pacing_rule', params: {
        'p_rule_id': r.id,
        'p_active': active,
      });
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // agrupa regras por restaurante
    final byRestaurant = <String, List<_PacingRule>>{};
    for (final r in _rules) {
      byRestaurant.putIfAbsent(r.restaurantName, () => []).add(r);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Reservas Pro — Config'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_waitlist.isNotEmpty) ...[
                        const Text('Fila de espera hoje',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 6),
                        Card(
                          child: Column(
                            children: _waitlist
                                .map((w) => ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.people_outline,
                                          color: AppColors.accent),
                                      title: Text(w.restaurantName),
                                      trailing: Text('${w.emEspera} em espera',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      const Text('Regras de pacing por restaurante',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 6),
                      if (byRestaurant.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                              child: Text(
                                  'Nenhum restaurante definiu regras de pacing.\n'
                                  'As regras são criadas pelo parceiro na app dele.',
                                  textAlign: TextAlign.center)),
                        ),
                      ...byRestaurant.entries.map((entry) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              title: Text(entry.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text('${entry.value.length} regras · '
                                  '${entry.value.where((r) => r.active).length} ativas'),
                              children: entry.value
                                  .map((r) => SwitchListTile(
                                        dense: true,
                                        title: Text(
                                            '${_dias[r.dayOfWeek % 7]} · ${r.slotStart}–${r.slotEnd}'),
                                        subtitle: Text(
                                            'máx ${r.maxCovers} lugares · '
                                            '${r.maxReservations} reservas · '
                                            '${r.walkInPct}% walk-in'),
                                        value: r.active,
                                        activeThumbColor: AppColors.primary,
                                        onChanged: (v) => _toggle(r, v),
                                      ))
                                  .toList(),
                            ),
                          )),
                    ],
                  ),
                ),
    );
  }
}

class _PacingRule {
  final String id;
  final String restaurantName;
  final int dayOfWeek;
  final String slotStart;
  final String slotEnd;
  final int maxCovers;
  final int maxReservations;
  final int walkInPct;
  final bool active;

  _PacingRule({
    required this.id,
    required this.restaurantName,
    required this.dayOfWeek,
    required this.slotStart,
    required this.slotEnd,
    required this.maxCovers,
    required this.maxReservations,
    required this.walkInPct,
    required this.active,
  });

  factory _PacingRule.fromJson(Map<String, dynamic> j) => _PacingRule(
        id: j['id'] as String,
        restaurantName: (j['restaurant_name'] as String?) ?? '—',
        dayOfWeek: (j['day_of_week'] as num?)?.toInt() ?? 0,
        slotStart: _hhmm(j['slot_start'] as String?),
        slotEnd: _hhmm(j['slot_end'] as String?),
        maxCovers: (j['max_covers'] as num?)?.toInt() ?? 0,
        maxReservations: (j['max_reservations'] as num?)?.toInt() ?? 0,
        walkInPct: (j['walk_in_reserved_pct'] as num?)?.toInt() ?? 0,
        active: (j['active'] as bool?) ?? false,
      );

  static String _hhmm(String? t) =>
      t == null ? '—' : (t.length >= 5 ? t.substring(0, 5) : t);
}

class _WaitlistRow {
  final String restaurantName;
  final int emEspera;
  _WaitlistRow({required this.restaurantName, required this.emEspera});
  factory _WaitlistRow.fromJson(Map<String, dynamic> j) => _WaitlistRow(
        restaurantName: (j['restaurant_name'] as String?) ?? '—',
        emEspera: (j['em_espera'] as num?)?.toInt() ?? 0,
      );
}
