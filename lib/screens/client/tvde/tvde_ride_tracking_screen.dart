import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_fare_view.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/directions_service.dart';
import '../../../services/payment_service.dart';
import '../../../stores/tvde_chat_store.dart';
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/tvde/tvde_roundtrip_driver_notice.dart';
import '../../shared/tvde_chat_screen.dart';
import 'ride_mbway_waiting_dialog.dart';
import 'tvde_rate_screen.dart';

/// TVDE — Mapa em tempo real do estado da corrida (reusa google_maps_flutter,
/// o mesmo stack de mapa do delivery). Consome o realtime de tvde_rides
/// produzido pela Fase 2.
class TvdeRideTrackingScreen extends StatefulWidget {
  const TvdeRideTrackingScreen({super.key});

  @override
  State<TvdeRideTrackingScreen> createState() => _TvdeRideTrackingScreenState();
}

class _TvdeRideTrackingScreenState extends State<TvdeRideTrackingScreen>
    with WidgetsBindingObserver {
  GoogleMapController? _map;
  LatLng? _driverPos;
  String? _driverName;
  double? _driverRating;
  // D1/D — cartão completo do motorista para o passageiro.
  String? _driverPhotoUrl;
  String? _driverCar; // marca/modelo
  String? _driverCarColor;
  String? _driverPlate;
  String? _driverPhone; // E — botão ligar
  Timer? _driverPoll;
  Timer? _animTimer;
  bool _navigatedToRate = false;

  /// [Item I] chat da corrida — ouvido para o badge de nao-lidas (lado cliente).
  TvdeChatStore? _chatStore;
  String? _chatRideId;

  /// C5 — mesma velocidade média do dispatch (30 km/h) para o ETA.
  static const double _avgSpeedKmh = 30.0;

  // ── B2 — rota real grossa recolha→destino (mesmo DirectionsService/chave). ──
  final DirectionsService _directions = DirectionsService();
  Set<Polyline> _routePolys = <Polyline>{};
  String? _routeKey;

  // ── [Bloco 5, 30/08] rota do MOTORISTA (→recolha antes de embarcar,
  // →destino em viagem), estilo Uber. Refaz-se quando a fase muda ou o carro
  // se afasta ≥120 m do ponto onde a rota foi traçada (poupa Directions).
  Set<Polyline> _driverRoutePolys = <Polyline>{};
  LatLng? _driverRouteFrom;
  String _driverRoutePhase = '';

  // ── Heading-up (paridade com o mapa do motorista) ─────────────────────────
  // Câmara estilo Waze: segue o carro com zoom/tilt de navegação e RODA
  // (bearing) conforme a direção de marcha, calculada pelo delta de posições
  // do poll (≥5 m para não amplificar ruído de GPS) — mesmo padrão do
  // tvde_driver_home_screen [Item G]. Valores espelham platform_settings
  // (tvde_nav_zoom / tvde_nav_tilt); leitura dinâmica pendente, como no
  // ecrã do motorista.
  static const double _kNavZoom = 17.5;
  static const double _kNavTilt = 45.0;
  double _bearing = 0;
  LatLng? _lastBearingPos;
  bool _followCam = true; // gesto do utilizador pausa; botão mira religa
  bool _progCamMove = false;

  // ── [CAMPO-02 · Feature 1] Paradas adicionais ─────────────────────────────
  List<TvdeRideStop> _stops = const [];
  int _maxStops = 2; // fallback; sobrescrito por platform_settings
  int _stopFeeCents = 200; // taxa cliente por parada (fallback)
  int _stopTimerSeconds = 120; // espera gratuita informativa por parada
  int _cancelGraceSeconds = 180; // [F2] janela grátis de cancelamento (fallback)
  int _packageCents = TvdeRoundtripPrice.fallbackCents;
  Timer? _stopsTicker; // 1s: repinta countdowns + recarrega paradas a cada 5s
  int _stopsTick = 0;
  bool _addingStop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Espelho do servidor logo ao abrir: o objeto em memória pode estar velho
    // (ex.: corrida entretanto cancelada noutro device / pelo cron).
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<TvdeStore>().refreshActiveRide());
    _driverPoll = Timer.periodic(const Duration(seconds: 5), (_) => _pollDriver());
    _stopsTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _stopsTick++;
      if (_stopsTick % 5 == 0) _loadStops();
      // repinta os countdowns de espera (só quando há paradas alcançadas)
      if (_stops.any((s) => s.reached)) setState(() {});
    });
    _loadStopSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStops());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltar ao foreground → reatar o realtime (o canal pode ter morrido em
    // silêncio no background — a tela da Sandra ficou presa em "à procura" a
    // 30/08) E rebuscar a corrida no servidor. Um estado terminal que chegue
    // por aqui faz a tela sair sozinha (build já trata isCancelled/isFinished).
    if (state == AppLifecycleState.resumed && mounted) {
      final store = context.read<TvdeStore>();
      store.reattachActiveRide();
      // MB Way de pacote pendente? Retomar a ativação em fundo (idempotente).
      unawaited(store.resumePendingRoundtripActivation());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driverPoll?.cancel();
    _animTimer?.cancel();
    _stopsTicker?.cancel();
    _map?.dispose();
    _directions.dispose();
    if (_chatRideId != null) _chatStore?.unlisten(_chatRideId!);
    super.dispose();
  }

  Future<void> _loadStopSettings() async {
    final store = context.read<TvdeStore>();
    final max = await store.getSettingInt('tvde_max_stops', 2);
    final fee = await store.getSettingInt('tvde_stop_fee_cents', 200);
    final timer = await store.getSettingInt('tvde_stop_timer_seconds', 120);
    final grace = await store.getSettingInt('cancel_grace_seconds', 180);
    final ride = store.activeRide;
    final pkg = ride != null
        ? await TvdeRoundtripPrice.loadForRide(store, ride)
        : TvdeRoundtripPrice.fallbackCents;
    if (mounted) {
      setState(() {
        _maxStops = max;
        _stopFeeCents = fee;
        _stopTimerSeconds = timer;
        _cancelGraceSeconds = grace;
        _packageCents = pkg;
      });
    }
  }

  Future<void> _loadStops() async {
    final ride = context.read<TvdeStore>().activeRide;
    if (ride == null) return;
    final stops = await context.read<TvdeStore>().fetchRideStops(ride.id);
    if (mounted) setState(() => _stops = stops);
  }

  /// Cliente adiciona uma parada no meio da corrida (abre pesquisa de morada).
  Future<void> _addStop(TvdeRide ride) async {
    if (_addingStop) return;
    final picked = await showModalBottomSheet<_PickedStop>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddStopSheet(),
    );
    if (picked == null || !mounted) return;

    // Corrida paga no app: os €2 pagam-se NA HORA e a parada só entra depois de
    // o pagamento confirmar. Em dinheiro o motorista cobra tudo no fim.
    if (ride.isPaidOnline) {
      await _addStopPaid(ride, picked);
      return;
    }

    setState(() => _addingStop = true);
    try {
      await context.read<TvdeStore>().addStop(
            ride.id,
            lat: picked.lat,
            lng: picked.lng,
            label: picked.label,
          );
      await _loadStops();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('max_stops_reached')
            ? 'Já atingiste o máximo de $_maxStops paradas.'
            : 'Não foi possível adicionar a parada.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _addingStop = false);
    }
  }

  /// Parada numa corrida **paga online** (cartão ou MB Way): confirma o valor,
  /// cobra, e só adiciona a parada quando o pagamento passar.
  Future<void> _addStopPaid(TvdeRide ride, _PickedStop picked) async {
    final method = ride.paymentMethod == 'mbway' ? 'mbway' : 'card';

    // 1. Folha de confirmação (com o número MB Way quando é esse o método).
    final confirmed = await showModalBottomSheet<_StopPayConfirm>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StopPayConfirmSheet(
        label: picked.label,
        feeCents: _stopFeeCents,
        method: method,
        initialPhone: Supabase.instance.client.auth.currentUser?.phone ?? '',
      ),
    );
    if (confirmed == null || !mounted) return;

    setState(() => _addingStop = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = context.read<TvdeStore>();
      final res = await store.chargeStop(
        ride.id,
        method: method,
        lat: picked.lat,
        lng: picked.lng,
        label: picked.label,
        mbwayPhone: method == 'mbway' ? confirmed.phone : null,
      );
      final piId = res['paymentIntentId'] as String?;
      if (piId == null) throw Exception('sem_payment_intent');
      final amountEur = ((res['amountCents'] as num?)?.toInt() ?? _stopFeeCents) / 100;

      Map<String, dynamic>? outcome;
      bool paid = false;

      if (method == 'card') {
        // Cartão: folha da Stripe → uma única confirmação.
        final clientSecret = res['clientSecret'] as String?;
        if (clientSecret == null) throw Exception('sem_client_secret');
        await PaymentService().processPayment(clientSecret);
        outcome = await store.confirmStopPayment(piId);
        paid = outcome?['succeeded'] == true;
      } else {
        // MB Way: sem folha da Stripe — confirma-se na app do banco e nós
        // fazemos poll (3 s até 120 s), igual ao da corrida.
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => TvdeRideMbwayWaitingDialog.forStop(
            paymentIntentId: piId,
            amountEur: amountEur,
            onResponse: (r) => outcome = r,
          ),
        );
        paid = ok == true;
      }

      await _loadStops();
      if (!mounted) return;

      if (paid) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Parada adicionada.')),
        );
      } else if (outcome?['refunded'] == true) {
        messenger.showSnackBar(SnackBar(
          content: Text('Pagamento devolvido — não foi possível adicionar a '
              'parada. ${_stopErrorPt(outcome?['error']?.toString())}'),
        ));
      } else {
        messenger.showSnackBar(const SnackBar(
          content: Text('Não recebemos a confirmação do pagamento. '
              'A parada não foi adicionada.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(_stopErrorPt(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _addingStop = false);
    }
  }

  /// Traduz os códigos de erro da Edge Function para PT-PT.
  String _stopErrorPt(String? raw) {
    final e = raw ?? '';
    if (e.contains('max_stops_reached')) {
      return 'Já atingiste o máximo de $_maxStops paradas.';
    }
    if (e.contains('invalid_ride_state_for_stop')) {
      return 'A corrida já não permite adicionar paradas.';
    }
    if (e.contains('card_payments_not_enabled')) {
      return 'Os pagamentos no cartão estão desativados de momento.';
    }
    if (e.contains('below_minimum')) {
      return 'Valor abaixo do mínimo aceite pelo pagamento.';
    }
    return 'Não foi possível adicionar a parada.';
  }

  Future<void> _removeStop(TvdeRide ride, TvdeRideStop stop) async {
    try {
      await context.read<TvdeStore>().removeStop(ride.id, stop.id);
      await _loadStops();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível remover a parada.')),
        );
      }
    }
  }

  /// B2 — traça a rota real recolha→destino (grossa). Uma vez por corrida.
  Future<void> _maybeFetchRoute(TvdeRide ride) async {
    if (_routeKey == ride.id) return;
    _routeKey = ride.id;
    try {
      final route = await _directions.fetchRoute(
        origin: ll.LatLng(ride.originLat, ride.originLng),
        destination: ll.LatLng(ride.destLat, ride.destLng),
      );
      if (!mounted || route == null || route.points.isEmpty) return;
      setState(() {
        _routePolys = {
          Polyline(
            polylineId: const PolylineId('tvde_route'),
            points: route.points.toGMaps(),
            color: AppColors.primary,
            width: 12,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        };
      });
    } catch (_) {/* sem rota → mapa mantém-se sem a linha (fallback) */}
  }

  /// B5 — botão mira: recentra na posição do motorista (ou no ponto de
  /// recolha) com a câmara de navegação (zoom/tilt/bearing) e religa o follow.
  Future<void> _recenter(TvdeRide ride) async {
    final c = _map;
    if (c == null) return;
    final target = _driverPos ?? LatLng(ride.originLat, ride.originLng);
    _followCam = true;
    _progCamMove = true;
    try {
      await c.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: target,
        zoom: _kNavZoom,
        tilt: _kNavTilt,
        bearing: _bearing,
      )));
    } finally {
      _progCamMove = false;
    }
  }

  /// Heading-up: a câmara segue o carro e roda com a direção de marcha.
  /// Só quando o follow está ativo — um gesto do utilizador no mapa pausa
  /// (para poder explorar) e a mira religa.
  Future<void> _followDriver(LatLng pos) async {
    final c = _map;
    if (c == null || !_followCam) return;
    _progCamMove = true;
    try {
      await c.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: pos,
        zoom: _kNavZoom,
        tilt: _kNavTilt,
        bearing: _bearing,
      )));
    } finally {
      _progCamMove = false;
    }
  }

  /// C4 — animação suave do carro entre polls (12 passos × 80 ms, o mesmo
  /// padrão do DriverStore no delivery). Sem saltos de marker.
  void _setDriverPos(LatLng target) {
    // Heading-up: bearing pela direção de marcha, a partir das posições CRUAS
    // do poll (não das animadas) — paridade com o motorista [Item G].
    final prevRaw = _lastBearingPos;
    if (prevRaw != null) {
      final moved = Geolocator.distanceBetween(prevRaw.latitude,
          prevRaw.longitude, target.latitude, target.longitude);
      if (moved >= 5) {
        var b = Geolocator.bearingBetween(prevRaw.latitude, prevRaw.longitude,
            target.latitude, target.longitude);
        if (b < 0) b += 360;
        _bearing = b;
      }
    }
    _lastBearingPos = target;
    _followDriver(target);

    final from = _driverPos;
    if (from == null) {
      setState(() => _driverPos = target);
      return;
    }
    if ((from.latitude - target.latitude).abs() < 1e-6 &&
        (from.longitude - target.longitude).abs() < 1e-6) {
      return;
    }
    _animTimer?.cancel();
    var step = 0;
    const steps = 12;
    _animTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      step++;
      if (!mounted) {
        t.cancel();
        return;
      }
      final f = step / steps;
      setState(() => _driverPos = LatLng(
            from.latitude + (target.latitude - from.latitude) * f,
            from.longitude + (target.longitude - from.longitude) * f,
          ));
      if (step >= steps) t.cancel();
    });
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// C5 — ETA do motorista: até à recolha (antes de embarcar) ou até ao
  /// destino (em viagem). Null quando não há posição do motorista.
  int? _etaMinutes(TvdeRide ride) {
    final pos = _driverPos;
    if (pos == null) return null;
    final double tLat;
    final double tLng;
    if (ride.isInProgress) {
      tLat = ride.destLat;
      tLng = ride.destLng;
    } else if (ride.isAssigned) {
      tLat = ride.originLat;
      tLng = ride.originLng;
    } else {
      return null;
    }
    final km = _haversineKm(pos.latitude, pos.longitude, tLat, tLng);
    final mins = (km / _avgSpeedKmh * 60).ceil();
    return mins < 1 ? 1 : mins;
  }

  Future<void> _pollDriver() async {
    final ride = context.read<TvdeStore>().activeRide;
    // Também em viagem (em_andamento): alimenta o ETA ao destino e a animação.
    if (ride == null ||
        ride.driverId == null ||
        !(ride.isAssigned || ride.isInProgress)) {
      return;
    }
    try {
      // `driver_id` = auth uid do motorista → a linha resolve por user_id
      // (em motoristas reais drivers.id <> user_id; usar 'id' não encontrava
      // nada e o marker/cartão do motorista nunca aparecia).
      final row = await Supabase.instance.client
          .from('drivers')
          .select(
              'name, avg_rating, lat, lng, photo_url, vehicle_make_model, vehicle_color, license_plate, phone')
          .eq('user_id', ride.driverId!)
          .maybeSingle();
      final lat = (row?['lat'] as num?)?.toDouble();
      final lng = (row?['lng'] as num?)?.toDouble();
      if (mounted) {
        setState(() {
          _driverName = (row?['name'] as String?)?.trim();
          _driverRating = (row?['avg_rating'] as num?)?.toDouble();
          _driverPhotoUrl = (row?['photo_url'] as String?)?.trim();
          _driverCar = (row?['vehicle_make_model'] as String?)?.trim();
          _driverCarColor = (row?['vehicle_color'] as String?)?.trim();
          _driverPlate = (row?['license_plate'] as String?)?.trim();
          _driverPhone = (row?['phone'] as String?)?.trim();
        });
        // C4 — anima em vez de saltar.
        if (lat != null && lng != null) {
          final pos = LatLng(lat, lng);
          _setDriverPos(pos);
          // [Bloco 5] rota viva do motorista (→recolha / →destino).
          _maybeFetchDriverRoute(ride, pos);
        }
      }
    } catch (_) {}
  }

  /// [Bloco 5, 30/08] Rota do motorista até ao alvo da fase atual — como o
  /// Uber: o cliente vê o caminho que o carro vai fazer, não só o pontinho.
  Future<void> _maybeFetchDriverRoute(TvdeRide ride, LatLng pos) async {
    final phase =
        ride.isInProgress ? 'dest' : (ride.isAssigned ? 'pickup' : '');
    if (phase.isEmpty) {
      if (_driverRoutePolys.isNotEmpty && mounted) {
        setState(() => _driverRoutePolys = <Polyline>{});
      }
      return;
    }
    final from = _driverRouteFrom;
    final moved = from == null
        ? double.infinity
        : Geolocator.distanceBetween(
            from.latitude, from.longitude, pos.latitude, pos.longitude);
    if (phase == _driverRoutePhase && moved < 120) return;
    _driverRoutePhase = phase;
    _driverRouteFrom = pos;
    final target = phase == 'dest'
        ? ll.LatLng(ride.destLat, ride.destLng)
        : ll.LatLng(ride.originLat, ride.originLng);
    try {
      final route = await _directions.fetchRoute(
        origin: ll.LatLng(pos.latitude, pos.longitude),
        destination: target,
      );
      if (!mounted || route == null || route.points.isEmpty) return;
      setState(() {
        _driverRoutePolys = {
          Polyline(
            polylineId: const PolylineId('tvde_driver_route'),
            points: route.points.toGMaps(),
            color: AppColors.accent,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        };
      });
    } catch (_) {/* sem rota do motorista → fica só a rota grossa (B2) */}
  }

  void _maybeGoToRate(TvdeRide ride) {
    if (_navigatedToRate) return;
    if (ride.isFinished && !ride.ratedByClient) {
      _navigatedToRate = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => TvdeRateScreen(ride: ride)),
        );
      });
    }
  }

  Set<Marker> _markers(TvdeRide ride) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(ride.originLat, ride.originLng),
        infoWindow: const InfoWindow(title: 'Recolha'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: LatLng(ride.destLat, ride.destLng),
        infoWindow: const InfoWindow(title: 'Destino'),
      ),
    };
    if (_driverPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverPos!,
        infoWindow: const InfoWindow(title: 'Motorista'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ));
    }
    // [Feature 1] paradas adicionais numeradas.
    for (final s in _stops) {
      markers.add(Marker(
        markerId: MarkerId('stop_${s.id}'),
        position: LatLng(s.lat, s.lng),
        infoWindow: InfoWindow(title: 'Parada ${s.seq}', snippet: s.label),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    return markers;
  }

  /// E — ligar ao motorista (tel:), se o número existir.
  Future<void> _call() async {
    final phone = _driverPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// [Item I] garante subscricao ao chat desta corrida (badge de nao-lidas).
  void _ensureChatListen(TvdeRide ride) {
    if (_chatRideId == ride.id) return;
    final chat = context.read<TvdeChatStore>();
    if (_chatRideId != null) chat.unlisten(_chatRideId!);
    _chatStore = chat;
    chat.listen(ride.id);
    _chatRideId = ride.id;
  }

  /// E — abre o chat com o motorista (scoped por corrida).
  void _openChat(TvdeRide ride) {
    // [Item I] abrir marca as recebidas como lidas → badge zera.
    context.read<TvdeChatStore>().markRead(ride.id, 'client');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvdeChatScreen(
          rideId: ride.id,
          myRole: 'client',
          title: _driverName ?? 'Motorista',
          otherPhone: _driverPhone,
        ),
      ),
    );
  }

  /// "Tentar de novo" após `sem_motorista`.
  ///
  /// BUG 6 (2026-08-13) — em dinheiro repete-se aqui mesmo. Paga online, não:
  /// a corrida anterior já não tem pagamento aproveitável, e criar outra sem
  /// cobrar dava uma corrida em **dinheiro** disfarçada (o motorista chegaria a
  /// pedir o valor em mão a quem julgava já ter pago). Nesse caso o
  /// `retryRide` devolve `null` e mandamos o cliente ao ecrã de pedido, que
  /// tem a folha de pagamento.
  Future<void> _retry(TvdeRide ride, TvdeStore store) async {
    // Capturar o messenger ANTES do pop — depois o `context` deste ecrã já não
    // serve para o procurar.
    final messenger = ScaffoldMessenger.of(context);
    final novo = await store.retryRide();
    if (!mounted || novo != null) return;
    if (ride.isPaidOnline) {
      store.clearActiveRide();
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('Pede a corrida outra vez para escolheres o pagamento — '
            'a anterior não chegou a ter motorista e não foi cobrada.'),
      ));
    }
  }

  Future<void> _cancel(TvdeRide ride) async {
    // Corrida estacionada à espera do pagamento: nunca foi cobrada e nunca
    // chamou motorista, por isso desistir é grátis e imediato — mostrar a
    // janela de taxa aqui seria mentira.
    //
    // 2026-08-13 — `isPaymentSettling` ('processing') fica DE FORA: aí o
    // cliente já confirmou no banco e o dinheiro vai a caminho. Mandá-lo por
    // este atalho (`skipRefund: true`) apagava a corrida e deixava o pagamento
    // órfão na Stripe, sem nada para o devolver. Esse caso segue o caminho
    // normal, que passa pelo refund.
    if (ride.isAwaitingPayment && !ride.isPaymentSettling) {
      final desistir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desistir da corrida?'),
          content: const Text(
              'Ainda não foste cobrado e nenhum motorista foi chamado. Podes '
              'desistir sem custo.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Continuar a aguardar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sim, desistir')),
          ],
        ),
      );
      if (desistir != true || !mounted) return;
      try {
        final store = context.read<TvdeStore>();
        // Guarda 30/08 (corrida 5bac9a76): NUNCA cancelar como não-pago sem
        // perguntar primeiro ao servidor se o PaymentIntent passou entretanto.
        final res = await store.confirmRidePayment(ride.id);
        if (!mounted) return;
        final st = res?['payment_status'] as String?;
        if ((res != null && res['succeeded'] == true) || st == 'processing') {
          await store.refreshActiveRide();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Afinal o pagamento já entrou (ou está a ser '
                  'confirmado) — a corrida segue.')));
          return;
        }
        await store.cancelRide(ride.id,
            reason: 'payment_failed', skipRefund: true);
        if (!mounted) return;
        // Mesma saída determinística do cancelamento normal (P0-3).
        context.read<TvdeStore>().clearActiveRide();
        Navigator.pop(context);
      } catch (e) {
        _cancelFalhou(e);
      }
      return;
    }

    // [F2] Preview da taxa por tempo (o backend é a fonte de verdade e respeita
    // o kill-switch tvde_cancel_full_after_grace). Grátis dentro da janela; depois,
    // antes do pickup, o cliente paga o valor TOTAL da corrida.
    final created = ride.createdAt;
    final elapsed =
        created == null ? 0 : DateTime.now().difference(created).inSeconds;
    final withinGrace = elapsed <= _cancelGraceSeconds;
    // Preview pelo memo partilhado: numa perna do pacote €8 a "corrida toda"
    // é o pacote, não a tarifa base (que o cliente nunca chega a pagar).
    final feeCents = withinGrace
        ? 0
        : TvdeFareView.of(ride, packageCents: _packageCents).clientTotalCents;
    final graceMin = (_cancelGraceSeconds / 60).round();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar corrida?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (feeCents == 0)
              Text(
                  'Cancelamento grátis (dentro dos primeiros $graceMin min).',
                  style: const TextStyle(color: AppColors.textSecondary))
            else ...[
              Text(
                  'Já passaram mais de $graceMin min. Cancelar agora tem um custo:',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: Spacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.euro, size: 18, color: AppColors.error),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'Custo de cancelamento: €${(feeCents / 100).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              const Text('Corresponde ao valor total da corrida.',
                  style:
                      TextStyle(color: AppColors.textSubtle, fontSize: 12.5)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(feeCents == 0 ? 'Sim, cancelar' : 'Cancelar e pagar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<TvdeStore>().cancelRide(ride.id);
      if (!mounted) return;
      // P0-3: navegação determinística — limpa o estado e sai já, sem depender
      // do realtime chegar para fechar o ecrã. Reabrir "Bora Motorista" mostra
      // a tela de destino limpa (a corrida cancelada não é retomável).
      context.read<TvdeStore>().clearActiveRide();
      Navigator.pop(context);
    } catch (e) {
      _cancelFalhou(e);
    }
  }

  /// Falha ao cancelar. Se o servidor responder que a corrida JÁ está num
  /// estado terminal (cancelada noutro device / limpa pelo cron), isso é
  /// sucesso do ponto de vista do cliente — o botão nunca fica "mudo":
  /// confirma por palavras, limpa e sai. Qualquer outra falha ressincroniza
  /// com o servidor (se entretanto ficou terminal, o build sai sozinho).
  void _cancelFalhou(Object e) {
    if (!mounted) return;
    final s = e.toString();
    if (s.contains('ride_already_terminal')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.contains('finalizada')
              ? 'A corrida já tinha terminado.'
              : 'A corrida já estava cancelada.')));
      context.read<TvdeStore>().clearActiveRide();
      Navigator.pop(context);
      return;
    }
    context.read<TvdeStore>().refreshActiveRide();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Não foi possível cancelar.')),
    );
  }

  /// Corrida estacionada em `aguarda pagamento` (cartão): reapresenta a
  /// PaymentSheet com o MESMO PaymentIntent e, se o cliente pagar, pede ao
  /// servidor para revalidar e libertar já — sem depender só do webhook.
  Future<void> _pagarDeNovo(TvdeRide ride) async {
    final store = context.read<TvdeStore>();
    final secret = store.cardClientSecretFor(ride.id);
    if (secret == null) return;
    try {
      await PaymentService().processPayment(secret);
    } catch (_) {
      return; // desistiu outra vez — a tela continua a mostrar o estado real
    }
    if (!mounted) return;
    for (var i = 0; i < 3; i++) {
      final res = await store.confirmRidePayment(ride.id);
      if (!mounted) return;
      if (res != null && res['succeeded'] == true) break;
      if (i < 2) await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) await store.refreshActiveRide();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final ride = store.activeRide;

    if (ride == null) {
      return const Scaffold(
        appBar: BoraScreenAppBar(title: 'A tua corrida'),
        body: Center(child: Text('Sem corrida ativa.')),
      );
    }

    _maybeGoToRate(ride);
    _ensureChatListen(ride);

    if (ride.isCancelled) {
      return _TerminalView(
        icon: Icons.cancel,
        color: AppColors.error,
        title: ride.statusLabel,
        onClose: () {
          store.clearActiveRide();
          Navigator.pop(context);
        },
      );
    }

    final center = LatLng(
      (ride.originLat + ride.destLat) / 2,
      (ride.originLng + ride.destLng) / 2,
    );
    // B2 — garante a rota real traçada (idempotente por corrida).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeFetchRoute(ride));

    // [Bloco 5, 30/08] Com motorista atribuído (ou em viagem), o cartão grande
    // dava lugar ao mapa: fica uma FITINHA em baixo que puxa para cima
    // (DraggableScrollableSheet) para ver o resto. Nos outros estados (à
    // procura, a confirmar pagamento, sem motorista) o cartão completo mantém-se
    // — aí a informação É o ecrã.
    final compact = ride.isAssigned || ride.isInProgress;
    const stripSize = 0.14;
    final panel = _StatusPanel(
      ride: ride,
      busy: store.busy,
      driverName: _driverName,
      driverRating: _driverRating,
      driverPhotoUrl: _driverPhotoUrl,
      driverCar: _driverCar,
      driverCarColor: _driverCarColor,
      driverPlate: _driverPlate,
      hasPhone: _driverPhone != null && _driverPhone!.isNotEmpty,
      etaMinutes: _etaMinutes(ride),
      unreadCount: context.watch<TvdeChatStore>().unreadFor(ride.id, 'client'),
      stops: _stops,
      maxStops: _maxStops,
      stopFeeCents: _stopFeeCents,
      stopTimerSeconds: _stopTimerSeconds,
      packageCents: _packageCents,
      addingStop: _addingStop,
      onAddStop: () => _addStop(ride),
      onRemoveStop: (stop) => _removeStop(ride, stop),
      onChat: () => _openChat(ride),
      onCall: _call,
      onCancel: () => _cancel(ride),
      onPayAgain: ride.isAwaitingPayment &&
              ride.paymentMethod == 'card' &&
              store.cardClientSecretFor(ride.id) != null
          ? () => _pagarDeNovo(ride)
          : null,
      onRetry: () => _retry(ride, store),
      onClose: () {
        store.clearActiveRide();
        Navigator.pop(context);
      },
    );

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'A tua corrida'),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers(ride),
            // B2 (grossa recolha→destino) + Bloco 5 (rota viva do motorista).
            polylines: {..._routePolys, ..._driverRoutePolys},
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            // Com heading-up a bússola deixa o utilizador repor o norte.
            compassEnabled: true,
            mapToolbarEnabled: false,
            onMapCreated: (c) => _map = c,
            onCameraMoveStarted: () {
              // Gesto do utilizador (movimento não-programático) pausa o
              // follow — a mira (_recenter) religa.
              if (!_progCamMove) _followCam = false;
            },
          ),
          // B5 — botão mira (recentra no motorista/recolha). Fica SEMPRE acima
          // da fitinha/painel, em qualquer estado.
          Positioned(
            right: Spacing.md,
            bottom: compact
                ? MediaQuery.of(context).size.height * stripSize + Spacing.md
                : 200,
            child: FloatingActionButton.small(
              heroTag: 'tvde_client_recenter',
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              onPressed: () => _recenter(ride),
              child: const Icon(Icons.my_location),
            ),
          ),
          if (!compact)
            Align(alignment: Alignment.bottomCenter, child: panel)
          else
            DraggableScrollableSheet(
              initialChildSize: stripSize,
              minChildSize: stripSize,
              maxChildSize: 0.82,
              snap: true,
              snapSizes: const [stripSize, 0.82],
              builder: (context, scrollCtrl) => Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x29000000),
                        blurRadius: 16,
                        offset: Offset(0, -2)),
                  ],
                ),
                child: ListView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: Spacing.sm),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    _CompactStrip(
                      ride: ride,
                      fare: TvdeFareView.of(ride,
                          packageCents: _packageCents),
                      etaMinutes: _etaMinutes(ride),
                    ),
                    panel,
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [Bloco 5, 30/08] A fitinha do fundo — estilo Uber: uma linha com o estado,
/// o ETA e o preço; puxar para cima mostra o painel completo (paradas,
/// mensagem, ligar, cancelar).
class _CompactStrip extends StatelessWidget {
  const _CompactStrip({
    required this.ride,
    required this.fare,
    required this.etaMinutes,
  });

