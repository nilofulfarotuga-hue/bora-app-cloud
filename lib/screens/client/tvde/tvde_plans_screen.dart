import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_plan_quote.dart';
import '../../../models/tvde_subscription.dart';
import '../../../services/directions_service.dart';
import '../../../services/payment_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../reservation/reservation_payment_method_sheet.dart';
import 'plan_mbway_waiting_dialog.dart';

/// TVDE — Planos de assinatura + contador diário.
///
/// [Rota do plano · 2026-08-25] O preço do plano depende da ROTA HABITUAL do
/// cliente: primeiro escolhe origem e destino (mesmo seletor de moradas e mesmo
/// cálculo de distância da corrida normal), depois o servidor orça
/// (`tvde_quote_plan`) e só então o ecrã mostra a CONTA ABERTA e acende o botão
/// de pagar. Nenhum valor de plano é conhecido pelo app — vem sempre do
/// servidor, tal como o total cobrado pela Edge Function `tvde-plan-payment`.
class TvdePlansScreen extends StatefulWidget {
  const TvdePlansScreen({super.key});

  @override
  State<TvdePlansScreen> createState() => _TvdePlansScreenState();
}

class _TvdePlansScreenState extends State<TvdePlansScreen> {
  static const _plans = ['semanal', 'quinzenal', 'mensal'];
  static const _labels = {
    'semanal': 'Plano Semanal',
    'quinzenal': 'Plano Quinzenal',
    'mensal': 'Plano Mensal',
  };

  final DirectionsService _directions = DirectionsService();
  final _originController = TextEditingController();
  final _destController = TextEditingController();

  LatLng? _origin;
  LatLng? _dest;
  String? _originLabel;
  String? _destLabel;

  /// Distância da rota escolhida (km). null = ainda não há rota.
  double? _routeKm;
  bool _quoting = false;

  /// plano → orçamento para a rota escolhida. Vazio até haver rota.
  Map<String, TvdePlanQuote> _quotes = const {};

