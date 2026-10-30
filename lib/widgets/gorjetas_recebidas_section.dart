import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';

/// Uma gorjeta como o estafeta/motorista a vê (regra do Danilo, 30/10/2026).
///
/// Gorjeta paga DEPOIS (avaliação da entrega ou da corrida) com cartão/MB Way
/// é um pagamento à parte: quem a recebe fica com ela MENOS a taxa exata que a
/// Stripe cobrou nesse pagamento (ex.: 2,00 € − 0,28 € = 1,72 €). Gorjeta do
/// carrinho e gorjeta em dinheiro chegam inteiras.
///
/// O que ele recebe vem do servidor (`tips.liquido_prestador_cents`, coluna
/// gerada). Enquanto a taxa real ainda não chegou da Stripe, o servidor já a
/// estima; a taxa mostrada é sempre valor − o que recebe.
class GorjetaRecebida {
  const GorjetaRecebida({required this.valorCents, required this.recebeCents});

  factory GorjetaRecebida.daLinha(Map<String, dynamic> l) {
    final valor = (l['amount_cents'] as num?)?.toInt() ?? 0;
    final recebe = (l['liquido_prestador_cents'] as num?)?.toInt() ?? valor;
    return GorjetaRecebida(
        valorCents: valor, recebeCents: recebe.clamp(0, valor < 0 ? 0 : valor));
  }

  /// O que o cliente deu.
  final int valorCents;

  /// O que fica para o estafeta/motorista.
  final int recebeCents;

  /// Taxa do pagamento descontada (0 nas do carrinho e nas de dinheiro).
  int get taxaCents => valorCents - recebeCents;

  bool get temTaxa => taxaCents > 0;

  /// "Gorjeta 2,00 € · taxa do pagamento −0,28 € · recebes 1,72 €"; sem taxa,
  /// null (a linha mostra só o valor).
  String? get detalhe => temTaxa
      ? 'Gorjeta {0} · taxa do pagamento −{1} · recebes {2}'
          .trArgs([eurCents(valorCents), eurCents(taxaCents), eurCents(recebeCents)])
      : null;

  /// Soma do que ele recebe.
  static int total(Iterable<GorjetaRecebida> g) =>
      g.fold<int>(0, (s, x) => s + x.recebeCents);

  static String eurCents(num cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
}

/// Gorjetas recebidas pelo estafeta/motorista (missão 03/10 · bloco 3).
///
/// Uma linha "Gorjeta" por pedido/corrida, com o que fica para quem a recebe
/// (regra de 30/10: a paga depois por cartão/MB Way sai sem a taxa da Stripe).
/// As pagas por cartão/MB Way entram no acerto semanal; as de dinheiro já
/// estão na mão. Lê `public.tips` (RLS: cada prestador só vê as suas). Sem
/// gorjetas → nada.
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
          .select(
              'id, amount_cents, liquido_prestador_cents, method, target, paid_at, status')
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

  @override
  Widget build(BuildContext context) {
    if (_linhas.isEmpty) return const SizedBox.shrink();
    final gorjetas = [for (final l in _linhas) GorjetaRecebida.daLinha(l)];
    final total = GorjetaRecebida.total(gorjetas);
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
              GorjetaRecebida.eurCents(total),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary),
            ),
            Text(
              'As de cartão e MB WAY entram no acerto da semana. Nas dadas depois, sai a taxa do pagamento.'.tr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Divider(height: 20),
            for (var i = 0; i < _linhas.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.volunteer_activism_outlined,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${'Gorjeta'.tr} · ${_linhas[i]['target'] == 'tvde' ? 'corrida'.tr : 'entrega'.tr}'
                            ' · ${_linhas[i]['method'] == 'cash' ? 'dinheiro'.tr : (_linhas[i]['method'] == 'mbway' ? 'MB WAY' : 'cartão'.tr)}',
                          ),
                          if (gorjetas[i].detalhe != null)
                            Text(
                              gorjetas[i].detalhe!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    Text(GorjetaRecebida.eurCents(gorjetas[i].recebeCents),
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
