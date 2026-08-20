import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/driver_model.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/driver_location_ping_service.dart';
import '../../../services/heartbeat_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/incoming_job_alert.dart';
import '../../../models/order_model.dart';
import '../../../services/permission_gate_service.dart';
import '../../../services/push_token_service.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/order_store.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../widgets/background_location_disclosure.dart';
import '../../../widgets/bora_support_sheet.dart';
import '../../../services/navigation_service.dart';
import '../../../widgets/tvde/tvde_reservation_offer_card.dart';
import '../../driver_home_screen.dart';
import '../../driver_earnings_screen.dart';
import 'tvde_driver_agenda_screen.dart';
import 'tvde_offer_screen.dart';
import 'tvde_ride_active_screen.dart';

/// TVDE — Bora Motorista. Home do motorista de passageiros (modo escondido,
/// roteado a partir do _RootNavigator quando vehicle_type='carro_passageiros').
/// Reusa o MESMO mecanismo de is_online + heartbeat (90s) + GPS do delivery —
/// não cria heartbeat novo. 100% isolado do dispatch de entregas.
class TvdeDriverHomeScreen extends StatefulWidget {
  const TvdeDriverHomeScreen({super.key});

  @override
  State<TvdeDriverHomeScreen> createState() => _TvdeDriverHomeScreenState();
}