  /// plano → "forma" do plano (viagens, dias, km incluídos, €/km) pedida ao
  /// servidor a 0 km. Serve só para os cartões dizerem quantas viagens dão —
  /// NUNCA para mostrar valor sem rota.
  Map<String, TvdePlanQuote> _shape = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvdeStore>().loadSubscription();
      context.read<TvdeStore>().loadPlanRequest();
    });
    _loadShape();
  }

  @override
  void dispose() {
    _directions.dispose();
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  /// Pergunta ao servidor a forma de cada plano (viagens/dias/km incluídos e
  /// €/km do excesso). Orçamos a 1 km — distância simbólica, sempre dentro do
  /// incluído, só para ler a FORMA do plano; o valor deste orçamento nunca é
  /// mostrado. Best-effort: se falhar, os cartões apenas não mostram a
  /// contagem de viagens — nunca inventamos números.
  Future<void> _loadShape() async {
    final store = context.read<TvdeStore>();
    final results = await Future.wait(_plans.map((p) => store.quotePlan(p, 1)));
    if (!mounted) return;
    final map = <String, TvdePlanQuote>{};
    for (var i = 0; i < _plans.length; i++) {
      final q = results[i];
      if (q != null && q.ridesTotal > 0) map[_plans[i]] = q;
    }
    setState(() => _shape = map);
  }

  void _onOriginSelected(String address, LatLng? coords) {
    if (coords == null) return;
    setState(() {
      _origin = coords;
      _originLabel = address;
    });
    _recalcRoute();
  }

  void _onDestSelected(String address, LatLng? coords) {
    if (coords == null) return;
    setState(() {
      _dest = coords;
      _destLabel = address;
    });
    _recalcRoute();
  }

  /// Mudou o texto à mão → a rota deixa de estar confirmada e o orçamento cai
  /// (o botão de pagar apaga-se outra vez).
  void _invalidateRoute() {
    if (_routeKm == null && _quotes.isEmpty) return;
    setState(() {
      _routeKm = null;
      _quotes = const {};
    });
  }

  /// Distância da rota — MESMO cálculo da corrida normal: rota real do
  /// Directions (2 tentativas, porque uma falha transitória subestimava o km)
  /// e haversine só como último recurso.
  Future<void> _recalcRoute() async {
    if (_origin == null || _dest == null) return;
    final store = context.read<TvdeStore>();
    setState(() => _quoting = true);

    double km = double.parse(
        const Distance().as(LengthUnit.Kilometer, _origin!, _dest!)
            .toStringAsFixed(2));
    var isRealRoute = false;
    for (var attempt = 0; attempt < 2 && !isRealRoute; attempt++) {
      try {
        final route = await _directions.fetchRoute(
          origin: _origin!,
          destination: _dest!,
        );
        if (route != null && route.distanceKm > 0) {
          km = double.parse(route.distanceKm.toStringAsFixed(2));
          isRealRoute = true;
        }
      } catch (_) {
        // mantém haversine; volta a tentar se ainda houver tentativa
      }
    }

    final results = await Future.wait(_plans.map((p) => store.quotePlan(p, km)));
    if (!mounted) return;
    final map = <String, TvdePlanQuote>{};
    for (var i = 0; i < _plans.length; i++) {
      final q = results[i];
      if (q != null && q.priceCents > 0) map[_plans[i]] = q;
    }
    setState(() {
      _routeKm = km;
      _quotes = map;
      _quoting = false;
    });
  }

  /// Cliente adere pagando por **cartão OU MB Way** (dinheiro não é permitido
  /// no plano). O valor é o do orçamento do servidor para a rota escolhida — a
  /// Edge Function recalcula-o e é esse que cobra.
  Future<void> _aderir(String plan) async {
    final quote = _quotes[plan];
    final km = _routeKm;
    if (quote == null || km == null) return;
    final label = _labels[plan]!;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O pagamento do plano está disponível na app móvel.')));
      return;
    }

    final choice = await showModalBottomSheet<ReservationPaymentChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReservationPaymentMethodSheet(
          amountEur: quote.priceCents / 100, title: label),
    );
    if (choice == null || !mounted) return;

    final store = context.read<TvdeStore>();
    final messenger = ScaffoldMessenger.of(context);

    // ── MB Way ──────────────────────────────────────────────────────────────
    if (choice.method == ReservationPaymentMethod.mbway) {
      final created = await store.createPlanPaymentMbway(
        plan,
        choice.mbwayPhone!,
        distanceKm: km,
        originLabel: _originLabel,
        destLabel: _destLabel,
      );
      if (!mounted) return;
      if (created == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Não foi possível iniciar o MBWay. Confirma o número '
                'e tenta de novo.')));
        return;
      }
      final chargedCents =
          (created['amountCents'] as num?)?.toInt() ?? quote.priceCents;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PlanMbwayWaitingDialog(
          plan: plan,
          paymentIntentId: created['paymentIntentId'] as String,
          amount: chargedCents / 100,
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(ok == true
              ? 'Plano ativo! Já podes usar as corridas incluídas.'
              : 'Não recebemos a confirmação MBWay. Se pagaste, reabre os '
                  'Planos; senão tenta de novo.')));
      return;
    }

    // ── Cartão (Stripe) ─────────────────────────────────────────────────────
    // 1) Cria o PaymentIntent do plano (Edge Function isolada) — o valor é
    //    calculado lá a partir da distância da rota.
    final created = await store.createPlanPayment(
      plan,
      distanceKm: km,
      originLabel: _originLabel,
      destLabel: _destLabel,
    );
    if (!mounted) return;
    if (created == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível iniciar o pagamento. Tenta de novo.')));
      return;
    }

    // 2) Folha de pagamento Stripe (cartão). Lança em cancelamento/erro.
    try {
      await PaymentService().processPayment(created['clientSecret'] as String);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Pagamento não concluído.')));
      return;
    }

    // 3) Ativa a subscrição — a Edge Function reverifica o PI na Stripe.
    try {
      await store.activatePlan(plan, created['paymentIntentId'] as String);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Plano ativo! Já podes usar as corridas incluídas.')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('O pagamento foi feito, mas a ativação falhou. Reabre '
              'os Planos para confirmar, ou contacta o suporte.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final sub = store.subscription;
    final pending = store.planRequestStatus == 'pendente';

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Planos'),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          if (sub != null) ...[
            _ActiveSubscription(
              sub: sub,
              dailyUsed: store.dailyUsed,
              shape: _shape[sub.plan],
            ),
            const SizedBox(height: Spacing.lg),
          ],
          if (pending) ...[
            const _PendingBanner(),
            const SizedBox(height: Spacing.lg),
          ],
          const Text('Planos disponíveis',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          const _WeekdayNotice(),
          const SizedBox(height: Spacing.sm),
          _RoutePicker(
            originController: _originController,
            destController: _destController,
            onOriginSelected: _onOriginSelected,
            onDestSelected: _onDestSelected,
            onEdited: _invalidateRoute,
            routeKm: _routeKm,
            busy: _quoting,
          ),
          const SizedBox(height: Spacing.md),
          for (final plan in _plans)
            _PlanCard(
              title: _labels[plan]!,
              quote: _quotes[plan],
              shape: _shape[plan],
              busy: _quoting,
              onAderir: pending || store.busy || _quotes[plan] == null
                  ? null
                  : () => _aderir(plan),
            ),
        ],
      ),
    );
  }
}