  final TvdeRide ride;
  final TvdeFareView fare;
  final int? etaMinutes;

  String get _texto {
    if (ride.isInProgress) {
      return etaMinutes != null
          ? 'Viagem em curso · ~$etaMinutes min'
          : 'Viagem em curso';
    }
    if (ride.hasArrived) return 'O motorista chegou';
    return etaMinutes != null
        ? 'Motorista a caminho · ~$etaMinutes min'
        : 'Motorista a caminho';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.sm, Spacing.lg, Spacing.xs),
      child: Row(
        children: [
          Icon(
            ride.isInProgress ? Icons.navigation : Icons.directions_car,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              _texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
          Text(
            fare.clientLabel.split(' ').first, // só o valor, o resto no painel
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_up,
              size: 20, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.ride,
    required this.busy,
    required this.driverName,
    required this.driverRating,
    required this.driverPhotoUrl,
    required this.driverCar,
    required this.driverCarColor,
    required this.driverPlate,
    required this.hasPhone,
    required this.etaMinutes,
    required this.unreadCount,
    required this.stops,
    required this.maxStops,
    required this.stopFeeCents,
    required this.stopTimerSeconds,
    required this.packageCents,
    required this.addingStop,
    required this.onAddStop,
    required this.onRemoveStop,
    required this.onChat,
    required this.onCall,
    required this.onCancel,
    this.onPayAgain,
    required this.onRetry,
    required this.onClose,
  });

  final TvdeRide ride;
  final bool busy;
  final String? driverName;
  final double? driverRating;
  // D1 — cartão completo do motorista.
  final String? driverPhotoUrl;
  final String? driverCar;
  final String? driverCarColor;
  final String? driverPlate;
  final bool hasPhone;

  /// C5 — "chega em ~X min" (recolha) / "destino em ~X min" (em viagem).
  final int? etaMinutes;
  /// [Item I] mensagens por ler (badge no botão Mensagem).
  final int unreadCount;

  /// [Feature 1] paradas adicionais + config.
  final List<TvdeRideStop> stops;
  final int maxStops;
  final int stopFeeCents;
  final int stopTimerSeconds;
  final int packageCents;
  final bool addingStop;
  final VoidCallback onAddStop;
  final void Function(TvdeRideStop) onRemoveStop;

  final VoidCallback onChat;
  final VoidCallback onCall;
  final VoidCallback onCancel;
  final VoidCallback? onPayAgain;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  /// D1 — linha do carro: "Renault Clio · Cinzento · AA-00-BB".
  String? _carLine() {
    final parts = <String>[
      if (driverCar != null && driverCar!.isNotEmpty) driverCar!,
      if (driverCarColor != null && driverCarColor!.isNotEmpty) driverCarColor!,
      if (driverPlate != null && driverPlate!.isNotEmpty) driverPlate!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final fare = TvdeFareView.of(ride, packageCents: packageCents);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ride.isAssigned &&
              driverName != null &&
              driverName!.isNotEmpty) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  backgroundImage:
                      (driverPhotoUrl != null && driverPhotoUrl!.isNotEmpty)
                          ? NetworkImage(driverPhotoUrl!)
                          : null,
                  child: (driverPhotoUrl == null || driverPhotoUrl!.isEmpty)
                      ? const Icon(Icons.person, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driverName!,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textPrimary)),
                      // D1 — carro: marca/modelo · cor · matrícula.
                      if (_carLine() != null)
                        Text(_carLine()!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (driverRating != null && driverRating! > 0) ...[
                  const Icon(Icons.star, size: 16, color: AppColors.accent),
                  const SizedBox(width: 2),
                  Text(driverRating!.toStringAsFixed(1),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ],
              ],
            ),
            // E — falar com o motorista (chat + ligar).
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text('$unreadCount'),
                    child: OutlinedButton.icon(
                      onPressed: onChat,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Mensagem'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.md)),
                      ),
                    ),
                  ),
                ),
                if (hasPhone) ...[
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onCall,
                      icon: const Icon(Icons.call, size: 18),
                      label: const Text('Ligar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.md)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // C5 — ETA do motorista (recolha ou destino).
            if (etaMinutes != null && !ride.isQueued) ...[
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    ride.isInProgress
                        ? 'Chegada ao destino em ~$etaMinutes min'
                        : 'O motorista chega em ~$etaMinutes min',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
            const Divider(height: Spacing.lg),
          ],
          Row(
            children: [
              if (ride.isSearching || ride.isAwaitingPayment)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(_icon(ride), color: AppColors.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                // Estado honesto (30/08): enquanto o pagamento online não está
                // `succeeded`, ninguém está a ser chamado — dizer "A confirmar
                // pagamento…" e nunca "À procura de motorista".
                child: Text(
                    ride.isAwaitingPayment
                        ? 'A confirmar pagamento…'
                        : ride.statusLabel,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              if (fare.coveredByPlan && fare.clientTotalCents == 0)
                // [Item B] corrida coberta pelo plano → cliente paga €0.
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text('Incluída no plano',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                )
              else
                // Fonte única partilhada com o badge do motorista: numa perna
                // do pacote €8 mostra o preço do PACOTE (nunca a tarifa base),
                // e soma sempre as paradas já adicionadas.
                Flexible(
                  child: Text(fare.clientLabel,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            '${ride.originLabel ?? 'Recolha'} → ${ride.destLabel ?? 'Destino'}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          // Corrida estacionada à espera do pagamento: NÃO está a chamar
          // motorista nenhum. Dizê-lo por palavras, para o cliente não pensar
          // que já vem alguém a caminho.
          if (ride.isAwaitingPayment) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              ride.paymentMethod == 'mbway'
                  // 2026-08-13 — dizer exactamente onde está a bola. O cliente
                  // que vê "à espera da confirmação do pagamento" sem saber que
                  // é ELE que tem de confirmar no banco, fica à espera do nada.
                  ? 'À espera da confirmação do MB Way. Abre a app do teu banco '
                      'e confirma o pagamento — só depois começamos a procurar '
                      'motorista.'
                  : onPayAgain != null
                      // Sheet aberta e abandonada sem pagar (d947b446): dizer
                      // a verdade e dar a saída, em vez de prometer que
                      // "aparece dentro de momentos".
                      ? 'O pagamento não foi concluído — ainda não começámos '
                          'a procurar motorista e não foste cobrado. Toca em '
                          '«Pagar de novo» ou cancela sem custo.'
                      : 'Ainda não começámos a procurar motorista — estamos à '
                          'espera da confirmação do pagamento. Se já '
                          'confirmaste, aparece dentro de momentos.',
              style: const TextStyle(
                  color: AppColors.textSubtle, fontSize: 12),
            ),
            if (onPayAgain != null) ...[
              const SizedBox(height: Spacing.md),
              BoraAccentButton(
                label: 'Pagar de novo',
                icon: Icons.credit_card,
                loading: busy,
                onPressed: onPayAgain!,
              ),
            ],
          ],
          // Back-to-back — passageiro em fila: contexto claro, sem spinner.
          if (ride.isQueued && ride.isAssigned) ...[
            const SizedBox(height: Spacing.sm),
            const Text(
              'Serás o próximo: o motorista está a terminar uma viagem perto '
              'de ti e segue logo para a tua recolha.',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ],
          _buildStops(context),
          const SizedBox(height: Spacing.lg),
          if (ride.isNoDriver) ...[
            const Text(
              'De momento não há motoristas disponíveis. Podes tentar novamente.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.md),
            BoraAccentButton(
              label: 'Tentar de novo',
              icon: Icons.refresh,
              loading: busy,
              onPressed: onRetry,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: onClose, child: const Text('Fechar')),
          ] else if (ride.isInProgress) ...[
            const Text('Boa viagem! O valor final é calculado pela distância real.',
                style: TextStyle(color: AppColors.textSubtle, fontSize: 12)),
          ] else ...[
            OutlinedButton.icon(
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancelar corrida'),
            ),
          ],
        ],
      ),
    );
  }

  IconData _icon(TvdeRide ride) {
    if (ride.hasArrived) return Icons.where_to_vote;
    if (ride.isOnTheWay) return Icons.directions_car;
    if (ride.isInProgress) return Icons.navigation;
    return Icons.local_taxi;
  }

  /// [Feature 1] Secção de paradas adicionais — só enquanto o motorista já vem
  /// a caminho / chegou / em viagem (estados em que faz sentido "passa aqui").
  Widget _buildStops(BuildContext context) {
    final canManage = ride.isOnTheWay || ride.hasArrived || ride.isInProgress;
    // Corrida paga no app já não esconde as paradas: a parada é cobrada na hora
    // (cartão/MB Way) e só entra quando o pagamento confirma.
    if (stops.isEmpty && !canManage) {
      return const SizedBox.shrink();
    }

    final feePerStopEur =
        (stops.isNotEmpty ? stops.first.feeCents : stopFeeCents) / 100;
    final canAdd = canManage && stops.length < maxStops;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: Spacing.lg),
        Row(
          children: [
            const Icon(Icons.add_location_alt_outlined,
                size: 18, color: AppColors.primary),
            const SizedBox(width: Spacing.sm),
            const Expanded(
              child: Text('Paradas',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary)),
            ),
            Text('${stops.length}/$maxStops',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Passa por outro sítio a caminho — €${feePerStopEur.toStringAsFixed(2)} por parada. '
          'A parada não está incluída no plano.'
          '${ride.isPaidOnline ? ' Pagas a parada na hora.' : ' Pagas ao motorista no fim.'}',
          style: const TextStyle(color: AppColors.textSubtle, fontSize: 11.5),
        ),
        for (final s in stops) ...[
          const SizedBox(height: Spacing.sm),
          _StopRow(
            stop: s,
            timerSeconds: stopTimerSeconds,
            onRemove: () => onRemoveStop(s),
          ),
        ],
        const SizedBox(height: Spacing.sm),
        if (canAdd)
          OutlinedButton.icon(
            onPressed: addingStop ? null : onAddStop,
            icon: addingStop
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: Text(addingStop ? 'A adicionar…' : 'Adicionar parada'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.md)),
            ),
          )
        else if (stops.length >= maxStops)
          Text('Máximo de $maxStops paradas atingido.',
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12)),
        if (stops.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: Text('Paradas (${stops.length} × €${feePerStopEur.toStringAsFixed(2)})',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ),
              Text('€${(ride.extraStopsFeeCents / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontSize: 13)),
            ],
          ),
        ],
      ],
    );
  }
}