class _TvdeDriverHomeScreenState extends State<TvdeDriverHomeScreen>
    with WidgetsBindingObserver {
  final HeartbeatService _heartbeat = HeartbeatService();
  StreamSubscription<Position>? _gps;
  Position? _lastPos;
  Timer? _offerPoll;
  bool _offerOpen = false;
  // Parte 1 (rodada 2) — dedup do alerta sonoro de oferta de entrega/favor que
  // chega enquanto o motorista está no mapa TVDE (era silenciosa — ordem 9016).
  final Set<String> _alertedDeliveryOfferIds = <String>{};
  bool _activeOpen = false;
  bool _deliveryOpen = false;

  // F/M4 — tempo online desta sessão (relógio no cartão). Arranca ao ficar
  // online, para ao ficar offline. (Agregação diária real = backend, follow-up.)
  DateTime? _onlineSince;
  Timer? _onlineTicker;

  gmaps.GoogleMapController? _mapController;
  gmaps.LatLng? _lastCameraTarget;

  // [Item G] Paridade com o mapa do estafeta: seta verde rotativa (bearing) em
  // vez de pino grande; bússola + botão centralizar. Fallback à bolinha nativa
  // enquanto o ícone não carrega (e sempre na Web, onde fromBytes não existe).
  gmaps.BitmapDescriptor? _driverArrowIcon;
  double _bearing = 0;

  /// Centro por omissão (Guarda) enquanto não há 1º fix de GPS — garante que o
  /// mapa nunca aparece vazio/branco: renderiza sempre com câmara válida.
  static const gmaps.LatLng _guardaCenter = gmaps.LatLng(40.5373, -7.2657);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDriverArrowIcon();
    // [TVDE P0] Push de oferta força reload do store → a tela de oferta aparece
    // mesmo que o realtime tenha caído (fallback triplo: push → realtime → poll).
    NotificationService.tvdeOfferReload = _reloadOffer;
    // [Reserva agendada 2026-08-19] Push de reserva força reload da agenda, e
    // o botão "A caminho" da notificação dos 10 min cai aqui.
    NotificationService.tvdeReservationReload = _reloadAgenda;
    NotificationService.tvdeReservationReadyTap = _onReservationReadyFromPush;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Reflete admin approve/reject pós-login sem relogin (espelha o
      // DriverHomeScreen de entrega: refreshApprovalStatus → notifyListeners →
      // o gate em build() reage via context.watch<AuthStore>()).
      await context.read<AuthStore>().refreshApprovalStatus();
      if (!mounted) return;
      await context.read<TvdeDriverStore>().start();
      if (!mounted) return;
      // Dual-driver: espelha o work_mode carregado no modelo local do delivery
      // (supportsService) — a fonte de verdade do matching é o backend.
      context.read<DriverStore>().currentDriver?.workMode =
          context.read<TvdeDriverStore>().workMode;
      // Se o motorista já estava Online (re-abertura), retoma heartbeat+GPS.
      final isOnline =
          context.read<DriverStore>().currentDriver?.isOnline ?? false;
      if (isOnline) {
        unawaited(_heartbeat.start());
        // F4B (2026-08-16): renovar o token FCM sempre que se retoma online —
        // motorista aprovado online sem token era invisível ao push.
        unawaited(PushTokenService.registerForRole('driver'));
        unawaited(_startGps());
        _startOfferPoll();
        _startOnlineClock();
      }
      // F4B: presença honesta — escuta as falhas de heartbeat para o banner.
      _heartbeat.serverAck.addListener(_onServerAckChanged);
      _syncNav();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tocar na notificação de oferta traz o app à frente → re-lê oferta/corrida
    // ativa (a par do realtime) para o ecrã de oferta aparecer.
    if (state == AppLifecycleState.resumed && mounted) {
      // Apanha admin approve/reject enquanto o app esteve em background — o
      // motorista volta ao app já aprovado e o gate atualiza sem relogin.
      unawaited(context.read<AuthStore>().refreshApprovalStatus());
      final driverStore = context.read<DriverStore>();
      if (driverStore.currentDriver?.isOnline == true) {
        unawaited(_heartbeat.start());
      }
      context.read<TvdeDriverStore>().loadCurrent().then((_) {
        if (mounted) _syncNav();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (NotificationService.tvdeOfferReload == _reloadOffer) {
      NotificationService.tvdeOfferReload = null;
    }
    if (NotificationService.tvdeReservationReload == _reloadAgenda) {
      NotificationService.tvdeReservationReload = null;
    }
    if (NotificationService.tvdeReservationReadyTap ==
        _onReservationReadyFromPush) {
      NotificationService.tvdeReservationReadyTap = null;
    }
    _heartbeat.serverAck.removeListener(_onServerAckChanged);
    _heartbeat.stop();
    _gps?.cancel();
    _offerPoll?.cancel();
    _onlineTicker?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Recarrega a oferta/corrida do servidor e reavalia a navegação. Ligado ao
  /// push `new_tvde_ride_offer` (chegada + tap) via NotificationService.
  void _reloadOffer() {
    if (!mounted) return;
    context.read<TvdeDriverStore>().loadCurrent().then((_) {
      if (mounted) _syncNav();
    });
  }

  // ══ RESERVA AGENDADA (2026-08-19) ═══════════════════════════════════════

  void _reloadAgenda() {
    if (!mounted) return;
    context.read<TvdeDriverStore>().loadAgenda();
  }

  /// Botão "A caminho" da notificação persistente dos 10 minutos.
  ///
  /// Confirma no servidor e abre já a navegação para a recolha. A RPC também é
  /// chamada headless quando a notificação é tocada com a app fechada — é
  /// idempotente, por isso as duas chamadas convivem sem problema.
  Future<void> _onReservationReadyFromPush(String rideId) async {
    if (!mounted) return;
    final store = context.read<TvdeDriverStore>();
    final ok = await store.reservationReady(rideId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Confirmado. Vai a caminho da recolha.'
          : 'Não consegui confirmar. Abre a agenda e tenta outra vez.'),
    ));
    if (!ok) {
      _openAgenda();
      return;
    }
    // Abre a navegação para a morada de recolha do cliente.
    //
    // [Fix 2026-08-20] A reserva activada NÃO está na agenda: o sweep, ao
    // activá-la, põe `status='motorista_atribuido'` e a consulta da agenda
    // pede `status='agendada'`. Como este push só é enviado depois de
    // activada, procurar só na agenda falhava SEMPRE e a navegação nunca
    // abria. Ordem de procura: agenda → corrida activa → servidor.
    TvdeRide? r;
    for (final x in store.agenda) {
      if (x.id == rideId) {
        r = x;
        break;
      }
    }
    if (r == null && store.activeRide?.id == rideId) {
      r = store.activeRide;
    }
    r ??= await store.fetchRideById(rideId);
    if (r == null || !mounted) {
      _openAgenda();
      return;
    }
    await NavigationService.openNavigationOptions(
      context,
      LatLng(r.originLat, r.originLng),
    );
  }

  void _openAgenda() {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TvdeDriverAgendaScreen()),
    );
  }

  Future<void> _aceitarReserva(String rideId) async {
    final store = context.read<TvdeDriverStore>();
    try {
      await store.acceptReservation(rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reserva aceite. Fica na tua agenda — avisamos-te '
            'perto da hora.'),
      ));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('offer_no_longer_valid')
          ? 'Essa reserva já não está disponível.'
          : 'Não consegui aceitar a reserva. Tenta outra vez.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _recusarReserva(String rideId) async {
    try {
      await context.read<TvdeDriverStore>().rejectReservation(rideId);
    } catch (_) {/* a rotação do servidor segue de qualquer forma */}
  }

  /// Rede de segurança: enquanto online e sem oferta/corrida, relê a cada 10s.
  /// Garante a oferta mesmo que push E realtime falhem (Uber-grade). Barato —
  /// só corre quando online e ocioso.
  void _startOfferPoll() {
    _offerPoll?.cancel();
    _offerPoll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final driverStore = context.read<DriverStore>();
      if (driverStore.currentDriver?.isOnline != true) return;
      final tvde = context.read<TvdeDriverStore>();
      // Elegível para oferta: livre, OU em viagem 'em_andamento' sem fila
      // (back-to-back — o tier 2 do matching só oferece nesse estado).
      final canReceive = tvde.offeredRide == null &&
          (tvde.activeRide == null ||
              (tvde.activeRide!.isInProgress && tvde.queuedRide == null));
      if (!canReceive) return;
      tvde.loadCurrent().then((_) {
        if (mounted) _syncNav();
      });
    });
  }

  void _stopOfferPoll() {
    _offerPoll?.cancel();
    _offerPoll = null;
  }

  /// Segue a posição do motorista com a câmara (best-effort). Só anima quando o
  /// alvo muda de facto — evita animações a cada rebuild.
  void _followCamera(gmaps.LatLng target) {
    final c = _mapController;
    if (c == null) return;
    final prev = _lastCameraTarget;
    if (prev != null &&
        (prev.latitude - target.latitude).abs() < 0.0002 &&
        (prev.longitude - target.longitude).abs() < 0.0002) {
      return;
    }
    _lastCameraTarget = target;
    c.animateCamera(gmaps.CameraUpdate.newLatLng(target));
  }

  /// [Item G] Constrói a seta verde do motorista (igual ao mapa do estafeta).
  /// Off-Web apenas — BitmapDescriptor.bytes não existe na Web; aí cai na
  /// bolinha azul nativa (myLocationEnabled).
  Future<void> _loadDriverArrowIcon() async {
    if (kIsWeb) return;
    try {
      final bytes = await _createArrowIcon();
      if (!mounted) return;
      setState(() => _driverArrowIcon = gmaps.BitmapDescriptor.bytes(bytes));
    } catch (_) {
      // Fallback silencioso — o marker fica null e usa-se a bolinha nativa.
    }
  }

  Future<Uint8List> _createArrowIcon() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 56.0;
    final paint = Paint()..color = AppColors.primary; // verde Bora
    final path = ui.Path()
      ..moveTo(size / 2, 0)
      ..lineTo(size, size)
      ..lineTo(size / 2, size * 0.7)
      ..lineTo(0, size)
      ..close();
    canvas.drawPath(path, paint);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawPath(path, stroke);
    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  // ── Navegação reativa para oferta / corrida ativa ──────────────────────────
  void _syncNav() {
    if (!mounted) return;
    final store = context.read<TvdeDriverStore>();
    final active = store.activeRide;
    if (active != null && active.isLive && !_activeOpen) {
      _activeOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => const TvdeRideActiveScreen()))
          .then((_) {
        _activeOpen = false;
        // Corrida terminou → atualiza os ganhos do dia.
        if (mounted) context.read<TvdeDriverStore>().loadTodayEarnings();
      });
      return;
    }
    final offer = store.offeredRide;
    if (offer != null && !_offerOpen && !_activeOpen) {
      _offerOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => TvdeOfferScreen(ride: offer)))
          .then((_) => _offerOpen = false);
    }
  }

  /// [Item F] Auto-abre o fluxo de estafeta APENAS para RETOMAR uma entrega já
  /// ativa (myOrders) — ex.: reabrir a app a meio de uma entrega. As ofertas
  /// NOVAS (availableOrders) já NÃO teleportam: aparecem como overlay sobre o
  /// mapa TVDE (tela única). Ao terminar (back), volta ao modo corridas.
  void _maybeResumeDeliveryFlow() {
    if (!mounted || _deliveryOpen || _activeOpen || _offerOpen) return;
    final tvde = context.read<TvdeDriverStore>();
    if (tvde.ridesOnly ||
        tvde.activeRide != null ||
        tvde.queuedRide != null) {
      return;
    }
    if (context.read<OrderStore>().myOrders.isEmpty) return;
    _openDeliveryFlow();
  }

  void _openDeliveryFlow() {
    if (_deliveryOpen) return;
    _deliveryOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DriverHomeScreen()))
        .then((_) => _deliveryOpen = false);
  }

  /// Parte 1 (rodada 2) — oferta de entrega/favor a chegar enquanto o motorista
  /// está no mapa TVDE aparece como overlay MAS era SILENCIOSA (ordem 9016).
  /// Juntamos o alerta sonoro/heads-up (canal urgente). Tipo próprio para não
  /// colidir com o roteamento do gate do estafeta. Dedup + dispensa ao sair.
  void _maybeAlertDeliveryOffers(List<OrderModel> offers) {
    final currentIds = <String>{};
    for (final o in offers) {
      currentIds.add(o.id);
    }
    for (final id in _alertedDeliveryOfferIds.toList()) {
      if (!currentIds.contains(id)) {
        IncomingJobAlert.dismiss(id);
        _alertedDeliveryOfferIds.remove(id);
      }
    }
    for (final o in offers) {
      if (!_alertedDeliveryOfferIds.add(o.id)) continue;
      IncomingJobAlert.show(
        id: o.id,
        type: 'tvde_incoming_delivery',
        title: '🛵 Nova entrega/favor!',
        body: 'Toca para abrir e responder.',
        extraPayload: {'orderId': o.id},
      );
    }
  }

  /// Ganhos UNIFICADOS (HOJE/ESTA SEMANA/SEMANA PASSADA/ÚLTIMO ACERTO + extrato
  /// TVDE/entregas/tokens + settlement), da RPC driver_earnings_summary. O
  /// motorista TVDE passa a ver o quadro completo, não só o histórico de corridas.
  void _openEarnings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const DriverEarningsScreen()));
  }

  /// F — suporte (reusa a folha de suporte do delivery: Bora IA + WhatsApp + Email).
  void _openSupport() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BoraSupportSheet(),
    );
  }

  // F/M4 — relógio de tempo online (sessão).
  void _startOnlineClock() {
    _onlineSince ??= DateTime.now();
    _onlineTicker ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopOnlineClock() {
    _onlineTicker?.cancel();
    _onlineTicker = null;
    _onlineSince = null;
  }

  String? _onlineElapsedLabel() {
    final since = _onlineSince;
    if (since == null) return null;
    final d = DateTime.now().difference(since);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  // ── Online toggle (reuso DriverStore + heartbeat + GPS) ────────────────────
  Future<void> _toggleOnline(bool value) async {
    final driverStore = context.read<DriverStore>();
    final id = driverStore.currentDriverId;
    // Declaração em destaque (Google Play) de LOCALIZAÇÃO EM SEGUNDO PLANO —
    // antes de ficar Online (o GPS transmite enquanto Online + app minimizada).
    if (value && !await BackgroundLocationDisclosure.ensureAccepted(context)) {
      return; // Recusou — não fica Online.
    }
    if (!mounted) return;
    final ok = driverStore.toggleAvailability(id, value);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conclui a corrida atual antes de ficar offline.')));
      }
      return;
    }
    if (value) {
      // [A] 2026-06-30 — gate MÍNIMO partilhado com o estafeta. Antes o TVDE
      // não tinha gate nenhum. Garante a notificação persistente (best-effort)
      // e oferece o overlay no máximo uma vez. NUNCA bloqueia ir online — o
      // toggleAvailability acima já passou; overlay é só um bónus.
      await PermissionGateService.ensureMinimumOnlinePermissions(context);
      if (!mounted) return;
      unawaited(OverlayPermissionGate.maybeOfferOnce(context));
      unawaited(_heartbeat.start());
      // F4B (2026-08-16): registar/renovar o token FCM SEMPRE ao ficar online
      // (regra do Danilo). Idempotente — o PushTokenService deduplica.
      unawaited(PushTokenService.registerForRole('driver'));
      await _startGps();
      _startOfferPoll();
      _startOnlineClock();
    } else {
      unawaited(_heartbeat.stop());
      await _gps?.cancel();
      _gps = null;
      _stopOfferPoll();
      _stopOnlineClock();
      await _goOfflinePing();
    }
  }

  Future<void> _startGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('GPS desativado. Ative a localização para receber corridas.'),
          duration: Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Ativar',
            onPressed: Geolocator.openLocationSettings,
          ),
        ));
      }
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    // Ping imediato → aparece já uma linha fresca em driver_locations (fonte do
    // matching TVDE) sem esperar o 1º fix do stream.
    try {
      final first = await Geolocator.getCurrentPosition();
      _lastPos = first;
      await DriverLocationPingService.instance.ping(
        latitude: first.latitude,
        longitude: first.longitude,
        heading: first.heading.isFinite ? first.heading : null,
        speedKmh: first.speed.isFinite ? first.speed * 3.6 : null,
        isOnline: true,
      );
    } catch (_) {/* o stream cobre o ping seguinte */}

    await _gps?.cancel();
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
      ),
    ).listen((pos) {
      if (!mounted) return;
      // [Item G] bearing (direção de marcha) a partir do delta de posição —
      // roda a seta como no mapa do estafeta. Só quando andou o suficiente para
      // não amplificar ruído de GPS em rotação.
      final prev = _lastPos;
      _lastPos = pos;
      if (prev != null) {
        final moved = Geolocator.distanceBetween(
            prev.latitude, prev.longitude, pos.latitude, pos.longitude);
        if (moved >= 5) {
          var b = Geolocator.bearingBetween(
              prev.latitude, prev.longitude, pos.latitude, pos.longitude);
          if (b < 0) b += 360;
          _bearing = b;
        }
      }
      final store = context.read<DriverStore>();
      store.updateDriverLocation(
          store.currentDriverId, LatLng(pos.latitude, pos.longitude));
      // Alimenta driver_locations por user_id via RPC partilhada (throttle 45s).
      // É a fonte que o tvde_offer_to_next lê para elegibilidade.
      DriverLocationPingService.instance.ping(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading.isFinite ? pos.heading : null,
        speedKmh: pos.speed.isFinite ? pos.speed * 3.6 : null,
        isOnline: true,
      );
    }, onError: (Object e) {
      // GPS desligado a meio do stream emite LocationServiceDisabledException.
      // Sem este handler, o erro fica por tratar e rebenta o app.
      if (!mounted) return;
      if (e is LocationServiceDisabledException) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS desativado. Ative a localização para receber corridas.'),
            duration: Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Ativar',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
      }
    });
  }

  /// Marca driver_locations.is_online=false (por user_id) ao ficar offline/logout
  /// — sai do matching de imediato, sem esperar a janela de frescura. Reusa a RPC
  /// partilhada driver_update_location (apenas CHAMADA, não alterada).
  Future<void> _goOfflinePing() async {
    final pos = _lastPos;
    if (pos == null) return; // sem fix prévio: a frescura (janela) já exclui
    try {
      await Supabase.instance.client.rpc('driver_update_location', params: {
        'p_latitude': pos.latitude,
        'p_longitude': pos.longitude,
        'p_is_online': false,
      });
    } catch (_) {/* best-effort */}
  }

  /// F4B (2026-08-16): presença HONESTA. 3 heartbeats falhados (~90s) = o
  /// servidor já nos marcou offline (expire_stale_driver_presence corre a 90s)
  /// — proibido verdinho enganoso: banner vermelho + reconectar.
  void _onServerAckChanged() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!_heartbeat.serverAck.value) {
      messenger.showMaterialBanner(MaterialBanner(
        backgroundColor: Colors.red.shade700,
        content: const Text(
          'Sem ligação ao servidor — podes não estar a receber corridas.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => _heartbeat.pingNow(),
            child:
                const Text('TENTAR JÁ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ));
    } else {
      messenger.hideCurrentMaterialBanner();
    }
  }

  void _logout() {
    _heartbeat.stop();
    _gps?.cancel();
    unawaited(_goOfflinePing());
    context.read<AuthStore>().logout();
  }

  // ── Preferências de trabalho (só corridas vs tudo) ─────────────────────────
  void _openWorkModeSheet() {
    final mode = context.read<TvdeDriverStore>().workMode;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
              child: Text('O que queres aceitar?',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            RadioListTile<String>(
              value: 'rides_only',
              groupValue: mode,
              activeColor: AppColors.primary,
              title: const Text('Só corridas de passageiros'),
              subtitle: const Text('Recebes apenas viagens Bora Motorista.'),
              onChanged: (v) => _applyWorkMode(ctx, v!),
            ),
            RadioListTile<String>(
              value: 'everything',
              groupValue: mode,
              activeColor: AppColors.primary,
              title: const Text('Corridas + entregas (tudo)'),
              subtitle: const Text(
                  'Corridas + entregas de restaurante, supermercado e favores.'),
              onChanged: (v) => _applyWorkMode(ctx, v!),
            ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _applyWorkMode(BuildContext sheetCtx, String mode) async {
    Navigator.pop(sheetCtx);
    try {
      await context.read<TvdeDriverStore>().setWorkMode(mode);
      if (!mounted) return;
      // Espelha no modelo local do delivery: supportsService() passa a aceitar
      // entregas quando 'everything' (dual-driver). Fonte de verdade = backend.
      context.read<DriverStore>().currentDriver?.workMode = mode;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mode == 'rides_only'
              ? 'Preferência guardada: só corridas.'
              : 'Preferência guardada: tudo.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível guardar a preferência.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dispara a navegação reativa sempre que o store muda.
    context.watch<TvdeDriverStore>();
    // [Item F] Ofertas de entrega/favor (OrderStore) aparecem como overlay SOBRE
    // este mapa (tela única). O auto-open fica só para retomar entrega ativa.
    final deliveryOffers = context.watch<OrderStore>().availableOrders;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncNav();
      _maybeResumeDeliveryFlow();
      _maybeAlertDeliveryOffers(deliveryOffers);
    });

    final status = context.watch<AuthStore>().currentDriverStatus;
    if (status != DriverStatus.approved) {
      return _GateScreen(status: status, onLogout: _logout);
    }

    final isOnline =
        context.select<DriverStore, bool>((d) => d.currentDriver?.isOnline ?? false);
    final LatLng? locLl =
        context.select<DriverStore, LatLng?>((d) => d.currentDriver?.location);
    final gmaps.LatLng? mePos =
        locLl == null ? null : gmaps.LatLng(locLl.latitude, locLl.longitude);
    // [Perf] Este ecrã fica MONTADO por baixo quando a corrida ativa é aberta
    // com Navigator.push. Continuar a animar a câmara de um mapa invisível é
    // trabalho puro no platform channel e roubava frames ao mapa que está à
    // frente. Só segue a câmara quando esta rota é a de cima.
    // [Reserva agendada] Oferta antecipada pendente para este motorista.
    final reservationOffer =
        context.watch<TvdeDriverStore>().reservationOffer;
    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (mePos != null && isTopRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followCamera(mePos));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Bora Motorista'),
        actions: [
          // [Item F] Removido o atalho separado de "Entregas" — as ofertas de
          // entrega/favor agora aparecem como overlay no próprio mapa (tela única).
          // [Reserva agendada 2026-08-19] A AGENDA — as corridas marcadas dele.
          // Badge com o número para ele ver de relance que tem trabalho hoje.
          IconButton(
            tooltip: 'Agenda',
            onPressed: _openAgenda,
            icon: Builder(builder: (_) {
              final n = context.watch<TvdeDriverStore>().agenda.length;
              final icone = const Icon(Icons.event_note);
              if (n == 0) return icone;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  icone,
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$n',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          IconButton(
            tooltip: 'Ganhos',
            onPressed: _openEarnings,
            icon: const Icon(Icons.bar_chart),
          ),
          IconButton(
            tooltip: 'Preferências',
            onPressed: _openWorkModeSheet,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Suporte',
            onPressed: _openSupport,
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      // Estilo Uber Driver: mapa em tela cheia com a posição própria + cartão de
      // estado/toggle flutuante. O cartão vive num Stack por CIMA do mapa, logo
      // renderiza SEMPRE (mesmo que a platform view do GoogleMap demore) — é o
      // fallback defensivo contra tela sem controlo.
      body: Stack(
        children: [
          gmaps.GoogleMap(
            initialCameraPosition: gmaps.CameraPosition(
              target: mePos ?? _guardaCenter,
              zoom: 14.5,
            ),
            myLocationEnabled: _driverArrowIcon == null,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              if (mePos != null) {
                _lastCameraTarget = mePos;
                c.moveCamera(gmaps.CameraUpdate.newLatLng(mePos));
              }
            },
            markers: (mePos == null || _driverArrowIcon == null)
                ? <gmaps.Marker>{}
                : {
                    // [Item G] Seta verde rotativa (paridade com o estafeta) —
                    // sem o pino azul grande. Enquanto o ícone não carrega, a
                    // bolinha nativa (myLocationEnabled) marca a posição.
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('me'),
                      position: mePos,
                      rotation: _bearing,
                      icon: _driverArrowIcon!,
                      anchor: const Offset(0.5, 0.5),
                      flat: true,
                    ),
                  },
          ),
          if (mePos == null) const _LocatingBanner(),
          // [Reserva agendada 2026-08-19] Oferta ANTECIPADA de reserva, sobre
          // o mapa. Não rouba o ecrã como a oferta imediata (que é a corrida
          // a começar já) — aqui há tempo, o prazo vem do servidor.
          if (reservationOffer != null)
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: TvdeReservationOfferCard(
                ride: reservationOffer,
                busy: context.watch<TvdeDriverStore>().busy,
                onAccept: () => _aceitarReserva(reservationOffer.id),
                onReject: () => _recusarReserva(reservationOffer.id),
              ),
            ),
          // [Item G] Botão centralizar (paridade com o estafeta) — recentra na
          // posição do motorista e volta ao zoom de navegação.
          if (mePos != null)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).size.height * 0.55,
              child: FloatingActionButton.small(
                heroTag: 'tvde_map_recenter',
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                onPressed: () {
                  final c = _mapController;
                  if (c == null) return;
                  _lastCameraTarget = mePos;
                  c.animateCamera(
                      gmaps.CameraUpdate.newLatLngZoom(mePos, 15.5));
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: _OnlinePanel(
                isOnline: isOnline,
                todayEarnCents:
                    context.read<TvdeDriverStore>().todayEarnCents,
                avgRating: context
                    .select<DriverStore, double?>((d) => d.currentDriver?.avgRating),
                ratingsCount: context.select<DriverStore, int>(
                    (d) => d.currentDriver?.ratingsCount ?? 0),
                onlineLabel: isOnline ? _onlineElapsedLabel() : null,
                onChanged: _toggleOnline,
              ),
            ),
          ),
          // [Item F] Ofertas de entrega/favor SOBRE o mapa TVDE (tela única) —
          // sem ícone separado nem teleporte automático; toca para aceitar no
          // fluxo de estafeta provado (com contagem + som).
          if (deliveryOffers.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _openDeliveryFlow,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.delivery_dining, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                deliveryOffers.length == 1
                                    ? 'Nova oferta de entrega/favor'
                                    : '${deliveryOffers.length} ofertas de entrega/favor',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
                              ),
                              const Text('Toca para ver e aceitar',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cartão flutuante de estado + toggle online/offline (estilo Uber Driver).
class _OnlinePanel extends StatelessWidget {
  const _OnlinePanel({
    required this.isOnline,
    required this.todayEarnCents,
    required this.avgRating,
    required this.ratingsCount,
    required this.onlineLabel,
    required this.onChanged,
  });
  final bool isOnline;
  final int todayEarnCents;
  final double? avgRating;
  final int ratingsCount;
  final String? onlineLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(Spacing.md),
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
                Text('€${(todayEarnCents / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ],
            ),
          ),
          // F/M14 + M4 — avaliação média recebida + tempo online do dia (sessão).
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              const Icon(Icons.star, size: 16, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                (avgRating != null && avgRating! > 0)
                    ? '${avgRating!.toStringAsFixed(1)} · $ratingsCount avaliações'
                    : 'Sem avaliações ainda',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (onlineLabel != null) ...[
                const Icon(Icons.timer_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text('Online há $onlineLabel',
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ],
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
          Icon(isOnline ? Icons.local_taxi : Icons.local_taxi_outlined,
              size: 32,
              color: isOnline ? AppColors.primary : AppColors.textSubtle),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isOnline ? 'Estás online' : 'Estás offline',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                Text(
                  isOnline
                      ? 'À espera de corridas de passageiros.'
                      : 'Fica online para receber corridas.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Switch(
            value: isOnline,
            activeColor: AppColors.primary,
            onChanged: onChanged,
          ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip "a localizar" no topo enquanto não há 1º fix de GPS.
class _LocatingBanner extends StatelessWidget {
  const _LocatingBanner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.all(Spacing.md),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Spacing.sm),
              Text('A obter a tua localização…',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ecrã de espera quando o motorista ainda não foi aprovado (ou foi rejeitado).
class _GateScreen extends StatelessWidget {
  const _GateScreen({required this.status, required this.onLogout});
  final DriverStatus status;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final rejected = status == DriverStatus.rejected;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(rejected ? Icons.cancel : Icons.hourglass_top,
                  size: 72,
                  color: rejected ? AppColors.error : AppColors.primary),
              const SizedBox(height: Spacing.lg),
              Text(
                rejected ? 'Candidatura rejeitada' : 'Candidatura em análise',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                rejected
                    ? 'A tua candidatura a motorista de passageiros foi rejeitada. Contacta o suporte.'
                    : 'Vamos rever a tua candidatura a motorista de passageiros. Avisamos-te assim que for aprovada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.xl),
              TextButton(onPressed: onLogout, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}