/// Escolha da rota habitual — origem + destino pelo MESMO seletor de moradas
/// da corrida normal. Sem rota não há orçamento, e sem orçamento não há valor
/// nem botão de pagar.
class _RoutePicker extends StatelessWidget {
  const _RoutePicker({
    required this.originController,
    required this.destController,
    required this.onOriginSelected,
    required this.onDestSelected,
    required this.onEdited,
    required this.routeKm,
    required this.busy,
  });

  final TextEditingController originController;
  final TextEditingController destController;
  final void Function(String, LatLng?) onOriginSelected;
  final void Function(String, LatLng?) onDestSelected;
  final VoidCallback onEdited;
  final double? routeKm;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('A tua rota habitual',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          const Text(
            'O preço do plano depende da distância que fazes. Escolhe de onde '
            'sais e para onde vais para vermos a conta certa.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: Spacing.md),
          AddressAutocompleteField(
            controller: originController,
            labelText: 'De onde sais',
            prefixIcon: const Icon(Icons.trip_origin, size: 18),
            onSelected: onOriginSelected,
            onChanged: (_) => onEdited(),
          ),
          const SizedBox(height: Spacing.sm),
          AddressAutocompleteField(
            controller: destController,
            labelText: 'Para onde vais',
            prefixIcon: const Icon(Icons.place_outlined, size: 18),
            onSelected: onDestSelected,
            onChanged: (_) => onEdited(),
          ),
          const SizedBox(height: Spacing.sm),
          if (busy)
            const Row(
              children: [
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: Spacing.sm),
                Text('A calcular a tua rota…',
                    style:
                        TextStyle(fontSize: 12.5, color: AppColors.textSubtle)),
              ],
            )
          else if (routeKm != null)
            Row(
              children: [
                const Icon(Icons.straighten, size: 16, color: AppColors.primary),
                const SizedBox(width: Spacing.sm),
                Text('A tua rota tem ${TvdePlanQuote.km(routeKm!)} km',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ],
            )
          else
            const Text('Escolhe a rota para veres o preço de cada plano.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSubtle)),
        ],
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.md + 2),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_top, color: AppColors.primary),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Pedido de adesão enviado. A equipa Bora vai ativar o teu plano '
              'em breve.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso fixo: os planos só cobrem Segunda a Sexta (2 corridas/dia útil).
/// Fim de semana fica de fora — nesses dias o cliente paga a tarifa normal.
class _WeekdayNotice extends StatelessWidget {
  const _WeekdayNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.md + 2),
      ),
      child: const Row(
        children: [
          Icon(Icons.event_available, color: AppColors.primary),
          SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Válido Segunda a Sexta. Aos fins de semana (sábado e domingo) as '
              'corridas não são cobertas pelo plano — paga-se a tarifa normal.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// "O meu plano" — o que está ativo, a ROTA guardada, os km incluídos e a
/// regra do excesso.
class _ActiveSubscription extends StatelessWidget {
  const _ActiveSubscription({
    required this.sub,
    required this.dailyUsed,
    this.shape,
  });
  final TvdeSubscription sub;
  final int dailyUsed;

  /// Forma do plano vinda do servidor — dá os km incluídos e o €/km quando a
  /// subscrição antiga ainda não os tem gravados.
  final TvdePlanQuote? shape;

  @override
  Widget build(BuildContext context) {
    final remainingToday =
        (sub.dailyIncluded - dailyUsed).clamp(0, sub.dailyIncluded);
    final kmIncluded = sub.kmIncluded ?? shape?.baseKm;
    final perKmCents = shape?.perKmCents;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_membership, color: Colors.white),
              const SizedBox(width: Spacing.sm),
              Text(sub.planLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Segunda a Sexta · fim de semana não incluído',
              style: TextStyle(color: Colors.white70, fontSize: 11.5)),
          const SizedBox(height: Spacing.md),
          _row('Hoje', '$remainingToday de ${sub.dailyIncluded} corridas restantes'),
          const SizedBox(height: 4),
          _row('Plano', '${sub.ridesLeft} de ${sub.ridesTotal} corridas restantes'),
          if (sub.hasRoute) ...[
            const SizedBox(height: 4),
            _row('A tua rota', '${sub.routeOriginLabel} → ${sub.routeDestLabel}'),
          ],
          if (kmIncluded != null) ...[
            const SizedBox(height: 4),
            _row('Incluído', 'até $kmIncluded km por viagem'),
          ],
          if (kmIncluded != null && perKmCents != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Acima de $kmIncluded km, cada km a mais custa '
              '${TvdePlanQuote.eur(perKmCents)} por viagem.',
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(color: Colors.white70)),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

/// Cartão de um plano. Sem rota escolhida diz o que o plano DÁ (viagens/dia)
/// e que a distância incluída depende da rota — nunca um valor. Com rota,
/// mostra a conta aberta linha a linha e acende o botão.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.quote,
    required this.shape,
    required this.busy,
    this.onAderir,
  });

  final String title;
  final TvdePlanQuote? quote;
  final TvdePlanQuote? shape;
  final bool busy;
  final VoidCallback? onAderir;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final s = shape ?? quote;

    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(
                q != null
                    ? TvdePlanQuote.eur(q.priceCents)
                    : (busy ? 'A calcular…' : 'Escolhe a rota'),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: q != null ? AppColors.primary : AppColors.textSubtle),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (s != null)
            Text(
              '${s.ridesTotal} viagens · ${s.ridesPerDay} por dia · '
              'Segunda a Sexta',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          if (q == null)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'A distância incluída em cada viagem depende da rota que '
                'escolheres — escolhe-a acima para veres a conta.',
                style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
              ),
            ),
          if (q != null) ...[
            const SizedBox(height: Spacing.sm),
            _Breakdown(lines: q.breakdown(title)),
          ],
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAderir,
              icon: const Icon(Icons.add_card, size: 18),
              label: Text(q == null
                  ? 'Escolhe a rota primeiro'
                  : 'Aderir por ${TvdePlanQuote.eur(q.priceCents)}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A conta aberta, linha a linha, antes do botão de pagar.
class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.lines});
  final List<TvdePlanQuoteLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(l.label,
                        style: TextStyle(
                            fontSize: l.strong ? 13.5 : 12.5,
                            fontWeight:
                                l.strong ? FontWeight.w700 : FontWeight.w400,
                            color: l.strong
                                ? AppColors.textPrimary
                                : AppColors.textSecondary)),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(l.value,
                      style: TextStyle(
                          fontSize: l.strong ? 14 : 12.5,
                          fontWeight:
                              l.strong ? FontWeight.w700 : FontWeight.w600,
                          color: l.strong
                              ? AppColors.primary
                              : AppColors.textPrimary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