class _TerminalView extends StatelessWidget {
  const _TerminalView({
    required this.icon,
    required this.color,
    required this.title,
    required this.onClose,
  });
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'A tua corrida'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: color),
              const SizedBox(height: Spacing.lg),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: Spacing.xl),
              BoraPrimaryButton(
                  label: 'Fechar', icon: Icons.check, onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}

/// [Feature 1] Uma linha de parada no painel do cliente. Quando o motorista já
/// chegou à parada mostra o countdown da espera gratuita (informativo).
class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.timerSeconds,
    required this.onRemove,
  });

  final TvdeRideStop stop;
  final int timerSeconds;
  final VoidCallback onRemove;

  String? _countdown() {
    final r = stop.reachedAt;
    if (r == null) return null;
    final end = r.add(Duration(seconds: timerSeconds));
    final left = end.difference(DateTime.now());
    if (left.isNegative) return null;
    final m = left.inMinutes;
    final s = left.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final reached = stop.reached;
    final cd = _countdown();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text('${stop.seq}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              stop.label ?? 'Parada ${stop.seq}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          if (reached) ...[
            Icon(cd != null ? Icons.timer_outlined : Icons.check_circle,
                size: 15, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              cd != null ? 'Espera $cd' : 'Espera concluída',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary),
            ),
          ] else
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
              tooltip: 'Remover parada',
            ),
        ],
      ),
    );
  }
}

