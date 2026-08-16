import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/maps_config.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/directions_service.dart';
import '../../../services/location_service.dart';
import '../../../services/payment_service.dart';
import '../../../services/saved_card_checkout.dart';
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/customer_note_field.dart';
import '../../../widgets/tvde/tvde_payment_selector.dart';
import 'ride_mbway_waiting_dialog.dart';
import 'tvde_plans_screen.dart';
import 'tvde_rides_history_screen.dart';
import 'tvde_ride_tracking_screen.dart';

/// Frente 4 — como o cliente paga ESTA corrida, decidido pela cobertura do
/// plano. Espelha a matemática do `tvde_finish_ride` para mostrar o valor e o
/// porquê ANTES de pedir (nunca cobrar sem o cliente ver).
enum _PayCase {
  normal, // sem plano (ou plano não cobre hoje) → tarifa cheia
  freeCovered, // coberta e ≤ base_km → grátis, não abre pagamento
  excess, // coberta mas > base_km → só o excesso (€/km acima)
  extra, // membro sem corridas hoje → €4,50 + excesso
}

/// TVDE — Ecrã para o passageiro pedir uma corrida.
/// Pickup por GPS + destino (Google Places, reuso do Favores) + preço estimado.
class TvdeRequestRideScreen extends StatefulWidget {
  const TvdeRequestRideScreen({super.key});

  @override
  State<TvdeRequestRideScreen> createState() => _TvdeRequestRideScreenState();
}

class _TvdeRequestRideScreenState extends State<TvdeRequestRideScreen> {
  final _destController = TextEditingController();
  final _pickupController = TextEditingController();
  final DirectionsService _directions = DirectionsService();
  gmaps.GoogleMapController? _mapCtrl;

  LatLng? _pickup;
  String _pickupLabel = 'A obter localização…';
  LatLng? _dest;
  String? _destLabel;

  bool _estimating = false;
  bool _locating = true;

  // B1 — distância efetiva usada na estimativa/pedido: rota real (Directions,
  // mesma chave) com fallback haversine. `_distanceSource` regista qual foi.
  double? _effectiveKm;
  // Tempo estimado da viagem (rota real) — só informativo, padrão Uber/Bolt.
  int? _etaMinutes;
  // ignore: unused_field — [Item D] guardado para futura persistência no ride.
  String _distanceSource = 'route';

  // Frente 4 — caso de pagamento decidido pela cobertura do plano (preview
  // read-only). Espelha o `tvde_finish_ride`: grátis / só-excesso / extra-membro
  // / normal, com o valor e a mensagem que o cliente vê ANTES de pedir.
  _PayCase _payCase = _PayCase.normal;
  int _payableCents = 0;
  String? _payMessage;

  // [CAMPO-02 · Feature 3] "Garantir a volta": pacote ida+volta pago adiantado.
  bool _roundtrip = false;
  int _roundtripPriceCents = 0;
  int _roundtripSavingCents = 0;
  Map<String, dynamic>? _activeCredit; // vale-volta ativo (mostra "Chamar a volta")

