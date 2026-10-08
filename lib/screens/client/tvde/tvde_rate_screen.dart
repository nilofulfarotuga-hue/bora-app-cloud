import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_fare_view.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/pending_rating_queue.dart';
import '../../../services/tip_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/tip_selector.dart';
import '../../../widgets/tvde/tvde_roundtrip_driver_notice.dart';

import '../../../l10n/tr.dart';

/// TVDE — Avaliação do motorista pelo passageiro (tvde_rate, subject 'driver').
class TvdeRateScreen extends StatefulWidget {
  const TvdeRateScreen({super.key, required this.ride});
  final TvdeRide ride;

  /// [04/10 · corridas 0d979026 e 8c7f5ca6] Abre a avaliação da última corrida
  /// terminada que ficou por avaliar — a que o `TvdeStore.loadActiveRide`
  /// deixou em `rideAwaitingRating`. Serve o caso em que `finalizada` chegou
  /// com a app fechada (ou o separador recarregado): o ecrã da corrida já não
  /// existia e ninguém voltava a pedir as estrelas. Sem pendente, não faz nada.
  static Future<void> abrirSePendente(BuildContext context) async {
    final ride = context.read<TvdeStore>().rideAwaitingRating;
    if (ride == null || !ride.aguardaAvaliacaoCliente) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TvdeRateScreen(ride: ride)),
    );
  }

  @override
  State<TvdeRateScreen> createState() => _TvdeRateScreenState();
}

class _TvdeRateScreenState extends State<TvdeRateScreen> {
  /// Tempo máximo que este ecrã espera pelo envio antes de fechar na mesma.
  /// A corrida já acabou e o dinheiro já está resolvido — prender a pessoa
  /// por causa de uma estrela é inaceitável.
  static const Duration _timeoutEnvio = Duration(seconds: 6);

  int _stars = 5;
  final _comment = TextEditingController();
  int _packageCents = TvdeRoundtripPrice.fallbackCents;

  /// Estado de envio PRÓPRIO deste ecrã.
  ///
  /// **Cicatriz (corrida real, 05/09/2026):** aqui estava `store.busy`, o
  /// flag global do `TvdeStore` que dezenas de operações mexem. Bastava um
  /// refresh ou um poll a meio para o "Enviar avaliação" nascer morto e
  /// rodar para sempre — o passageiro só saiu pelo "Agora não", que é um
  /// `TextButton` sem essa dependência. Um botão trava-se pelo SEU pedido,
  /// nunca pelo estado de ocupado de um store partilhado.
  bool _sending = false;

  /// Gorjeta ao motorista (missão 03/10 · bloco 3), igual à Uber: no mesmo
  /// ecrã da avaliação, valores rápidos + outro valor + sem gorjeta. Cobrada à
  /// parte no cartão/MB Way da corrida; 100% para o motorista. Só aparece se
  /// `tips_enabled` estiver ligado e a corrida tiver sido paga na app.
  bool _gorjetaLigada = false;
  int _tipCents = 0;

  @override
  void initState() {
    super.initState();
    TipService.ligada().then((v) {
      if (mounted) setState(() => _gorjetaLigada = v);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final store = context.read<TvdeStore>();
      final pkg = await TvdeRoundtripPrice.loadForRide(store, widget.ride);
      if (mounted) setState(() => _packageCents = pkg);
      // Avaliações que ficaram por enviar numa corrida anterior seguem agora.
      await PendingRatingQueue.flush(
        PendingRatingQueue.kindDriver,
        (rideId, stars, comment) =>
            store.rateDriver(rideId, stars, comment: comment),
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

    final store = context.read<TvdeStore>();
    final comment =
        _comment.text.trim().isEmpty ? null : _comment.text.trim();
    String? aviso;
    try {
      await store
          .rateDriver(widget.ride.id, _stars, comment: comment)
          .timeout(_timeoutEnvio);
    } catch (e) {
      debugPrint('TvdeRateScreen._submit erro => $e');
      final guardada = await PendingRatingQueue.save(
        kind: PendingRatingQueue.kindDriver,
        rideId: widget.ride.id,
        stars: _stars,
        comment: comment,
      );
      aviso = guardada
          ? 'Avaliação enviada mais tarde.'.tr
          : 'Não foi possível enviar a avaliação.'.tr;
    }

    // A gorjeta não depende da avaliação ter passado: são coisas separadas.
    if (_tipCents > 0 && _gorjetaLigada && widget.ride.isPaidOnline) {
      final r = await TipService.cobrar(
        target: 'tvde',
        id: widget.ride.id,
        cents: _tipCents,
        moment: 'after',
      );
      aviso = r.mensagem;
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
  /// duas vezes é inofensivo (`clearActiveRide` é idempotente); ficar por
  /// limpar deixava a corrida pendurada no store.
  void _sair() {
    context.read<TvdeStore>().clearActiveRide();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final fareView =
        TvdeFareView.of(widget.ride, packageCents: _packageCents);
    final covered = fareView.clientTotalCents == 0;
    final fare = fareView.clientTotalCents / 100;

    // Sair por QUALQUER porta — "Agora não", envio, seta do header ou botão
    // físico do Android — deixa o estado igual: a corrida ativa é limpa.
    // Sem isto, o botão de voltar do telemóvel saía sem limpar e a corrida
    // ficava pendurada no store.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        final store = context.read<TvdeStore>();
        store.clearActiveRide();
        // [04/10] Visto uma vez (enviada ou "Agora não") → não se volta a
        // pedir esta avaliação a cada abertura da app.
        unawaited(store.dismissRideAwaitingRating(widget.ride.id));
      },
      child: Scaffold(
        appBar: BoraScreenAppBar(title: 'Avaliar viagem'.tr),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
              BoraBottomActionBar.folgaInferior(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Spacing.lg),
              const Icon(Icons.check_circle,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: Spacing.md),
              Text('Viagem concluída'.tr,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: Spacing.xs),
              Text(
                  covered
                      ? (widget.ride.isRoundtripLeg
                          ? 'Volta incluída no pacote — não pagaste nada.'.tr
                          : 'Corrida incluída no teu plano — não pagaste nada.')
                      : 'Pagaste €{0}{1}'.trArgs([fare.toStringAsFixed(2), fareView.isPaidOnline ? ' no app.' : ' em dinheiro.']),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.xl),
              Text('Como foi o motorista?'.tr,
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
                    icon: Icon(
                      star <= _stars ? Icons.star : Icons.star_border,
                      color: AppColors.accent,
                    ),
                  );
                }),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _comment,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Comentário (opcional)'.tr,
                  alignLabelWithHint: true,
                ),
              ),
              if (_gorjetaLigada && widget.ride.isPaidOnline && !covered) ...[
                const SizedBox(height: Spacing.lg),
                Text('Queres deixar uma gorjeta ao motorista?'.tr,
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: Spacing.sm),
                TipSelector(
                  enabled: !_sending,
                  onChanged: (cents) => _tipCents = cents,
                ),
              ],
              const SizedBox(height: Spacing.xl),
              BoraPrimaryButton(
                label: 'Enviar avaliação'.tr,
                icon: Icons.send,
                loading: _sending,
                onPressed: _submit,
              ),
              const SizedBox(height: Spacing.sm),
              TextButton(onPressed: _skip, child: Text('Agora não'.tr)),
            ],
          ),
        ),
      ),
    );
  }
}
