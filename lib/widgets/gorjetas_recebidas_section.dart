import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';

/// Gorjetas recebidas pelo estafeta/motorista (missão 03/10 · bloco 3).
///
/// Uma linha "Gorjeta" por pedido/corrida, 100% para quem a recebe. As pagas
/// por cartão/MB Way entram no acerto semanal; as de dinheiro já estão na mão.
/// Lê `public.tips` (RLS: cada prestador só vê as suas). Sem gorjetas → nada.
class GorjetasRecebidasSection extends StatefulWidget {
  const GorjetasRecebidasSection({super.key});

  @override
  State<GorjetasRecebidasSection> createState() =>
      _GorjetasRecebidasSectionState();
}

class _GorjetasRecebidasSectionState extends State<GorjetasRecebidasSection> {
  List<Map<String, dynamic>> _linhas = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final desde =
          DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
      final res = await Supabase.instance.client
          .from('tips')
          .select('id, amount_cents, method, target, paid_at, status')
          .eq('provider_user_id', uid)
          .inFilter('status', ['succeeded', 'cash_collected'])
          .gte('paid_at', desde)
          .order('paid_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() => _linhas = List<Map<String, dynamic>>.from(res as List));
      }
    } catch (e) {
      debugPrint('[Gorjetas] $e');
    }
  }

  String _eur(num cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    if (_linhas.isEmpty) return const SizedBox.shrink();
    final total =
        _linhas.fold<int>(0, (s, l) => s + ((l['amount_cents'] as num?)?.toInt() ?? 0));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gorjetas (últimos 30 dias)'.tr,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              _eur(total),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary),
            ),
            Text(
              'São todas tuas. As de cartão e MB WAY entram no acerto da semana.'.tr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Divider(height: 20),
            for (final l in _linhas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.volunteer_activism_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${'Gorjeta'.tr} · ${l['target'] == 'tvde' ? 'corrida'.tr : 'entrega'.tr}'
                        ' · ${l['method'] == 'cash' ? 'dinheiro'.tr : (l['method'] == 'mbway' ? 'MB WAY' : 'cartão'.tr)}',
                      ),
                    ),
                    Text(_eur((l['amount_cents'] as num?) ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
