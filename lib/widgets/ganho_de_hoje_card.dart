import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../screens/ganhos_screen.dart';

/// Cartão "Ganhos de hoje" — o MESMO número nos quatro ecrãs de casa de quem
/// trabalha: TVDE, estafeta, limpeza e lavagem de carros.
///
/// 2026-09-05: o cartão do ecrã TVDE mostrava €4,00 num dia que tinha €9,32,
/// porque somava só a tabela das corridas — a entrega feita nesse mesmo dia
/// não entrava na conta. A regra é que o prestador vê sempre o total do dia
/// dele, de tudo o que faz, esteja no ecrã que estiver. Por isso o número vem
/// da RPC `meu_ganho_ao_vivo` (a mesma fonte do ecrã Ganhos): uma só verdade,
/// quatro sítios a mostrá-la. Um cartão partilhado em vez de quatro cópias —
/// quatro cópias acabam sempre a divergir.
class GanhoDeHojeCard extends StatefulWidget {
  const GanhoDeHojeCard({
    super.key,
    this.recarregarQuando,
    this.valorInicialCents,
  });

  /// Store do ecrã onde o cartão vive. Quando notifica (um trabalho acabou,
  /// uma corrida fechou), o cartão volta a ler o total do dia. Fica opcional
  /// para o cartão poder ser usado num ecrã que não tenha store própria.
  final Listenable? recarregarQuando;

  /// Valor que o ecrã já tem em mão, para pintar o primeiro frame sem traço.
  /// Também vem de `meu_ganho_ao_vivo`, por isso não há duas contas.
  final int? valorInicialCents;

  @override
  State<GanhoDeHojeCard> createState() => _GanhoDeHojeCardState();
}

class _GanhoDeHojeCardState extends State<GanhoDeHojeCard>
    with WidgetsBindingObserver {
  int? _hojeCents;
  bool _aLer = false;

  @override
  void initState() {
    super.initState();
    _hojeCents = widget.valorInicialCents;
    WidgetsBinding.instance.addObserver(this);
    widget.recarregarQuando?.addListener(_ler);
    _ler();
  }

  @override
  void didUpdateWidget(covariant GanhoDeHojeCard old) {
    super.didUpdateWidget(old);
    if (old.recarregarQuando != widget.recarregarQuando) {
      old.recarregarQuando?.removeListener(_ler);
      widget.recarregarQuando?.addListener(_ler);
    }
  }

  @override
  void dispose() {
    widget.recarregarQuando?.removeListener(_ler);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ler();
  }

  Future<void> _ler() async {
    if (_aLer) return;
    _aLer = true;
    try {
      // `Supabase.instance` rebenta se ainda não houver arranque (é o caso num
      // teste de widget), por isso fica dentro do try tal como a chamada.
      final sb = Supabase.instance.client;
      if (sb.auth.currentUser == null) return;
      final g = await sb.rpc('meu_ganho_ao_vivo');
      if (!mounted) return;
      if (g is Map && g['ok'] == true) {
        setState(() => _hojeCents = (g['hoje_cents'] as num?)?.toInt() ?? 0);
      }
    } catch (e) {
      // Sem rede ou RPC em baixo: o cartão fica com o último valor conhecido
      // em vez de mostrar zero — zero seria uma mentira sobre o dia dele.
      debugPrint('[GanhoDeHoje] meu_ganho_ao_vivo: $e');
    } finally {
      _aLer = false;
    }
  }

  String get _valor {
    final c = _hojeCents;
    if (c == null) return '—';
    return '€${(c / 100).toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GanhosScreen()),
      ).then((_) => _ler()),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet,
                color: AppColors.primary, size: 20),
            const SizedBox(width: Spacing.sm),
            const Text('Ganhos de hoje',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const Spacer(),
            Text(_valor,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                color: AppColors.primary, size: 18),
          ],
        ),
      ),
    );
  }
}
