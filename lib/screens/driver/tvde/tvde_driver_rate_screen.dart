import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/pending_rating_queue.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Avaliação do passageiro pelo motorista no fim da corrida
/// (tvde_rate → subject_type='tvde_passenger'). Mostra o ganho do motorista.
class TvdeDriverRateScreen extends StatefulWidget {
  const TvdeDriverRateScreen({super.key, required this.ride});
  final TvdeRide ride;

  @override
  State<TvdeDriverRateScreen> createState() => _TvdeDriverRateScreenState();
}

class _TvdeDriverRateScreenState extends State<TvdeDriverRateScreen> {
  /// Tempo máximo que este ecrã espera pelo envio antes de fechar na mesma.
  /// A corrida já acabou — o motorista tem de poder voltar a ficar online.
  static const Duration _timeoutEnvio = Duration(seconds: 6);

  int _stars = 5;
  final _comment = TextEditingController();

  /// Estado de envio PRÓPRIO deste ecrã.
  ///
  /// **Cicatriz (corrida real, 05/09/2026):** aqui estava `store.busy`, o
  /// flag global do `TvdeDriverStore` que dezenas de operações mexem — o
  /// mesmo defeito que prendeu o passageiro no ecrã de avaliação dele.
  /// Um botão trava-se pelo SEU pedido, nunca pelo estado de ocupado de um
  /// store partilhado.
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Avaliações que ficaram por enviar numa corrida anterior seguem agora.
      final store = context.read<TvdeDriverStore>();
      await PendingRatingQueue.flush(
        PendingRatingQueue.kindPassenger,
        (rideId, stars, comment) =>
            store.ratePassenger(rideId, stars, comment: comment),
      );
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);

    final store = context.read<TvdeDriverStore>();
    final comment =
        _comment.text.trim().isEmpty ? null : _comment.text.trim();
    String? aviso;
    try {
      await store
          .ratePassenger(widget.ride.id, _stars, comment: comment)
          .timeout(_timeoutEnvio);
    } catch (e) {
      debugPrint('TvdeDriverRateScreen._submit erro => $e');
      final guardada = await PendingRatingQueue.save(
        kind: PendingRatingQueue.kindPassenger,
        rideId: widget.ride.id,
        stars: _stars,
        comment: comment,
      );
      aviso = guardada
          ? 'Avaliação enviada mais tarde.'
          : 'Não foi possível enviar a avaliação.';
    }

    if (!mounted) return;
    // Repor o guarda ANTES de fechar: se por alguma razão o fecho não
    // acontecer, o botão continua vivo em vez de ficar preso a rodar.
    setState(() => _sending = false);
    if (aviso != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(aviso)));
    }
    _sair();
  }

  void _skip() => _sair();

  /// Saída deste ecrã: limpa a corrida ativa e fecha.
  ///
  /// O `PopScope` no `build` faz o mesmo para as portas que não passam por
  /// aqui — a seta do header e o botão físico de voltar do Android. Limpar
  /// duas vezes é inofensivo; ficar por limpar deixava a corrida pendurada
  /// e o motorista sem conseguir voltar a ficar online.
  void _sair() {
    context.read<TvdeDriverStore>().clearActive();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final earn = (ride.driverEarnCents ?? 0) / 100;

    // Sair por QUALQUER porta — "Agora não", envio, seta do header ou botão
    // físico do Android — deixa o estado igual: a corrida ativa é limpa.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<TvdeDriverStore>().clearActive();
      },
      child: Scaffold(
        appBar: const BoraScreenAppBar(title: 'Fim da corrida'),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Spacing.lg),
              const Icon(Icons.check_circle,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: Spacing.md),
              Text('Viagem concluída',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: Spacing.xs),
              Text('Ganhaste €${earn.toStringAsFixed(2)} nesta corrida.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.xl),
              Text('Como foi o passageiro?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: Spacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return IconButton(
                    iconSize: 40,
                    onPressed: () => setState(() => _stars = star),
                    icon: Icon(star <= _stars ? Icons.star : Icons.star_border,
                        color: AppColors.accent),
                  );
                }),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _comment,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comentário (opcional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: Spacing.xl),
              BoraPrimaryButton(
                label: 'Enviar avaliação',
                icon: Icons.send,
                loading: _sending,
                onPressed: _submit,
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(onPressed: _skip, child: const Text('Agora não')),
            ],
          ),
        ),
      ),
    );
  }
}