  // Cartão + MB Way só aparecem (na FOLHA de pagamento, depois do botão) se o
  // kill switch estiver ligado (`tvde_card_payments_enabled`). Preços do plano
  // vêm do backend (platform_settings) para a UI bater certo com o finish.
  bool _cardEnabled = false;
  int _perKmCents = 50;
  int _baseKm = 6;
  int _extraRideCents = 450;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _destController.dispose();
    _pickupController.dispose();
    _mapCtrl?.dispose();
    _directions.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final store = context.read<TvdeStore>();
    await store.loadActiveRide();
    if (!mounted) return;
    if (store.activeRide != null && store.activeRide!.isLive) {
      _openTracking();
      return;
    }
    await _detectPickup();
    // [F3] vale ativo (para "Chamar a minha volta").
    final credit = await store.activeRoundtripCredit();
    // Kill switch de card/mbway (falha fechada → só dinheiro).
    final cardEnabled =
        await store.getSettingBool('tvde_card_payments_enabled', false);
    // Preços do plano (mesmos que o backend usa no finish) para a UI mostrar o
    // valor certo do excesso/extra ANTES de pedir.
    final perKm = await store.getSettingInt('tvde_extra_per_km_cents', 50);
    final baseKm = await store.getSettingInt('tvde_base_distance_km', 6);
    final extraRide = await store.getSettingInt('tvde_extra_ride_cents', 450);
    if (mounted) {
      setState(() {
        _activeCredit = credit;
        _cardEnabled = cardEnabled;
        _perKmCents = perKm;
        _baseKm = baseKm;
        _extraRideCents = extraRide;
      });
    }
  }

  Future<void> _detectPickup() async {
    setState(() => _locating = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc != null) {
      String? addr;
      try {
        addr = await LocationService.reverseGeocode(loc, googleApiKey);
      } catch (_) {}
      setState(() {
        _pickup = loc;
        _pickupLabel = addr ?? 'Localização atual';
        _pickupController.text = _pickupLabel;
        _locating = false;
      });
      _moveCamera(loc);
      if (_dest != null) _recalcEstimate();
    } else {
      setState(() {
        _pickupLabel = 'Localização indisponível';
        _locating = false;
      });
    }
  }

  /// C2 — recolha definida por pin arrastável: ao largar, reverse geocode
  /// (mesma chave/serviço do delivery) e reestima.
  Future<void> _onPickupDragEnd(gmaps.LatLng pos) async {
    final loc = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _pickup = loc;
      _pickupLabel = 'A obter morada…';
      _pickupController.text = _pickupLabel;
    });
    String? addr;
    try {
      addr = await LocationService.reverseGeocode(loc, googleApiKey);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _pickupLabel = addr ?? 'Local no mapa';
      _pickupController.text = _pickupLabel;
    });
    if (_dest != null) _recalcEstimate();
  }

  /// C2 — recolha por autocomplete (Google Places, reuso do destino).
  void _onPickupSelected(String address, LatLng? coords) {
    if (coords == null) return;
    setState(() {
      _pickup = coords;
      _pickupLabel = address;
    });
    _moveCamera(coords);
    if (_dest != null) _recalcEstimate();
  }

  void _moveCamera(LatLng target) {
    _mapCtrl?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(target.toGMaps(), 15));
  }

  /// Fallback haversine (linha reta) — usado só quando a rota real falha.
  double? get _haversineKm {
    if (_pickup == null || _dest == null) return null;
    final km = const Distance().as(LengthUnit.Kilometer, _pickup!, _dest!);
    return double.parse(km.toStringAsFixed(2));
  }

  /// B1 — estimativa pela DISTÂNCIA DE ROTA REAL (Directions, mesma chave do
  /// estafeta). Se a rota falhar (offline/erro API) cai para haversine e
  /// regista `_distanceSource='haversine'` (persistido no ride ao finalizar).
  Future<void> _recalcEstimate() async {
    final fallback = _haversineKm;
    if (_pickup == null || _dest == null || fallback == null) {
      setState(() {
        _effectiveKm = null;
        _etaMinutes = null;
        _payCase = _PayCase.normal;
        _payableCents = 0;
        _payMessage = null;
        _roundtripPriceCents = 0;
        _roundtripSavingCents = 0;
      });
      return;
    }
    setState(() => _estimating = true);
    double km = fallback;
    String source = 'haversine';
    int? etaMin;
    // [Item D] a rota real é a FONTE do preço. O Directions falha às vezes de
    // forma transitória (rede/limite de QPS) e, ao cair para haversine, o km e o
    // preço ficam SUBESTIMADOS (linha reta << rota real). Uma 2ª tentativa
    // recupera a rota real na esmagadora maioria desses casos.
    for (var attempt = 0; attempt < 2 && source == 'haversine'; attempt++) {
      try {
        final route = await _directions.fetchRoute(
          origin: _pickup!,
          destination: _dest!,
        );
        if (route != null && route.distanceKm > 0) {
          km = double.parse(route.distanceKm.toStringAsFixed(2));
          source = 'route';
          final mins = route.durationMinutes.round();
          if (mins > 0) etaMin = mins;
        }
      } catch (_) {
        // mantém haversine; volta a tentar se ainda houver tentativa
      }
    }
    final cents = await context.read<TvdeStore>().estimateFareCents(km);
    // [Item B] cobertura pelo plano (read-only, NÃO consome — só o finish consome).
    final cov = await context.read<TvdeStore>().previewCoverage();
    if (!mounted) return;
    // Planos só cobrem Segunda a Sexta — a RPC tvde_preview_coverage não checa
    // o dia da semana (só o consumo no finish o faz), então replicamos aqui
    // para não mostrar "Incluída no plano" ao fim de semana por engano.
    final isWeekend =
        DateTime.now().weekday == DateTime.saturday || DateTime.now().weekday == DateTime.sunday;
    final covered = !isWeekend && cov['covered'] == true;
    final used = (cov['daily_used'] as num?)?.toInt();
    final incl = (cov['daily_included'] as num?)?.toInt();
    final reason = cov['reason'] as String?;
    // Membro = tem plano ativo (mesmo que hoje não cubra: fim de semana ou já
    // usou as de hoje). O finish cobra €4,50 + excesso a membros não-cobertos.
    final isMember = covered || reason == 'daily_limit';
    final excessKm = km > _baseKm ? (km - _baseKm).ceil() : 0;
    final excessCents = excessKm * _perKmCents;

    _PayCase pc;
    int payable;
    String? message;
    if (covered) {
      if (excessKm == 0) {
        pc = _PayCase.freeCovered;
        payable = 0;
        message = (used != null && incl != null)
            ? 'Incluída no teu plano · ${used + 1}.ª de $incl hoje'
            : 'Incluída no teu plano';
      } else {
        pc = _PayCase.excess;
        payable = excessCents;
        message = 'Corrida do plano — só pagas o excesso: '
            '$excessKm km acima de $_baseKm = €${(payable / 100).toStringAsFixed(2)}';
      }
    } else if (isMember) {
      pc = _PayCase.extra;
      payable = _extraRideCents + excessCents;
      message = 'Já usaste as corridas de hoje — esta fica '
          '€${(payable / 100).toStringAsFixed(2)} (preço de membro).';
    } else {
      pc = _PayCase.normal;
      payable = cents;
      message = null;
    }
    setState(() {
      _effectiveKm = km;
      _etaMinutes = etaMin;
      _distanceSource = source;
      _payCase = pc;
      _payableCents = payable;
      _payMessage = message;
      _estimating = false;
    });
    _fetchRoundtripQuote(km);
  }

  Future<void> _fetchRoundtripQuote(double km) async {
    final store = context.read<TvdeStore>();
    final quote = await store.quoteRoundtrip(km);
    if (!mounted || quote == null) return;
    setState(() {
      _roundtripPriceCents = (quote['price_cents'] as num?)?.toInt() ?? 0;
      _roundtripSavingCents = (quote['saving_cents'] as num?)?.toInt() ?? 0;
    });
  }

  /// Frente 3 — carregar em "Solicitar corrida" abre a FOLHA de pagamento
  /// (como no checkout do delivery: método só APÓS o botão). Grátis (coberta
  /// ≤ base_km) cria já, sem folha.
  Future<void> _onRequestPressed() async {
    if (_payCase == _PayCase.freeCovered) {
      await _solicitar('cash');
      return;
    }
    // Online (cartão/MB Way) em QUALQUER corrida com valor > 0. A Edge Function
    // cobra o valor do plano (`tvde_ride_charge_cents`), não a tarifa cheia — por
    // isso excesso/extra também pagam por cartão/MB Way sem sobre-cobrar.
    final allowOnline = _cardEnabled && _payableCents > 0;
    final result = await showModalBottomSheet<_TvdePayResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      // Protege o topo (notch). O FUNDO não vem daqui — `useSafeArea` aplica
      // `SafeArea(bottom: false)`; quem trata da barra do sistema é o
      // `padding.bottom` somado dentro de `_TvdePaymentSheet`.
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TvdePaymentSheet(
        amountCents: _payableCents,
        message: _payMessage,
        allowOnline: allowOnline,
      ),
    );
    if (result == null || !mounted) return;
    await _solicitar(result.method,
        note: result.note,
        tokensUsed: result.tokensUsed,
        mbwayPhone: result.mbwayPhone);
  }

  Future<void> _solicitar(String method,
      {String? note, int tokensUsed = 0, String? mbwayPhone}) async {
    final store = context.read<TvdeStore>();
    final km = _effectiveKm;
    if (_pickup == null || _dest == null || km == null) return;
    // Guardada assim que a corrida nasce, para a podermos cancelar se o
    // pagamento falhar — inclusive quando o `confirmCard` lança.
    TvdeRide? criada;
    try {
      TvdeRide? ride;
      // Carteira Unica (2026-07-21): so o cartao usa cartao guardado +
      // biometria. MB Way confirma-se na app do banco e dinheiro nao cobra.
      String? savedPmId;
      if (method == 'card') {
        final auth = await SavedCardCheckout.instance.authorize();
        if (!mounted) return;
        if (auth.cancelled) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Pagamento cancelado. A corrida não foi pedida.')));
          return;
        }
        savedPmId = auth.savedPmId;
      }
      if (method == 'card' || method == 'mbway') {
        // A Edge Function cria a corrida e cobra. Com o backend novo ela nasce
        // em 'aguarda_pagamento' e NÃO despacha até o pagamento confirmar; com
        // o backend antigo nasce 'solicitada' e já despacha. Os dois casos são
        // suportados — ver `_aguardarPagamentoOnline`.
        ride = await store.requestRidePaid(
          originLat: _pickup!.latitude,
          originLng: _pickup!.longitude,
          originLabel: _pickupLabel,
          destLat: _dest!.latitude,
          destLng: _dest!.longitude,
          destLabel: _destLabel,
          distanceKm: km,
          method: method,
          mbwayPhone: mbwayPhone,
          tokensUsed: tokensUsed,
          savedPmId: savedPmId,
          onRideCreated: (r) => criada = r,
          confirmCard: (clientSecret) =>
              PaymentService().processPayment(clientSecret),
        );
        if (!mounted) return;
        // Corrida estacionada → só segue para o tracking depois de o SERVIDOR
        // confirmar o pagamento. Nunca mostrar "à procura de motorista" antes.
        if (ride != null && ride.isAwaitingPayment) {
          final libertada = await _aguardarPagamentoOnline(store, ride, method);
          if (!mounted || !libertada) return;
        }
      } else {
        ride = await store.requestRide(
          originLat: _pickup!.latitude,
          originLng: _pickup!.longitude,
          originLabel: _pickupLabel,
          destLat: _dest!.latitude,
          destLng: _dest!.longitude,
          destLabel: _destLabel,
          distanceKm: km,
          paymentMethod: 'cash',
          tokensUsed: tokensUsed,
        );
      }
      // Nota do cliente para o motorista (não-financeiro): grava após a corrida
      // criada. Falha silenciosa — nunca bloqueia o pedido por causa da nota.
      final trimmed = note?.trim() ?? '';
      if (ride != null && trimmed.isNotEmpty) {
        await store.setRideNote(ride.id, trimmed);
      }
      if (!mounted) return;
      _openTracking();
    } catch (e) {
      // O cliente recusou/cancelou o cartão (ou a cobrança rebentou) com a
      // corrida já criada e estacionada → cancelá-la, senão fica pendurada até
      // o cron a apanhar. Nada foi cobrado, por isso não se pede refund.
      final orfa = criada;
      if (orfa != null && orfa.isAwaitingPayment) {
        try {
          await store.cancelRide(orfa.id,
              reason: 'payment_failed', skipRefund: true);
        } catch (_) {/* o cron limpa (payment_timeout) */}
      }
      if (!mounted) return;
      final s = e.toString();
      final msg = s.contains('ride_in_progress')
          ? 'Já tens uma corrida em curso.'
          : s.contains('card_payments_not_enabled')
              ? 'Pagamento por cartão ainda não está disponível.'
              : s.contains('cancel') || s.contains('Cancel')
                  ? 'Pagamento não concluído. A corrida não foi pedida.'
                  : 'Não foi possível pedir a corrida.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Espera que o SERVIDOR liberte a corrida (`aguarda_pagamento` →
  /// `solicitada`). Devolve true se pode seguir para o tracking.
  ///
  /// Cartão: já foi confirmado no cliente, falta o servidor revalidar o
  /// PaymentIntent — tenta 3 vezes. MB Way: confirma-se na app do banco, por
  /// isso faz poll até 120 s com o diálogo de espera.
  ///
  /// Regra de segurança: só cancela quando o servidor **responde** que não está
  /// pago. Se não se conseguir falar com o servidor, NÃO cancela — seguir para
  /// o tracking (que mostra "a aguardar pagamento") é melhor do que cancelar às
  /// cegas uma corrida que pode ter sido cobrada. O cron limpa se ficar presa.
  Future<bool> _aguardarPagamentoOnline(
      TvdeStore store, TvdeRide ride, String method) async {
    Future<void> cancelar() async {
      try {
        await store.cancelRide(ride.id,
            reason: 'payment_failed', skipRefund: true);
      } catch (_) {/* o cron limpa (payment_timeout) */}
    }

    if (method == 'mbway') {
      final paid = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TvdeRideMbwayWaitingDialog.forRide(
          rideId: ride.id,
          amountEur: _payableCents / 100,
        ),
      );
      if (paid == true) return true;
      await cancelar();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não recebemos a confirmação MBWay. A corrida foi '
              'cancelada e não foste cobrado.')));
      return false;
    }

    // Cartão.
    bool respondeu = false;
    for (var i = 0; i < 3; i++) {
      final res = await store.confirmRidePayment(ride.id);
      if (!mounted) return false;
      if (res != null) {
        respondeu = true;
        if (res['succeeded'] == true) return true;
      }
      if (i < 2) await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return false;
    }

    if (!respondeu) {
      // Nunca se conseguiu perguntar. Não cancelar às cegas.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não conseguimos confirmar o pagamento agora. Vê o '
              'estado no ecrã da corrida.')));
      return true;
    }
    await cancelar();
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pagamento não concluído. A corrida não foi pedida.')));
    return false;
  }

  /// [F3 · Fase B] Pedido "garantir a volta": o preço dinâmico cobre as DUAS
  /// pernas (ida+volta com desconto). A folha é a mesma do pedido normal, por
  /// isso tem **Dinheiro** além de cartão/MB Way. A volta é disparada depois.
  ///
  /// Em qualquer dos caminhos a ida TEM de acabar ligada ao vale
  /// (`tvde_rides.roundtrip_credit_id`): é essa ligação que faz o
  /// `tvde_finish_ride` tratá-la como prepaga. Uma ida do pacote sem vale
  /// cobraria a tarifa por cima dos €8 — o "€13" que não pode acontecer.
  Future<void> _solicitarRoundtrip() async {
    final km = _effectiveKm;
    if (_pickup == null || _dest == null || km == null) return;

    final result = await showModalBottomSheet<_TvdePayResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      // Protege o topo (notch). O FUNDO não vem daqui — `useSafeArea` aplica
      // `SafeArea(bottom: false)`; quem trata da barra do sistema é o
      // `padding.bottom` somado dentro de `_TvdePaymentSheet`.
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TvdePaymentSheet(
        amountCents: _roundtripPriceCents,
        message: _roundtripSavingCents > 0
            ? 'Ida + volta com desconto. Poupas '
                '€${(_roundtripSavingCents / 100).toStringAsFixed(2)} '
                'face a duas corridas separadas.'
            : 'Preço total da ida + volta — chamas a volta quando quiseres.',
        allowOnline: _cardEnabled,
        // 2026-08-13 — DESLIGADO de propósito, e só metade da razão mudou.
        //
        // O caminho em DINHEIRO já honra tokens: a
        // `tvde_create_roundtrip_credit_cash(uuid, integer)` foi aplicada e
        // abate o desconto ao `paid_cents`.
        //
        // O caminho ONLINE **não**: quem o serve é a Edge Fn
        // `tvde-plan-payment`, que está bloqueada para deploy (chama
        // `tvde_create_roundtrip_credit` com 6 argumentos e em produção tem 4).
        // A versão que está no ar ignora `tokens_used` — o cliente escolheria
        // tokens, veria um preço mais baixo na folha de pagamento, e seria
        // cobrado o valor cheio. Mostrar o toggle seria prometer um desconto
        // que não acontece.
        //
        // A folha é a mesma para dinheiro e online (o método só se escolhe lá
        // dentro), por isso não dá para ligar só a metade que funciona.
        // Passar a `true` assim que a `20260804000000_PROPOSTA_tvde_roundtrip_tokens.sql`
        // estiver aplicada e a `tvde-plan-payment` deployada.
        allowTokens: false,
      ),
    );
    if (result == null || !mounted) return;

    if (result.method == 'cash') {
      await _solicitarRoundtripCash(km,
          note: result.note, tokensUsed: result.tokensUsed);
    } else {
      await _solicitarRoundtripOnline(km,
          isMbway: result.method == 'mbway',
          mbwayPhone: result.mbwayPhone,
          note: result.note,
          tokensUsed: result.tokensUsed);
    }
  }

  /// [Fase B] Pacote em **DINHEIRO** — zero Stripe. A ida nasce cash e despacha
  /// na hora (o motorista recolhe o valor em mão por conta da Bora); logo a
  /// seguir a RPC cria o vale e liga-lhe a ida.
  Future<void> _solicitarRoundtripCash(double km,
      {String? note, int tokensUsed = 0}) async {
    final store = context.read<TvdeStore>();
    final messenger = ScaffoldMessenger.of(context);

    TvdeRide? ida;
    try {
      ida = await store.requestRide(
        originLat: _pickup!.latitude,
        originLng: _pickup!.longitude,
        originLabel: _pickupLabel,
        destLat: _dest!.latitude,
        destLng: _dest!.longitude,
        destLabel: _destLabel,
        distanceKm: km,
        paymentMethod: 'cash',
      );
    } catch (e) {
      debugPrint('_solicitarRoundtripCash requestRide error => $e');
    }
    if (!mounted) return;
    if (ida == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível pedir a corrida.')));
      return;
    }

    // Ligar ao vale. Idempotente por ida, por isso o retry é seguro.
    Map<String, dynamic>? vale;
    for (var i = 0; i < 3 && vale == null; i++) {
      vale = await store.createRoundtripCreditCash(ida.id,
          tokensUsed: tokensUsed);
      if (!mounted) return;
      if (vale == null && i < 2) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
      }
    }

    if (vale == null) {
      // A ida ficou por ligar: seria uma corrida cash normal a cobrar a tarifa
      // ao cliente por cima dos €8. Cancelar é a única saída honesta — nada foi
      // cobrado (é dinheiro), por isso não há refund nenhum a pedir.
      try {
        await store.cancelRide(ida.id,
            reason: 'roundtrip_credit_failed', skipRefund: true);
      } catch (_) {/* o cron limpa; o admin vê a ida sem vale */}
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível garantir a volta. A corrida não foi '
              'pedida — tenta outra vez.')));
      return;
    }

    final trimmed = note?.trim() ?? '';
    if (trimmed.isNotEmpty) await store.setRideNote(ida.id, trimmed);
    if (!mounted) return;
    _openTracking();
  }

  /// [Fase B] Pacote em **CARTÃO / MB Way** — o contrato que já existia, intacto:
  /// PaymentIntent do valor dinâmico → cria a ida → `activate_roundtrip` liga-a.
  Future<void> _solicitarRoundtripOnline(double km,
      {required bool isMbway,
      String? mbwayPhone,
      String? note,
      int tokensUsed = 0}) async {
    final store = context.read<TvdeStore>();
    final messenger = ScaffoldMessenger.of(context);
    final priceEur = _roundtripPriceCents / 100;

    // 1) PaymentIntent do preço dinâmico (server-side). MB Way confirma-se na
    //    app do banco; cartão confirma-se já a seguir.
    final created = isMbway
        ? await store.createRoundtripPaymentMbway(mbwayPhone!, km,
            tokensUsed: tokensUsed)
        : await store.createRoundtripPayment(km, tokensUsed: tokensUsed);
    if (!mounted) return;
    final paymentIntentId = created?['paymentIntentId'] as String?;
    if (created == null || paymentIntentId == null) {
      messenger.showSnackBar(SnackBar(
          content: Text(isMbway
              ? 'Não foi possível iniciar o MBWay. Confirma o número e tenta '
                  'de novo.'
              : 'Não foi possível iniciar o pagamento da volta.')));
      return;
    }
    if (!isMbway) {
      if (created['clientSecret'] == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Não foi possível iniciar o pagamento da volta.')));
        return;
      }
      try {
        await PaymentService()
            .processPayment(created['clientSecret'] as String);
      } catch (_) {
        if (!mounted) return;
        messenger.showSnackBar(
            const SnackBar(content: Text('Pagamento cancelado.')));
        return;
      }
    }

    // 2) Corrida de IDA — tem de existir ANTES do `activate_roundtrip`, porque é
    //    ela que fica ligada ao vale (`tvde_rides.roundtrip_credit_id`). Sem essa
    //    ligação o `tvde_finish_ride` não a trata como pré-paga e o cliente
    //    pagaria a ida outra vez.
    //    BUG 6 (2026-08-13) — o `paymentMethod` ficava no DEFAULT ('cash'), e
    //    isso não era cosmético: `fn_tvde_dispatch_on_request` despacha na hora
    //    toda a corrida que nasce em dinheiro. Resultado provado na corrida
    //    81d1bd09 (20:10:43): a ida nasceu 'cash', o motorista foi chamado no
    //    MESMO milissegundo, aceitou 15 s depois e pôs-se a caminho — tudo com
    //    o cliente ainda parado no ecrã do MB Way. Aos 20:12 caiu em
    //    'payment_failed'. O método real TEM de ir aqui.
    //    O receio antigo ("marcá-la 'card' faz o backend procurar um PI dela
    //    que não existe") continua válido e continua tratado: o PI dos €8 vive
    //    no VALE, esta corrida não tem `payment_intent_id`. Quem a liberta
    //    passa a ser o `activate_roundtrip` → `tvde_create_roundtrip_credit`,
    //    que marca `payment_status='succeeded'` ao ligar o vale e deixa o
    //    `tr_tvde_dispatch_on_paid` despachar. Um só mecanismo, o mesmo da
    //    corrida normal paga online.
    TvdeRide? ida;
    try {
      ida = await store.requestRide(
        originLat: _pickup!.latitude,
        originLng: _pickup!.longitude,
        originLabel: _pickupLabel,
        destLat: _dest!.latitude,
        destLng: _dest!.longitude,
        destLabel: _destLabel,
        distanceKm: km,
        paymentMethod: isMbway ? 'mbway' : 'card',
      );
    } catch (_) {}
    if (!mounted) return;
    if (ida == null) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Pago, mas falhou criar a corrida. Fala com o suporte.')));
      return;
    }

    // 3) Liga a ida ao vale. O `activate_roundtrip` só passa com o PaymentIntent
    //    em 'succeeded' — no MB Way é isso que o dialog espera (poll), no cartão
    //    já está confirmado.
    if (isMbway) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TvdeRideMbwayWaitingDialog.forRoundtrip(
          outboundRideId: ida!.id,
          paymentIntentId: paymentIntentId,
          amountEur: priceEur,
        ),
      );
      if (!mounted) return;
      if (ok != true) {
        // [Fase B] Sem confirmação o vale não é criado e a ida ficaria solta, a
        // cobrar a tarifa ao cliente. Antes seguia "como corrida normal" — agora
        // cancela-se. Nada foi cobrado, por isso não se pede refund.
        try {
          await store.cancelRide(ida.id,
              reason: 'payment_failed', skipRefund: true);
        } catch (_) {/* o cron limpa (payment_timeout) */}
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
            content: Text('Não recebemos a confirmação MBWay. A corrida não '
                'foi pedida e não foste cobrado.')));
        return;
      }
    } else {
      await store.activateRoundtrip(ida.id, paymentIntentId);
    }

    final trimmed = note?.trim() ?? '';
    if (trimmed.isNotEmpty) await store.setRideNote(ida.id, trimmed);
    if (!mounted) return;
    _openTracking();
  }

  /// [F3] Dispara a corrida de VOLTA usando o vale ativo (pede o destino).
  Future<void> _callReturn() async {
    final credit = _activeCredit;
    // Sem vale não há volta. A falta de GPS já NÃO trava — a folha deixa
    // escrever a origem à mão (antes o botão não fazia nada, em silêncio).
    if (credit == null) return;
    final store = context.read<TvdeStore>();

    // Relê a localização AGORA: a volta parte de onde o cliente está neste
    // momento, não de onde estava quando pediu a ida.
    var origin = _pickup;
    var originLabel = _pickupLabel;
    try {
      final now = await LocationService.getCurrentLocation();
      if (now != null) {
        origin = now;
        final addr = await LocationService.reverseGeocode(now, googleApiKey);
        if (addr != null && addr.isNotEmpty) originLabel = addr;
      }
    } catch (_) {/* fica o da ida; o cliente pode editar na folha */}
    if (!mounted) return;

    final picked = await showModalBottomSheet<_ReturnDest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      // [Ronda 2] Fechar a folha só pelo "X". Antes, tocar fora para esconder o
      // teclado fazia barrier-tap → `pop(null)` → o ecrã por baixo voltava ao
      // botão "Solicitar corrida" e o cliente pedia uma corrida normal de €5 a
      // pensar que estava a chamar a volta que já tinha pago.
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ReturnSheet(
        initialOriginLabel: originLabel,
        initialOrigin: origin,
      ),
    );
    if (!mounted) return;
    if (picked == null) {
      // Desistiu de propósito (X): o vale não se perde — dizer-lho, para não
      // ficar com a ideia de que tem de pedir (e pagar) outra corrida.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A tua volta continua disponível — podes chamá-la '
              'quando quiseres.')));
      return;
    }

    final from = LatLng(picked.originLat, picked.originLng);
    final to = LatLng(picked.lat, picked.lng);
    // distância por rota real (fallback haversine) da origem escolhida ao destino.
    double km = const Distance().as(LengthUnit.Kilometer, from, to);
    try {
      final route = await _directions.fetchRoute(origin: from, destination: to);
      if (route != null && route.distanceKm > 0) km = route.distanceKm;
    } catch (_) {}
    if (!mounted) return;
    try {
      await store.requestReturnRide(
        creditId: credit['id'] as String,
        originLat: picked.originLat,
        originLng: picked.originLng,
        originLabel: picked.originLabel,
        destLat: picked.lat,
        destLng: picked.lng,
        destLabel: picked.label,
        distanceKm: double.parse(km.toStringAsFixed(2)),
      );
      if (!mounted) return;
      _openTracking();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível chamar a volta.')));
    }
  }

  void _openTracking() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TvdeRideTrackingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final canRequest = _pickup != null &&
        _dest != null &&
        _effectiveKm != null &&
        !store.busy &&
        !_locating &&
        !_estimating;

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Bora Motorista',
        actions: [
          IconButton(
            icon: const Icon(Icons.card_membership),
            tooltip: 'Planos',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TvdePlansScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Histórico',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TvdeRidesHistoryScreen())),
          ),
        ],
      ),
      body: SingleChildScrollView(
        // Parte 9 — respiro no fundo (safe-area + extra) para o card "Planos Bora
        // Motorista" (último item) não ficar cortado no fundo do ecrã.
        padding: EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.lg,
          Spacing.lg,
          Spacing.lg + Spacing.xl + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [F3] vale-volta ativo → "Chamar a minha volta".
            if (_activeCredit != null) ...[
              _ReturnCreditCard(
                credit: _activeCredit!,
                busy: store.busy,
                onCall: _callReturn,
              ),
              const SizedBox(height: Spacing.md),
            ],
            // C1 — mapa na tela inicial com o pin da recolha (arrastável).
            _PickupMap(
              pickup: _pickup,
              dest: _dest,
              onMapCreated: (c) => _mapCtrl = c,
              onPickupDragEnd: _onPickupDragEnd,
              onRecenter: () {
                if (_pickup != null) _moveCamera(_pickup!);
              },
            ),
            const SizedBox(height: Spacing.md),
            // C2 — recolha editável (autocomplete + botão "usar localização").
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AddressAutocompleteField(
                    controller: _pickupController,
                    labelText: 'Ponto de recolha',
                    prefixIcon:
                        const Icon(Icons.my_location, color: AppColors.primary),
                    onSelected: _onPickupSelected,
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                _locating
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton.filledTonal(
                        tooltip: 'Usar a minha localização',
                        icon: const Icon(Icons.gps_fixed),
                        onPressed: _detectPickup,
                      ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            AddressAutocompleteField(
              controller: _destController,
              labelText: 'Para onde vais?',
              prefixIcon: const Icon(Icons.flag_outlined),
              onSelected: (address, coords) {
                if (coords == null) return;
                setState(() {
                  _dest = coords;
                  _destLabel = address;
                });
                _moveCamera(coords);
                _recalcEstimate();
              },
              onChanged: (_) {
                if (_dest != null) {
                  setState(() {
                    _dest = null;
                    _effectiveKm = null;
                    _etaMinutes = null;
                    _payableCents = 0;
                    _roundtripPriceCents = 0;
                    _roundtripSavingCents = 0;
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            _EstimateCard(
              payableCents: _payableCents,
              km: _effectiveKm,
              etaMinutes: _etaMinutes,
              loading: _estimating,
              isFree: _payCase == _PayCase.freeCovered,
              message: _payMessage,
            ),
            const SizedBox(height: Spacing.md),
            // [F3] "Garantir a volta" — pacote ida+volta pago adiantado.
            _RoundtripToggle(
              value: _roundtrip,
              priceCents: _roundtripPriceCents,
              savingCents: _roundtripSavingCents,
              onChanged: (v) => setState(() => _roundtrip = v),
            ),
            // Parte 9 — prazo do vale bem claro (validade = 12h, aplicada em prod).
            if (_roundtrip)
              const Padding(
                padding: EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  'Válida por 12 horas após a compra — depois disso perdes a volta.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
                ),
              ),
            const SizedBox(height: Spacing.xl),
            BoraAccentButton(
              label: _roundtrip
                  ? _roundtripPriceCents > 0
                      ? 'Garantir ida e volta · €${(_roundtripPriceCents / 100).toStringAsFixed(2)}'
                      : 'Garantir ida e volta'
                  : 'Solicitar corrida',
              icon: _roundtrip ? Icons.sync_alt : Icons.local_taxi,
              loading: store.busy,
              onPressed: canRequest
                  ? (_roundtrip ? _solicitarRoundtrip : _onRequestPressed)
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              _payCase == _PayCase.freeCovered
                  ? 'Incluída no teu plano — não pagas nada ao motorista.'
                  : 'Escolhes como pagar depois de solicitares.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
            const SizedBox(height: Spacing.lg),
            // C3 — planos visíveis na tela principal (card discreto, clicável).
            _PlansTeaser(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TvdePlansScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

/// C1/C2 — mapa da tela inicial com o pin da recolha (arrastável). Reusa o
/// stack de mapa do delivery (google_maps_flutter). Destino aparece como pin
/// laranja quando escolhido.
class _PickupMap extends StatelessWidget {
  const _PickupMap({
    required this.pickup,
    required this.dest,
    required this.onMapCreated,
    required this.onPickupDragEnd,
    required this.onRecenter,
  });

  final LatLng? pickup;
  final LatLng? dest;
  final void Function(gmaps.GoogleMapController) onMapCreated;
  final void Function(gmaps.LatLng) onPickupDragEnd;
  final VoidCallback onRecenter;

  static const _guarda = LatLng(40.5373, -7.2657);

  @override
  Widget build(BuildContext context) {
    final center = pickup ?? _guarda;
    final markers = <gmaps.Marker>{
      gmaps.Marker(
        markerId: const gmaps.MarkerId('pickup'),
        position: center.toGMaps(),
        draggable: true,
        onDragEnd: onPickupDragEnd,
        icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueGreen),
        infoWindow: const gmaps.InfoWindow(title: 'Arrasta para ajustar a recolha'),
      ),
      if (dest != null)
        gmaps.Marker(
          markerId: const gmaps.MarkerId('dest'),
          position: dest!.toGMaps(),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
              gmaps.BitmapDescriptor.hueOrange),
          infoWindow: const gmaps.InfoWindow(title: 'Destino'),
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.lg),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            gmaps.GoogleMap(
              initialCameraPosition:
                  gmaps.CameraPosition(target: center.toGMaps(), zoom: 15),
              markers: markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: onMapCreated,
            ),
            Positioned(
              right: Spacing.sm,
              bottom: Spacing.sm,
              child: FloatingActionButton.small(
                heroTag: 'tvde_pickup_recenter',
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                onPressed: onRecenter,
                child: const Icon(Icons.my_location),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// C3 — card discreto dos planos na tela principal (clicável).
class _PlansTeaser extends StatelessWidget {
  const _PlansTeaser({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md + 2),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md + 2),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Row(
          children: [
            Icon(Icons.card_membership, color: AppColors.primary),
            SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Planos Bora Motorista',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text('Corridas incluídas por dia a partir de €3. Vê e adere.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSubtle)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.payableCents,
    required this.km,
    required this.etaMinutes,
    required this.loading,
    required this.isFree,
    this.message,
  });
  final int payableCents;
  final double? km;
  final int? etaMinutes; // tempo estimado (rota real) — padrão Uber/Bolt
  final bool loading;
  final bool isFree; // coberta ≤ base_km → cliente paga €0
  final String? message; // linha do porquê (plano/excesso/extra)

  @override
  Widget build(BuildContext context) {
    final hasKm = km != null;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.white),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isFree ? 'Plano' : 'Valor estimado',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                if (loading)
                  const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                else
                  Text(
                    !hasKm
                        ? 'Escolhe o destino'
                        : '${isFree ? 'Grátis' : '€${(payableCents / 100).toStringAsFixed(2)}'}'
                            '  ·  ${km!.toStringAsFixed(1)} km'
                            '${etaMinutes != null ? '  ·  ~$etaMinutes min' : ''}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                if (message != null && hasKm) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(isFree ? Icons.check_circle : Icons.info_outline,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(message!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Frente 3 — folha de pagamento (aparece SÓ depois de "Solicitar corrida",
/// como no checkout do delivery): mostra o valor final + os métodos e confirma.
/// Dinheiro sempre; Cartão/MB Way só se [allowOnline] (switch on + tarifa normal).
/// Resultado da folha de pagamento TVDE: método escolhido + nota opcional +
/// tokens usados + número MB Way (só preenchido quando o método é 'mbway').
class _TvdePayResult {
  const _TvdePayResult(this.method, this.note, this.tokensUsed,
      {this.mbwayPhone});
  final String method;
  final String? note;
  final int tokensUsed;
  final String? mbwayPhone;
}

class _TvdePaymentSheet extends StatefulWidget {
  const _TvdePaymentSheet({
    required this.amountCents,
    required this.message,
    required this.allowOnline,
    this.allowTokens = true,
  });
  final int amountCents;
  final String? message;
  final bool allowOnline;

  /// [Fase B] Desconto em Bora Tokens. **false no pacote ida-e-volta**: o preço
  /// é server-side (RPC `tvde_quote_roundtrip`) e as RPCs do vale não recebem
  /// tokens — deixar o toggle aparecer prometeria um desconto que não acontece.
  final bool allowTokens;

  @override
  State<_TvdePaymentSheet> createState() => _TvdePaymentSheetState();
}

class _TvdePaymentSheetState extends State<_TvdePaymentSheet> {
  String _method = 'cash';
  final TextEditingController _noteController = TextEditingController();

  // MB Way — número do cliente. Sem isto a Edge Function recebe `phone` vazio e
  // a Stripe recusa. Pré-preenchido do perfil, tal como no picker das Reservas.
  final TextEditingController _phoneController = TextEditingController();
  String? _phoneError;

  // ── Token discount state ───────────────────────────────────────────────────
  int _availableTokens = 0;
  bool _useTokens = false;
  bool _tokensLoaded = false;
  int _tokenMaxPct = 50;

  @override
  void initState() {
    super.initState();
    if (widget.allowTokens) _loadTokens();
    final profilePhone = context.read<AuthStore>().currentClient?.phone;
    if (profilePhone != null && profilePhone.isNotEmpty) {
      final digits = profilePhone.replaceAll(RegExp(r'\D'), '');
      _phoneController.text =
          digits.startsWith('351') ? digits.substring(3) : digits;
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Carrega saldo de tokens e configuração de percentagem máxima.
  Future<void> _loadTokens() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _tokensLoaded = true);
      return;
    }
    try {
      final response = await Supabase.instance.client.rpc(
        'get_user_tokens',
        params: {'p_user_id': userId},
      );
      int pct = _tokenMaxPct;
      try {
        final pctRes = await Supabase.instance.client.rpc(
          'get_setting',
          params: {'p_key': 'token_payment_max_pct'},
        );
        if (pctRes is num) {
          pct = pctRes.toInt();
        } else if (pctRes is String) {
          pct = int.tryParse(pctRes) ?? pct;
        }
      } catch (e) {
        debugPrint('[TvdePaymentSheet] token_payment_max_pct fallback: $e');
      }
      if (mounted) {
        setState(() {
          _availableTokens = (response as num?)?.toInt() ?? 0;
          _tokenMaxPct = pct;
          _tokensLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[TvdePaymentSheet] _loadTokens error: $e');
      if (mounted) setState(() => _tokensLoaded = true);
    }
  }

  /// Calcula quantos tokens podem ser usados (limitado a 50% do total).
  int _calculateTokensToUse() {
    const double tokenValueEur = 0.005; // TOKEN_VALUE_EUR
    final double maxDiscountEur =
        (widget.amountCents / 100) * (_tokenMaxPct / 100.0);
    final int tokensToUse = (maxDiscountEur / tokenValueEur).toInt();
    return tokensToUse.clamp(0, _availableTokens);
  }

  /// Widget do toggle de tokens (estilo delivery, com cores amber).
  Widget _buildTokenToggle() {
    const double tokenValueEur = 0.005;
    final tokensToUse = _calculateTokensToUse();
    final tokenDiscount = tokensToUse * tokenValueEur;
    final maxDiscountEur =
        (widget.amountCents / 100) * (_tokenMaxPct / 100.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: SwitchListTile.adaptive(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        secondary:
            const Icon(Icons.monetization_on, color: Colors.amber),
        title: const Text(
          'Usar Bora Tokens',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          '$tokensToUse tokens → -€${tokenDiscount.toStringAsFixed(2)}\n'
          'Máximo $_tokenMaxPct% em Bora Tokens '
          '(€${maxDiscountEur.toStringAsFixed(2)})',
          style: TextStyle(
            fontSize: 12,
            color: Colors.amber.shade800,
          ),
        ),
        value: _useTokens,
        onChanged: (v) => setState(() => _useTokens = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom; // teclado
    final safeBottom = media.padding.bottom; // barra de navegação do sistema
    final eur = '€${(widget.amountCents / 100).toStringAsFixed(2)}';
    // Rolável: com MB Way escolhido aparece o campo do número e o teclado, e
    // sem scroll o conteúdo estoura em ecrãs baixos (o botão fica inalcançável).
    //
    // [Ronda 2] Porque é que o `useSafeArea: true` da folha NÃO chegava: no
    // Flutter esse flag aplica `SafeArea(bottom: false)` — protege o topo e
    // **exclui o fundo de propósito**. E `viewInsets.bottom` é o TECLADO, que
    // vale 0 com o teclado fechado; a barra de navegação do sistema é outra
    // coisa (`padding.bottom`) e ninguém a compensava — o botão de confirmar
    // ficava por baixo dela. Somam-se as duas: o `padding.bottom` já vem a 0
    // quando o teclado tapa a barra, por isso nunca há espaço a dobrar.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: Spacing.lg + inset + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              const Expanded(
                child: Text('Pagamento',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text('Total: $eur',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          if (widget.message != null) ...[
            const SizedBox(height: 4),
            Text(widget.message!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: Spacing.md),
          TvdePaymentSelector(
            current: _method,
            cardEnabled: widget.allowOnline,
            onChanged: (m) => setState(() {
              _method = m;
              _phoneError = null;
            }),
            phoneController: _phoneController,
            phoneError: _phoneError,
          ),
          const SizedBox(height: Spacing.md),
          // Nota opcional para o MOTORISTA — mesmo widget/limite do delivery.
          CustomerNoteField(
            controller: _noteController,
            title: 'Nota para o motorista (opcional)',
            hint: 'Ex.: espero à porta, levo mala grande, cadeira de bebé',
          ),

          // ── Token discount toggle ──────────────────────────
          if (widget.allowTokens && _tokensLoaded && _availableTokens > 0) ...[
            const SizedBox(height: Spacing.md),
            _buildTokenToggle(),
          ],

          const SizedBox(height: Spacing.lg),
          BoraAccentButton(
            label: _method == 'cash'
                ? 'Confirmar · pagar em dinheiro'
                : 'Pagar $eur',
            icon: Icons.check,
            onPressed: () {
              // MB Way exige o número (9 dígitos PT) — mesma validação do
              // picker das Reservas. Sem ele a Stripe recusa o PaymentIntent.
              String? phone;
              if (_method == 'mbway') {
                final digits =
                    _phoneController.text.replaceAll(RegExp(r'\D'), '');
                if (digits.length != 9) {
                  setState(() =>
                      _phoneError = 'Número MBWay inválido (9 dígitos).');
                  return;
                }
                phone = digits;
              }
              final tokensToUse = _useTokens ? _calculateTokensToUse() : 0;
              Navigator.pop(
                context,
                _TvdePayResult(_method, _noteController.text, tokensToUse,
                    mbwayPhone: phone),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// [F3] Toggle "Garantir a volta" — pacote ida+volta com desconto dinâmico.
class _RoundtripToggle extends StatelessWidget {
  const _RoundtripToggle(
      {required this.value,
      required this.priceCents,
      required this.savingCents,
      required this.onChanged});
  final bool value;
  final int priceCents;
  final int savingCents;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasPrice = priceCents > 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(
            color: value ? AppColors.primary : AppColors.divider),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: hasPrice ? onChanged : null,
        activeColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        title: const Row(
          children: [
            Icon(Icons.sync_alt, size: 18, color: AppColors.primary),
            SizedBox(width: Spacing.sm),
            Text('Garantir a volta',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: hasPrice
              ? Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text:
                          'Ida + volta por €${(priceCents / 100).toStringAsFixed(2)}',
                    ),
                    if (savingCents > 0)
                      TextSpan(
                        text:
                            ' · poupas €${(savingCents / 100).toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                  ]),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSubtle),
                )
              : const Text(
                  'Escolhe o destino para ver o preço do pacote.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSubtle),
                ),
        ),
      ),
    );
  }
}

/// [F3] Card do vale-volta ativo (topo do ecrã) com "Chamar a volta".
class _ReturnCreditCard extends StatelessWidget {
  const _ReturnCreditCard(
      {required this.credit, required this.busy, required this.onCall});
  final Map<String, dynamic> credit;
  final bool busy;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final expStr = credit['expires_at']?.toString();
    final exp = expStr == null ? null : DateTime.tryParse(expStr);
    String prazo = '';
    if (exp != null) {
      final left = exp.difference(DateTime.now());
      if (!left.isNegative) {
        final h = left.inHours;
        final m = left.inMinutes % 60;
        prazo = h > 0
            ? 'Válido mais ${h}h${m.toString().padLeft(2, '0')}'
            : 'Válido mais ${left.inMinutes} min';
      }
    }
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_alt, color: Colors.white),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tens uma volta garantida',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                if (prazo.isNotEmpty)
                  Text(prazo,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          FilledButton(
            onPressed: busy ? null : onCall,
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary),
            child: const Text('Chamar a volta'),
          ),
        ],
      ),
    );
  }
}

/// Destino escolhido para a corrida de volta.
class _ReturnDest {
  const _ReturnDest({
    required this.label,
    required this.lat,
    required this.lng,
    required this.originLabel,
    required this.originLat,
    required this.originLng,
  });
  final String label;
  final double lat;
  final double lng;

  /// Origem escolhida pelo cliente (pré-preenchida com a localização atual,
  /// mas editável — a volta pode partir de outro sítio que não o da ida).
  final String originLabel;
  final double originLat;
  final double originLng;
}

/// [F3] Folha da volta: **de onde sais** (pré-preenchido com a localização
/// atual, editável) e **destino**. Ocupa mais de meio ecrã de propósito — o
/// overlay de sugestões do autocomplete tem ~260 px e numa folha baixa ficava
/// cortado (mesmo motivo do `_AddStopSheet` no ecrã de tracking).
class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({
    required this.initialOriginLabel,
    required this.initialOrigin,
  });

  final String initialOriginLabel;
  final LatLng? initialOrigin;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  late final TextEditingController _origin;
  final TextEditingController _dest = TextEditingController();

  LatLng? _originCoords;
  double? _destLat;
  double? _destLng;
  String? _destLabel;
  String? _error;

  @override
  void initState() {
    super.initState();
    _origin = TextEditingController(text: widget.initialOriginLabel);
    _originCoords = widget.initialOrigin;
  }

  @override
  void dispose() {
    _origin.dispose();
    _dest.dispose();
    super.dispose();
  }

  void _confirm() {
    final o = _originCoords;
    if (o == null) {
      setState(() => _error = 'Escolhe de onde sais na lista de sugestões.');
      return;
    }
    if (_destLat == null || _destLng == null) {
      setState(() => _error = 'Escolhe o destino na lista de sugestões.');
      return;
    }
    Navigator.pop(
      context,
      _ReturnDest(
        label: _destLabel ?? _dest.text,
        lat: _destLat!,
        lng: _destLng!,
        originLabel: _origin.text,
        originLat: o.latitude,
        originLng: o.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom;
    // [Ronda 2] O teclado era descontado DUAS vezes — à altura (`0.72h - inset`)
    // e ao padding (`+ inset`) — e nada levantava a folha. Como a folha está
    // ancorada ao fundo, com um teclado normal (~0.4h) ela ficava INTEIRA por
    // baixo dele: o campo ganhava foco (o teclado subia) mas não se via o texto
    // nem se conseguia tocar nas sugestões do autocomplete.
    // O `margin` faz o que o padding interno não podia fazer: sobe a caixa toda
    // acima do teclado (mesmo efeito do `_AddStopSheet`, que já funcionava).
    final maxSheet = media.size.height - inset - media.padding.top;
    final desired = media.size.height * 0.72;
    return Container(
      margin: EdgeInsets.only(bottom: inset),
      height: desired < maxSheet ? desired : maxSheet,
      child: SingleChildScrollView(
        // Arrastar a folha fecha o teclado sem fechar a folha — o cliente já
        // não precisa de tocar fora (que agora nem fecha).
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_alt, color: AppColors.primary),
                const SizedBox(width: Spacing.sm),
                const Expanded(
                  child: Text('Chamar a minha volta',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            const Text(
                'A volta já está paga. Confirma de onde sais e para onde vais.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: Spacing.md),
            AddressAutocompleteField(
              key: const Key('tvde_return_origin'),
              controller: _origin,
              labelText: 'De onde sais',
              prefixIcon: const Icon(Icons.my_location, size: 20),
              onSelected: (address, coords) {
                if (coords == null) return;
                setState(() {
                  _originCoords = LatLng(coords.latitude, coords.longitude);
                  _error = null;
                });
              },
              // Editar à mão invalida as coordenadas antigas: sem escolher uma
              // sugestão não há coordenadas, e o botão avisa em vez de mandar
              // o cliente para o sítio errado.
              onChanged: (_) => setState(() => _originCoords = null),
            ),
            const SizedBox(height: Spacing.md),
            AddressAutocompleteField(
              key: const Key('tvde_return_dest'),
              controller: _dest,
              labelText: 'Destino da volta',
              prefixIcon: const Icon(Icons.place_outlined, size: 20),
              onSelected: (address, coords) {
                if (coords == null) return;
                setState(() {
                  _destLat = coords.latitude;
                  _destLng = coords.longitude;
                  _destLabel = address;
                  _error = null;
                });
              },
              onChanged: (_) => setState(() {
                _destLat = null;
                _destLng = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
            ],
            const SizedBox(height: Spacing.lg),
            BoraAccentButton(
              key: const Key('tvde_return_confirm'),
              label: 'Chamar a volta',
              onPressed: _confirm,
            ),
            // Espaço para o overlay de sugestões do autocomplete não ficar
            // cortado quando o campo está perto do fundo.
            const SizedBox(height: 260),
          ],
        ),
      ),
    );
  }
}