/// Resultado da folha de confirmação de parada paga.
class _StopPayConfirm {
  const _StopPayConfirm({required this.phone});

  /// 9 dígitos, só preenchido quando o método é MB Way.
  final String phone;
}

/// Confirmação do pagamento de uma parada extra numa corrida paga online.
/// Cartão → só confirma; MB Way → pede o número (obrigatório, 9 dígitos).
class _StopPayConfirmSheet extends StatefulWidget {
  const _StopPayConfirmSheet({
    required this.label,
    required this.feeCents,
    required this.method,
    required this.initialPhone,
  });

  final String label;
  final int feeCents;
  final String method; // 'card' | 'mbway'
  final String initialPhone;

  @override
  State<_StopPayConfirmSheet> createState() => _StopPayConfirmSheetState();
}

class _StopPayConfirmSheetState extends State<_StopPayConfirmSheet> {
  late final TextEditingController _phone;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    // Pré-preenche com o telefone do perfil (só os 9 dígitos nacionais).
    final digits = widget.initialPhone.replaceAll(RegExp(r'\D'), '');
    _phone = TextEditingController(
        text: digits.length >= 9 ? digits.substring(digits.length - 9) : '');
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _confirm() {
    if (widget.method == 'mbway') {
      final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 9) {
        setState(() => _phoneError = 'Indica um número com 9 dígitos.');
        return;
      }
      Navigator.pop(context, _StopPayConfirm(phone: digits));
      return;
    }
    Navigator.pop(context, const _StopPayConfirm(phone: ''));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = media.viewInsets.bottom; // teclado
    final safeBottom = media.padding.bottom; // barra de navegação do sistema
    final eur = '€${(widget.feeCents / 100).toStringAsFixed(2)}';
    final isMbway = widget.method == 'mbway';
    // [Ronda 2] Mesmo defeito da folha do pedido: `useSafeArea` só protege o
    // topo (aplica `SafeArea(bottom: false)`) e `viewInsets` só conta o teclado
    // — sem `padding.bottom` o botão fica atrás da barra do sistema.
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
              const Icon(Icons.add_location_alt_outlined,
                  color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text('Parada extra — $eur',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                tooltip: 'Fechar',
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(widget.label,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.md),
          Text(
            isMbway
                ? 'Esta corrida foi paga por MB Way. A parada é cobrada agora — '
                    'só é adicionada depois de confirmares no MB Way.'
                : 'Esta corrida foi paga no cartão. A parada é cobrada agora — '
                    'só é adicionada depois de o pagamento passar.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (isMbway) ...[
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('tvde_stop_mbway_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Número MBWay',
                hintText: '9XXXXXXXX',
                prefixText: '+351 ',
                errorText: _phoneError,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          BoraAccentButton(
            key: const Key('tvde_stop_pay_confirm'),
            label: 'Pagar $eur e adicionar',
            onPressed: _confirm,
          ),
        ],
      ),
    );
  }
}

/// Resultado da folha de pesquisa de parada.
class _PickedStop {
  const _PickedStop({required this.label, required this.lat, required this.lng});
  final String label;
  final double lat;
  final double lng;
}

/// [Feature 1] Folha para o cliente escolher a morada da nova parada (reusa o
/// mesmo AddressAutocompleteField do ecrã de pedido).
class _AddStopSheet extends StatefulWidget {
  const _AddStopSheet();

  @override
  State<_AddStopSheet> createState() => _AddStopSheetState();
}

class _AddStopSheetState extends State<_AddStopSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    // O overlay de sugestões do AddressAutocompleteField abre SEMPRE para baixo
    // (maxHeight 260) e o "campo sobe ao focar" depende de Scrollable.ensureVisible
    // — que é NO-OP sem um Scrollable ancestral. Antes, esta folha usava
    // Column(mainAxisSize.min) sem scroll: o ensureVisible não engatava, o campo
    // ficava colado ao teclado e a lista saía cortada/não-clicável. Fix igual ao
    // ecrã de pedido: folha com altura fixa generosa + SingleChildScrollView, para
    // o campo poder subir ao topo e deixar os 260px da lista acima do teclado.
    // O 0.7 fixo cortava a lista em ecrãs pequenos/teclados altos (0.7*h + teclado
    // > h); preencher exatamente o espaço acima do teclado garante que os 260px
    // da lista ficam SEMPRE visíveis/clicáveis.
    final maxSheet = media.size.height - bottomInset - media.padding.top;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: maxSheet,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_location_alt_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: Spacing.sm),
                  const Expanded(
                    child: Text('Adicionar parada',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              const Text(
                  'Escolhe onde o motorista deve passar a caminho do destino.',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: Spacing.md),
              AddressAutocompleteField(
                controller: _controller,
                labelText: 'Morada da parada',
                onSelected: (address, coords) {
                  if (coords == null) return;
                  Navigator.pop(
                    context,
                    _PickedStop(
                        label: address,
                        lat: coords.latitude,
                        lng: coords.longitude),
                  );
                },
              ),
              // Espaço abaixo do campo: dá extensão de scroll para o ensureVisible
              // puxar o campo ao topo e deixar os 260px da lista visíveis.
              const SizedBox(height: 280),
            ],
          ),
        ),
      ),
    );
  }
}
