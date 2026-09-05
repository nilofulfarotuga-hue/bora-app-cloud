import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../../services/tvde_arriving_notice.dart';
import '../../../services/tvde_eta_display.dart';
import '../../../stores/tvde_chat_store.dart';
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../utils/tvde_route_walk.dart';
import '../../../utils/tvde_sinal_motorista.dart';
import '../../../utils/tvde_stops_route.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/tvde/tvde_roundtrip_driver_notice.dart';
import '../../shared/tvde_chat_screen.dart';
import 'ride_mbway_waiting_dialog.dart';
import 'tvde_rate_screen.dart';

import '../../../l10n/tr.dart';

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
  int? _driverRatingsCount; // nº de avaliações (vem da RPC do cartão)
  Timer? _driverPoll;
  Timer? _animTimer;
  bool _navigatedToRate = false;

  // ── [TVDE 05/09 · 1A] Cartão do motorista pela RPC ────────────────────────
  // A RLS de `public.drivers` só deixa ler a própria linha (ou admin) — e bem:
  // essa tabela tem IBAN, NIF, morada e documento de identidade. O SELECT que
  // aqui estava devolvia SEMPRE vazio ao cliente e o erro morria num catch
  // mudo: nem carro no mapa, nem nome, nem matrícula, nem ETA. O cartão
  // PÚBLICO vem agora de `tvde_ride_driver_card` (SECURITY DEFINER), que só
  // responde ao cliente daquela corrida.
  int _driverPollSeconds = 5; // fallback; vem de tvde_driver_card_poll_seconds
  int _driverCardFails = 0;
  bool _driverCardDegraded = false; // ≥3 falhas → dizê-lo ao cliente

  /// Direção de marcha do carro (graus). Preferimos o `heading` do
  /// dispositivo; sem ele (ou parado) cai no `_bearing` calculado entre as
  /// duas últimas posições. Suavizado para o carrinho não tremer no mapa.
  double? _driverHeading;
  double? _driverSpeedKmh;

  // ── [TVDE 05/09 · 2C] Sinal velho tem de se ver ───────────────────────────
  // A RPC já devolvia `location_updated_at` e ninguém a lia: um motorista com
  // o GPS morto ficava igualzinho a um motorista parado no semáforo, e o
  // cliente não tinha como perceber a diferença. Agora: passados
  // `tvde_driver_stale_seconds` a animação pára e o carro esbate-se; passados
  // `tvde_driver_lost_seconds` deixa de se fingir que há posição fiável.
  /// Quando o motorista mandou a última posição (hora do SERVIDOR).
  DateTime? _driverFixAt;
  int _staleSeconds = 45; // fallback; vem de tvde_driver_stale_seconds
  int _lostSeconds = 180; // fallback; vem de tvde_driver_lost_seconds

  /// [PADRAO_BORA 3.13 · 05/09] Guarda LOCAL das acções deste ecrã (cancelar,
  /// pagar de novo, tentar de novo). Substitui o `busy` GLOBAL do `TvdeStore`,
  /// que dezenas de operações mexem — incluindo o poll do cartão do motorista,
  /// que corre de 4 em 4 segundos neste mesmo ecrã.
  bool _accaoEmCurso = false;

  Future<void> _comGuarda(Future<void> Function() accao) async {
    if (_accaoEmCurso) return;
    setState(() => _accaoEmCurso = true);
    try {
      await accao();
    } finally {
      // Reposto também em erro: um botão a rodar para sempre é o mesmo
      // defeito por outra porta.
      if (mounted) setState(() => _accaoEmCurso = false);
    }
  }

  /// Carrinho azul visto de cima (desenhado em código — não há asset).
  /// Null na Web: `BitmapDescriptor.bytes` não existe lá.
  BitmapDescriptor? _carIcon;

  /// [1B · 05/09] Pinos NUMERADOS das paradas, desenhados em código (o
  /// `BitmapDescriptor` da Google não sabe escrever números). Chave:
  /// `'<seq>|<jáAlcançada>'`. Vazio na Web — lá cai no marker nativo.
  final Map<String, BitmapDescriptor> _stopIcons = {};

  // ── [TVDE 05/09 · 2A/2B/2C] ETA ───────────────────────────────────────────
  /// ETA sem rota real (distância a direito ÷ velocidade média). Serve para
  /// mostrar sempre um número, mas não é fiável ao ponto de prometer chegada —
  /// por isso não dispara o aviso do 2C.
  bool _etaIsRough = false;

  /// Regra do Danilo: o número MOSTRADO é menor que o real. Fallbacks aqui,
  /// verdade em `platform_settings` (categoria `eta`).
  int _etaDiscountPct = kTvdeEtaClientDiscountPct;
  int _etaDiscountMaxMin = kTvdeEtaClientDiscountMaxMin;
  int _etaFloorMin = kTvdeEtaClientFloorMin;
  int _etaArrivingMin = 2; // tvde_eta_arriving_push_min

  /// Marca do aviso "está quase a chegar" — uma vez por corrida.
  String? _arrivingNotifiedRideId;

  /// [Item I] chat da corrida — ouvido para o badge de nao-lidas (lado cliente).
  TvdeChatStore? _chatStore;
  String? _chatRideId;

  /// [botoes-navbar-eta 31/08] Velocidade média do fallback do ETA — vem de
  /// `platform_settings.eta_avg_speed_kmh` (o Danilo afina no admin), nunca
  /// cravada. 28 é só o fallback de arranque/offline.
  int _etaSpeedKmh = 28;

  /// ETA da ROTA do motorista (a mesma polyline desenhada): duração devolvida
  /// pelo Directions + de onde/quando foi pedida. Enquanto fresca é a fonte
  /// do ETA; velha (>45 s ou carro >150 m do ponto do pedido) cai no fallback
  /// distância ÷ velocidade — o número nunca congela.
  double? _driverRouteEtaMin;
  DateTime? _driverRouteEtaAt;
  LatLng? _driverRouteEtaFrom;

  // ── B2 — rota real grossa recolha→destino (mesmo DirectionsService/chave). ──
  final DirectionsService _directions = DirectionsService();
  Set<Polyline> _routePolys = <Polyline>{};
  String? _routeKey;

  // ── [Bloco 5, 30/08] rota do MOTORISTA (→recolha antes de embarcar,
  // →destino em viagem), estilo Uber. Refaz-se quando a fase muda, quando
  // entra/sai uma parada [1B · 05/09], ou quando o carro se afasta ≥120 m do
  // ponto onde a rota foi traçada (poupa Directions).
  Set<Polyline> _driverRoutePolys = <Polyline>{};
  LatLng? _driverRouteFrom;
  String _driverRouteKey = '';

  /// [2A · 05/09] Os MESMOS pontos da linha acima, em `latlong2` — é sobre
  /// esta lista que o carro anda (`passosSobreRota`). Guardada à parte para
  /// não andar a desconverter a polilinha da Google a cada leitura de GPS.
  List<ll.LatLng> _driverRouteLL = const [];

  // ── Heading-up (paridade com o mapa do motorista) ─────────────────────────
  // Câmara estilo Waze: segue o carro com zoom/tilt de navegação e RODA
  // (bearing) conforme a direção de marcha, calculada pelo delta de posições
  // do poll (≥5 m para não amplificar ruído de GPS) — mesmo padrão do
  // tvde_driver_home_screen [Item G]. Valores espelham platform_settings
  // (tvde_nav_zoom / tvde_nav_tilt); leitura dinâmica pendente, como no
  // ecrã do motorista.
  static const double _kNavZoom = 17.5;
  static const double _kNavTilt = 45.0;

  // ── [2B · 05/09] Ritmo da animação do carro ───────────────────────────────
  // Os 12 passos históricos passam a ser o MÍNIMO, não o número fixo: quem
  // manda no tempo total é a velocidade real. Numa janela longa acrescentam-se
  // fotogramas (a ~80 ms cada, a cadência que já era suave) em vez de espaçar
  // os 12 — 12 passos em 4 segundos dariam três imagens por segundo.
  static const int _kAnimPassosBase = 12;
  static const double _kAnimMsPorPasso = 80;
  static const int _kAnimMinMs = 240;
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
    _restartDriverPoll();
    _loadCarIcon();
    _stopsTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _stopsTick++;
      if (_stopsTick % 5 == 0) _loadStops();
      // [2C] Sinal velho: parar a animação (um carro a deslizar com o GPS
      // morto é uma mentira em movimento) e repintar, porque o "há X" conta
      // sozinho — não chega nenhum evento para o atualizar.
      final velho = _sinalVelho;
      if (velho) _animTimer?.cancel();
      // repinta os countdowns de espera (só quando há paradas alcançadas)
      if (velho || _stops.any((s) => s.reached)) setState(() {});
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

  /// [05/09] O intervalo do poll deixa de estar cravado nos 5 s — vem de
  /// `tvde_driver_card_poll_seconds` (4 s hoje). Idempotente: cancela o timer
  /// anterior antes de abrir outro.
  void _restartDriverPoll() {
    _driverPoll?.cancel();
    final s = _driverPollSeconds < 1 ? 1 : _driverPollSeconds;
    _driverPoll = Timer.periodic(Duration(seconds: s), (_) => _pollDriver());
  }

  Future<void> _loadStopSettings() async {
    final store = context.read<TvdeStore>();
    final max = await store.getSettingInt('tvde_max_stops', 2);
    final fee = await store.getSettingInt('tvde_stop_fee_cents', 200);
    final timer = await store.getSettingInt('tvde_stop_timer_seconds', 120);
    final grace = await store.getSettingInt('cancel_grace_seconds', 180);
    final etaSpeed = await store.getSettingInt('eta_avg_speed_kmh', 28);
    // [05/09] cadência do cartão do motorista + regra do ETA mostrado.
    final pollS = await store.getSettingInt(
        'tvde_driver_card_poll_seconds', _driverPollSeconds);
    final etaPct = await store.getSettingInt(
        'tvde_eta_client_discount_pct', kTvdeEtaClientDiscountPct);
    final etaCut = await store.getSettingInt(
        'tvde_eta_client_discount_max_min', kTvdeEtaClientDiscountMaxMin);
    final etaFloor = await store.getSettingInt(
        'tvde_eta_client_floor_min', kTvdeEtaClientFloorMin);
    final arriving =
        await store.getSettingInt('tvde_eta_arriving_push_min', _etaArrivingMin);
    // [2C · 05/09] Idade da posição a partir da qual se avisa o cliente.
    final stale =
        await store.getSettingInt('tvde_driver_stale_seconds', _staleSeconds);
    final lost =
        await store.getSettingInt('tvde_driver_lost_seconds', _lostSeconds);
    final ride = store.activeRide;
    final pkg = ride != null
        ? await TvdeRoundtripPrice.loadForRide(store, ride)
        : TvdeRoundtripPrice.fallbackCents;
    if (mounted) {
      final pollMudou = pollS > 0 && pollS != _driverPollSeconds;
      setState(() {
        _maxStops = max;
        _stopFeeCents = fee;
        _stopTimerSeconds = timer;
        _cancelGraceSeconds = grace;
        _packageCents = pkg;
        if (etaSpeed > 0) _etaSpeedKmh = etaSpeed;
        if (pollS > 0) _driverPollSeconds = pollS;
        _etaDiscountPct = etaPct;
        _etaDiscountMaxMin = etaCut;
        _etaFloorMin = etaFloor;
        _etaArrivingMin = arriving;
        // "Perdido" tem de ser DEPOIS de "velho": settings trocadas no admin
        // não podem pôr o ecrã a dizer as duas coisas ao mesmo tempo.
        if (stale > 0) _staleSeconds = stale;
        if (lost > _staleSeconds) _lostSeconds = lost;
      });
      if (pollMudou) _restartDriverPoll();
    }
  }

  Future<void> _loadStops() async {
    final ride = context.read<TvdeStore>().activeRide;
    if (ride == null) return;
    final stops = await context.read<TvdeStore>().fetchRideStops(ride.id);
    if (mounted) setState(() => _stops = stops);
    unawaited(_loadStopIcons());
  }

  // ── [TVDE 05/09 · 2C] Idade da posição do motorista ───────────────────────

  /// Segundos desde a última posição do motorista. Null = nunca houve posição
  /// (aí não há carro no mapa e não há nada a dizer sobre a idade dele).
  /// Relógio do telemóvel adiantado em relação ao servidor daria idade
  /// negativa — trava-se em 0 em vez de mostrar disparate.
  /// A conta vive em `lib/utils/tvde_sinal_motorista.dart` — pura, com o
  /// relógio injectável, para poder ser exercitada por um teste directo sem
  /// device nem mapa. Aqui só se lhe passa a hora e os limites das settings.
  int? get _segundosDesdeFix => segundosDesdeFix(_driverFixAt);

  EstadoSinalMotorista get _estadoSinal => estadoDoSinal(
        _driverFixAt,
        staleSeconds: _staleSeconds,
        lostSeconds: _lostSeconds,
      );

  /// Posição velha: pára a animação e esbate o carro.
  bool get _sinalVelho =>
      _estadoSinal == EstadoSinalMotorista.velho ||
      _estadoSinal == EstadoSinalMotorista.perdido;

  /// Posição perdida: já não se finge que o ponto no mapa é o motorista.
  bool get _sinalPerdido => _estadoSinal == EstadoSinalMotorista.perdido;

  /// [1B · 05/09] Gera (uma vez por combinação) o pino numerado de cada parada.
  /// Só o número muda de parada para parada, e só o tom muda quando ela é
  /// alcançada — por isso a chave é `'<seq>|<alcançada>'` e o mapa não cresce.
  Future<void> _loadStopIcons() async {
    if (kIsWeb || !mounted) return;
    var novos = false;
    for (final s in _stops) {
      final chave = '${s.seq}|${s.reached}';
      if (_stopIcons.containsKey(chave)) continue;
      try {
        final bytes = await _createStopIcon(s.seq, alcancada: s.reached);
        _stopIcons[chave] = BitmapDescriptor.bytes(bytes);
        novos = true;
      } catch (_) {/* fallback: marker nativo (ver _markers) */}
    }
    if (novos && mounted) setState(() {});
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
            ? 'Já atingiste o máximo de {0} paradas.'.trArgs([_maxStops])
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
          SnackBar(content: Text('Parada adicionada.'.tr)),
        );
      } else if (outcome?['refunded'] == true) {
        messenger.showSnackBar(SnackBar(
          content: Text('Pagamento devolvido — não foi possível adicionar a parada. {0}'.trArgs([_stopErrorPt(outcome?['error']?.toString())])),
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text('Não recebemos a confirmação do pagamento. A parada não foi adicionada.'.tr),
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
      return 'Já atingiste o máximo de {0} paradas.'.trArgs([_maxStops]);
    }
    if (e.contains('invalid_ride_state_for_stop')) {
      return 'A corrida já não permite adicionar paradas.'.tr;
    }
    if (e.contains('card_payments_not_enabled')) {
      return 'Os pagamentos no cartão estão desativados de momento.'.tr;
    }
    if (e.contains('below_minimum')) {
      return 'Valor abaixo do mínimo aceite pelo pagamento.'.tr;
    }
    return 'Não foi possível adicionar a parada.'.tr;
  }

  Future<void> _removeStop(TvdeRide ride, TvdeRideStop stop) async {
    try {
      await context.read<TvdeStore>().removeStop(ride.id, stop.id);
      await _loadStops();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover a parada.'.tr)),
        );
      }
    }
  }

  /// B2 — traça a rota real recolha→destino (grossa). Uma vez por corrida.
  Future<void> _maybeFetchRoute(TvdeRide ride) async {
    // [1B · 05/09] A chave deixa de ser só a corrida: passa a mudar quando
    // entra ou sai uma parada. Sem isto, o cliente pagava €2 por uma paragem e
    // a linha grossa continuava a ir a direito ao destino, a contradizer a
    // linha do motorista — que desde hoje passa lá.
    final chave = chaveFaseComStops(ride.id,
        emViagem: true, stops: _stops, maxStops: _maxStops);
    if (_routeKey == chave) return;
    _routeKey = chave;
    try {
      final route = await _directions.fetchRoute(
        origin: ll.LatLng(ride.originLat, ride.originLng),
        destination: ll.LatLng(ride.destLat, ride.destLng),
        waypoints: waypointsDasStops(_stops, maxStops: _maxStops),
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

  /// C4 + [2A/2B · 05/09] — o carro deixa de saltar E deixa de cortar esquinas.
  ///
  /// **A cicatriz:** eram 12 passos × 80 ms em LINHA RECTA entre duas leituras.
  /// Como as leituras chegam de 50 em 50 metros, o carro cortava esquinas e
  /// atravessava quarteirões — passava por dentro dos prédios enquanto a linha
  /// da rota, desenhada mesmo ali, ia pela rua. E, fosse o carro parado num
  /// semáforo ou a 90 na variante, a animação durava sempre os mesmos 960 ms:
  /// um deslizava sem sair do sítio, o outro dava um solavanco e congelava.
  ///
  /// Agora: anda POR CIMA da polilinha já desenhada (`passosSobreRota`) e ao
  /// ritmo do `speed_kmh` que a RPC sempre mandou. Sem rota desenhada (ainda a
  /// carregar, ou o Directions falhou) mantém-se a linha recta — recurso, não
  /// regressão.
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
    _animTimer?.cancel();
    if (from == null) {
      setState(() => _driverPos = target);
      return;
    }
    if ((from.latitude - target.latitude).abs() < 1e-6 &&
        (from.longitude - target.longitude).abs() < 1e-6) {
      return;
    }

    final metrosRecta = Geolocator.distanceBetween(
        from.latitude, from.longitude, target.latitude, target.longitude);
    final v = _driverSpeedKmh;

    // [2B] Carro PARADO não desliza: velocidade a zero com um salto de metros
    // é ruído de GPS, não marcha. Assenta e fica quieto.
    // [2C] Posição já velha também não se anima — seria movimento inventado.
    if ((v != null && v < 1.5 && metrosRecta < 15) || _sinalVelho) {
      setState(() => _driverPos = target);
      return;
    }

    // [2B] Quanto tempo é que o carro leva MESMO a fazer este bocado, ao ritmo
    // a que anda. Tecto = o intervalo do poll: a animação tem de acabar antes
    // da leitura seguinte, senão empilham-se duas.
    final tetoMs = _driverPollSeconds.clamp(1, 30) * 1000;
    var totalMs = tetoMs;
    if (v != null && v > 1.0) {
      totalMs = (metrosRecta / (v / 3.6) * 1000).round();
    }
    totalMs = totalMs.clamp(_kAnimMinMs, tetoMs);
    // Os 12 passos são o CHÃO: numa janela longa acrescentam-se fotogramas em
    // vez de os espaçar, senão o carro anda a três imagens por segundo.
    final passos =
        (totalMs / _kAnimMsPorPasso).round().clamp(_kAnimPassosBase, 60);

    // [2A] Por cima da rota — só se houver linha e o carro estiver mesmo nela.
    final sobreRota = passosSobreRota(
      _driverRouteLL,
      ll.LatLng(from.latitude, from.longitude),
      ll.LatLng(target.latitude, target.longitude),
      passos: passos,
    );
    if (sobreRota != null) {
      // O comprimento REAL pela estrada é maior do que a distância a direito:
      // com ele o ritmo deixa de ser optimista.
      if (v != null && v > 1.0) {
        totalMs = (sobreRota.metros / (v / 3.6) * 1000)
            .round()
            .clamp(_kAnimMinMs, tetoMs);
      }
    }
    final caminho = sobreRota?.pontos;
    final periodo = Duration(
        milliseconds: (totalMs / passos).round().clamp(30, 200));

    var step = 0;
    _animTimer = Timer.periodic(periodo, (t) {
      step++;
      if (!mounted) {
        t.cancel();
        return;
      }
      final LatLng p;
      if (caminho != null) {
        // `min` é cinto e suspensórios: o timer já pára no último passo.
        final q = caminho[math.min(step, caminho.length) - 1];
        p = LatLng(q.latitude, q.longitude);
      } else {
        final f = step / passos;
        p = LatLng(
          from.latitude + (target.latitude - from.latitude) * f,
          from.longitude + (target.longitude - from.longitude) * f,
        );
      }
      // [2B] A andar em cima da rota, o carro aponta para onde a ESTRADA vai —
      // é isto que o faz dobrar a esquina em vez de derrapar de lado. Só conta
      // como plano B: o `heading` do dispositivo, quando existe, manda.
      final ant = _driverPos;
      if (ant != null) {
        final d = Geolocator.distanceBetween(
            ant.latitude, ant.longitude, p.latitude, p.longitude);
        if (d >= 2) {
          var b = Geolocator.bearingBetween(
              ant.latitude, ant.longitude, p.latitude, p.longitude);
          if (b < 0) b += 360;
          _bearing = b;
        }
      }
      setState(() => _driverPos = p);
      if (step >= passos) t.cancel();
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

  /// C5 + [botoes-navbar-eta 31/08] — ETA VIVO do motorista: até à recolha
  /// (antes de embarcar) ou ao destino (em viagem). Fonte preferida: a
  /// duração da MESMA rota desenhada no mapa (Directions), enquanto fresca;
  /// fallback: distância restante ÷ `eta_avg_speed_kmh` das settings.
  /// Recalculado a cada poll de posição (5 s) — nunca congela no valor
  /// inicial. Null quando não há posição do motorista.
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
    // [1C · 05/09] Tempo PARADO que ainda falta cumprir nas paradas. A rota da
    // Google só conta condução; sem esta parcela o ecrã prometia um destino
    // que o carro não conseguia cumprir — cobrava-se a paragem e escondia-se
    // o tempo dela. Só conta a caminho do DESTINO: as paradas ficam depois da
    // recolha, e somá-las ao ETA do pickup atrasaria o aviso do 2C.
    final paradoMin = ride.isInProgress
        ? minutosParadoPendente(_stops,
            stopTimerSeconds: _stopTimerSeconds, maxStops: _maxStops)
        : 0.0;
    // Rota fresca (pedida há <45 s E o carro ainda perto do ponto do pedido)
    // → a duração dela é a verdade. O refetch por movimento (≥120 m em
    // _maybeFetchDriverRoute) mantém-na viva enquanto o carro anda. Desde
    // 05/09 essa rota já passa PELAS paradas, por isso a condução delas está
    // aqui dentro — falta só o tempo de porta aberta.
    final at = _driverRouteEtaAt;
    final from = _driverRouteEtaFrom;
    final routeMin = _driverRouteEtaMin;
    if (routeMin != null && at != null && from != null) {
      final movedM = Geolocator.distanceBetween(
          from.latitude, from.longitude, pos.latitude, pos.longitude);
      if (DateTime.now().difference(at).inSeconds < 45 && movedM < 150) {
        _etaIsRough = false;
        final mins = (routeMin + paradoMin).ceil();
        return mins < 1 ? 1 : mins;
      }
    }
    // Sem rota fresca: distância a direito ÷ velocidade média. Dá sempre um
    // número (nunca "—"), mas fica marcado como estimativa grosseira. Também
    // aqui o caminho passa pelas paradas — um atalho imaginário pelo destino
    // seria a mesma mentira, só que noutro ramo do código.
    _etaIsRough = true;
    var km = 0.0;
    var pLat = pos.latitude;
    var pLng = pos.longitude;
    if (ride.isInProgress) {
      for (final s in stopsPendentes(_stops, maxStops: _maxStops)) {
        km += _haversineKm(pLat, pLng, s.lat, s.lng);
        pLat = s.lat;
        pLng = s.lng;
      }
    }
    km += _haversineKm(pLat, pLng, tLat, tLng);
    final mins = (km / _etaSpeedKmh * 60 + paradoMin).ceil();
    return mins < 1 ? 1 : mins;
  }

  /// [2B · 05/09] O número que o CLIENTE vê — o real menos o desconto de
  /// apresentação (regra do Danilo, toda em `platform_settings`). O ETA real
  /// nunca sai daqui: quem decide o aviso do 2C é `_etaMinutes`.
  int? _etaShownMinutes(TvdeRide ride) {
    final real = _etaMinutes(ride);
    if (real == null) return null;
    return tvdeEtaShownMinutes(
      real,
      discountPct: _etaDiscountPct,
      discountMaxMin: _etaDiscountMaxMin,
      floorMin: _etaFloorMin,
    );
  }

  /// O carro já está no ponto de recolha? O estado `motorista_chegou` pode
  /// demorar a chegar pelo realtime, e quem tem o carro à porta não pode
  /// continuar a ler "chega em ~1 min".
  bool _motoristaNoPonto(TvdeRide ride) {
    final pos = _driverPos;
    if (pos == null || ride.isInProgress) return false;
    final metros = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, ride.originLat, ride.originLng);
    if (metros < 100) return true;
    // Parado mesmo à porta: o GPS urbano erra uns metros, e um carro travado
    // a 120 m do ponto já ali está.
    final v = _driverSpeedKmh;
    return v != null && v < 3 && metros < 150;
  }

  /// [2C · 05/09] Aviso "está quase a chegar", uma vez por corrida, quando
  /// faltam `tvde_eta_arriving_push_min` minutos de ETA **REAL**.
  ///
  /// Só com rota real: uma estimativa a direito não é firme o suficiente para
  /// mandar alguém descer à rua.
  void _maybeAvisarQuaseAChegar(TvdeRide ride) {
    if (_arrivingNotifiedRideId == ride.id) return;
    // `isAssigned` já inclui `motorista_chegou`: quem chegou não está "quase".
    // E em fila (back-to-back) o motorista ainda nem vem a caminho.
    if (!ride.isAssigned ||
        ride.isInProgress ||
        ride.hasArrived ||
        ride.isQueued) {
      return;
    }
    final real = _etaMinutes(ride);
    if (real == null || _etaIsRough || real > _etaArrivingMin) return;

    _arrivingNotifiedRideId = ride.id; // marca ANTES: nunca sai duas vezes
    final quem = _primeiroNome(_driverName) ?? 'O teu motorista'.tr;
    final carro = <String>[
      if (_driverCar != null && _driverCar!.isNotEmpty) _driverCar!,
      if (_driverCarColor != null && _driverCarColor!.isNotEmpty)
        _driverCarColor!,
      if (_driverPlate != null && _driverPlate!.isNotEmpty)
        _formataMatricula(_driverPlate!),
    ].join(', ');
    unawaited(TvdeArrivingNotice.show(
      rideId: ride.id,
      title: '{0} está quase a chegar'.trArgs([quem]),
      body: carro.isEmpty ? 'Prepara-te para sair.'.tr : carro,
    ));
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
      // [1A · 05/09] Cartão PÚBLICO do motorista. A RPC recebe o id da
      // CORRIDA (não o do motorista) e é ela que decide se quem pergunta é
      // mesmo o passageiro desta corrida — por isso pode ser SECURITY DEFINER
      // sem abrir a tabela `drivers`, onde vivem IBAN, NIF e documentos.
      final res = await Supabase.instance.client
          .rpc('tvde_ride_driver_card', params: {'p_ride_id': ride.id});
      // `RETURNS TABLE` chega como lista; aceitamos também o mapa único, para
      // a tela não voltar a ficar muda se a assinatura mudar de forma.
      Map<String, dynamic>? bruto;
      if (res is List) {
        if (res.isNotEmpty && res.first is Map) {
          bruto = Map<String, dynamic>.from(res.first as Map);
        }
      } else if (res is Map) {
        bruto = Map<String, dynamic>.from(res);
      }
      if (bruto == null) {
        _notaFalhaCartao('resposta vazia');
        return;
      }
      final row = bruto; // não-nulo: o setState lá abaixo é um closure

      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();
      final heading = (row['heading'] as num?)?.toDouble();
      final speed = (row['speed_kmh'] as num?)?.toDouble();
      // [2C · 05/09] A idade da posição — o dado que a RPC sempre devolveu e
      // que ninguém lia. Sem ele, GPS morto e carro parado eram indistinguíveis
      // no ecrã do cliente.
      final fixAt =
          DateTime.tryParse(row['location_updated_at']?.toString() ?? '');
      if (!mounted) return;

      // A velocidade e a idade têm de estar postas ANTES de mexer na posição:
      // é `_setDriverPos` que decide, com elas, se anima ou se assenta.
      _driverSpeedKmh = speed;
      if (fixAt != null) _driverFixAt = fixAt;

      // C4 — anima em vez de saltar. Primeiro a posição: é ela que atualiza o
      // `_bearing` calculado entre pontos, que serve de plano B ao heading.
      if (lat != null && lng != null) {
        final pos = LatLng(lat, lng);
        _setDriverPos(pos);
        // [Bloco 5] rota viva do motorista (→recolha / →destino).
        _maybeFetchDriverRoute(ride, pos);
      }
      if (!mounted) return;
      setState(() {
        _driverName = (row['name'] as String?)?.trim();
        _driverRating = (row['avg_rating'] as num?)?.toDouble();
        _driverRatingsCount = (row['ratings_count'] as num?)?.toInt();
        _driverPhotoUrl = (row['photo_url'] as String?)?.trim();
        _driverCar = (row['vehicle_make_model'] as String?)?.trim();
        _driverCarColor = (row['vehicle_color'] as String?)?.trim();
        _driverPlate = (row['license_plate'] as String?)?.trim();
        _driverPhone = (row['phone'] as String?)?.trim();
        // 1B — para onde o carrinho aponta: heading do dispositivo enquanto
        // anda; parado (ou sem heading) usa a direção entre as duas últimas
        // posições; sem nem isso, mantém a última — parado não gira à toa.
        final aMexer = speed == null || speed > 1.5;
        final alvo = (heading != null && aMexer)
            ? heading
            : (_lastBearingPos != null ? _bearing : null);
        if (alvo != null) _driverHeading = _suavizaHeading(_driverHeading, alvo);
        _driverCardFails = 0;
        _driverCardDegraded = false;
      });
      // 2C — "está quase a chegar" (usa o ETA REAL, nunca o com desconto).
      _maybeAvisarQuaseAChegar(ride);
    } catch (e) {
      // Nunca mais em silêncio: um catch mudo escondeu este bug durante
      // semanas, com passageiros reais a olhar para um mapa vazio.
      _notaFalhaCartao(e.toString());
    }
  }

  /// Falha ao ler o cartão do motorista. Regista sempre; ao fim de TRÊS
  /// seguidas assume-se ao cliente que estamos a tentar ligar-nos — um ecrã
  /// que falha calado é pior do que um que se explica.
  void _notaFalhaCartao(String motivo) {
    _driverCardFails++;
    debugPrint('[TVDE-CLIENTE] tvde_ride_driver_card falhou '
        '($_driverCardFails.ª seguida): $motivo');
    if (_driverCardFails >= 3 && !_driverCardDegraded && mounted) {
      setState(() => _driverCardDegraded = true);
    }
  }

  /// Suaviza a rotação do carrinho (novo×0,3 + antigo×0,7) pelo caminho mais
  /// curto do círculo — sem isto, passar de 359° para 1° dava uma pirueta.
  double _suavizaHeading(double? anterior, double novo) {
    final n = ((novo % 360) + 360) % 360;
    if (anterior == null) return n;
    var delta = (n - anterior) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return ((anterior + delta * 0.3) % 360 + 360) % 360;
  }

  /// [Bloco 5, 30/08] Rota do motorista até ao alvo da fase atual — como o
  /// Uber: o cliente vê o caminho que o carro vai fazer, não só o pontinho.
  Future<void> _maybeFetchDriverRoute(TvdeRide ride, LatLng pos) async {
    final phase =
        ride.isInProgress ? 'dest' : (ride.isAssigned ? 'pickup' : '');
    if (phase.isEmpty) {
      if (_driverRoutePolys.isNotEmpty && mounted) {
        setState(() {
          _driverRoutePolys = <Polyline>{};
          _driverRouteLL = const [];
        });
      }
      return;
    }
    // [1B · 05/09] As paradas por alcançar entram como waypoints — mas SÓ a
    // caminho do destino. A caminho da recolha o passageiro ainda nem está no
    // carro: mandar o motorista passar primeiro pelas paradas seria absurdo.
    final emViagem = phase == 'dest';
    final List<ll.LatLng> waypoints = emViagem
        ? waypointsDasStops(_stops, maxStops: _maxStops)
        : const <ll.LatLng>[];
    // A chave inclui as paradas: acrescentar uma conta como fase nova e a
    // linha refaz-se já, em vez de esperar pelos 120 m de deslocação.
    final chave = chaveFaseComStops(ride.id,
        emViagem: emViagem, stops: _stops, maxStops: _maxStops);
    final from = _driverRouteFrom;
    final moved = from == null
        ? double.infinity
        : Geolocator.distanceBetween(
            from.latitude, from.longitude, pos.latitude, pos.longitude);
    if (chave == _driverRouteKey && moved < 120) return;
    _driverRouteKey = chave;
    _driverRouteFrom = pos;
    final target = emViagem
        ? ll.LatLng(ride.destLat, ride.destLng)
        : ll.LatLng(ride.originLat, ride.originLng);
    try {
      final route = await _directions.fetchRoute(
        origin: ll.LatLng(pos.latitude, pos.longitude),
        destination: target,
        waypoints: waypoints,
      );
      if (!mounted || route == null || route.points.isEmpty) return;
      setState(() {
        // [2A] Guardar os pontos crus: é sobre eles que o carro passa a andar.
        _driverRouteLL = route.points;
        // [31/08] a duração desta rota alimenta o ETA vivo (_etaMinutes).
        _driverRouteEtaMin = route.durationMinutes;
        _driverRouteEtaAt = DateTime.now();
        _driverRouteEtaFrom = pos;
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

  /// [1B · 05/09] Carrinho AZUL visto de cima, desenhado em código — não há
  /// asset de carro no projeto. Mesmo padrão da seta verde do ecrã do
  /// motorista: `BitmapDescriptor.bytes` NÃO existe na Web, por isso lá fica o
  /// marker nativo (azul na mesma) em vez de um ecrã partido.
  ///
  /// Azul porque o verde e o laranja são as cores da marca e já estão nos
  /// pinos de recolha e destino — o carro tem de se distinguir deles.
  Future<void> _loadCarIcon() async {
    if (kIsWeb) return;
    try {
      final bytes = await _createCarIcon();
      if (!mounted) return;
      setState(() => _carIcon = BitmapDescriptor.bytes(bytes));
    } catch (_) {/* fallback: marker nativo azul */}
  }

  Future<Uint8List> _createCarIcon() async {
    const size = 72.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Desenhado a apontar para CIMA (0° = norte). Quem o roda é o
    // `Marker.rotation`, com o heading do motorista.
    final corpo = ui.Path()
      ..moveTo(36, 4) // bico da frente
      ..lineTo(52, 20)
      ..lineTo(52, 62)
      ..quadraticBezierTo(52, 68, 46, 68)
      ..lineTo(26, 68)
      ..quadraticBezierTo(20, 68, 20, 62)
      ..lineTo(20, 20)
      ..close();

    // Halo branco primeiro: sem ele o carro azul desaparece por cima de uma
    // estrada escura do mapa.
    canvas.drawPath(
      corpo,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(corpo, Paint()..color = AppColors.mapDropoff);
    // Tejadilho claro — é o que dá o sentido da marcha num ícone pequeno.
    canvas.drawRRect(
      RRect.fromLTRBR(25, 26, 47, 48, const Radius.circular(5)),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  /// [1B · 05/09] Pino NUMERADO da parada. O cliente paga €2 por cada uma:
  /// tem de ver quantas são e por que ordem o carro lá passa — antes eram
  /// todas o mesmo alfinete azul, indistinguíveis entre si e da cor do carro.
  ///
  /// Escuro (não verde, não laranja, não vermelho, não azul) porque a recolha,
  /// a linha do motorista, o destino e o carro já ocupam essas quatro cores
  /// neste mapa. Alcançada fica cinzenta: já passou, não é para onde se vai.
  Future<Uint8List> _createStopIcon(int numero, {required bool alcancada}) async {
    const size = 64.0;
    const centro = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Halo branco: sem ele o pino escuro desaparece sobre uma estrada escura.
    canvas.drawCircle(centro, 24, Paint()..color = Colors.white);
    canvas.drawCircle(
      centro,
      21,
      Paint()
        ..color = alcancada ? AppColors.textSubtle : AppColors.textPrimary,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '$numero',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(centro.dx - tp.width / 2, centro.dy - tp.height / 2));

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Set<Marker> _markers(TvdeRide ride) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(ride.originLat, ride.originLng),
        infoWindow: InfoWindow(title: 'Recolha'.tr),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: LatLng(ride.destLat, ride.destLng),
        infoWindow: InfoWindow(title: 'Destino'.tr),
      ),
    };
    if (_driverPos != null) {
      // [1B] Carro azul, deitado no mapa e virado para onde segue — em vez do
      // alfinete laranja, que não dizia nada sobre a direção de marcha.
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _driverPos!,
        anchor: const Offset(0.5, 0.5), // roda sobre o próprio centro
        flat: true,
        rotation: _driverHeading ?? _bearing,
        // [2C] Posição velha → carro ESBATIDO. É o sinal visual de que aquele
        // ponto já não é de fiar; sólido a mentir era o que havia antes.
        alpha: _sinalVelho ? 0.4 : 1.0,
        infoWindow: InfoWindow(title: _driverName ?? 'Motorista'.tr),
        icon: _carIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }
    // [Feature 1 + 1B · 05/09] Paradas adicionais, agora com o número À VISTA
    // no mapa e com as já passadas apagadas — e não todas o mesmo alfinete.
    for (final s in _stops) {
      final icone = _stopIcons['${s.seq}|${s.reached}'];
      markers.add(Marker(
        markerId: MarkerId('stop_${s.id}'),
        position: LatLng(s.lat, s.lng),
        anchor: icone != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1),
        // Web (e falha a desenhar): sem bitmap próprio, o alfinete violeta
        // distingue-se da recolha/destino/carro, e o já-passado fica esbatido.
        alpha: icone != null || !s.reached ? 1.0 : 0.5,
        infoWindow:
            InfoWindow(title: 'Parada {0}'.trArgs([s.seq]), snippet: s.label),
        icon: icone ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
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
      messenger.showSnackBar(SnackBar(
        content: Text('Pede a corrida outra vez para escolheres o pagamento — a anterior não chegou a ter motorista e não foi cobrada.'.tr),
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
          title: Text('Desistir da corrida?'.tr),
          content: Text(
              'Ainda não foste cobrado e nenhum motorista foi chamado. Podes desistir sem custo.'.tr),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Continuar a aguardar'.tr)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Sim, desistir'.tr)),
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Afinal o pagamento já entrou (ou está a ser confirmado) — a corrida segue.'.tr)));
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
        title: Text('Cancelar corrida?'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (feeCents == 0)
              Text(
                  'Cancelamento grátis (dentro dos primeiros {0} min).'.trArgs([graceMin]),
                  style: const TextStyle(color: AppColors.textSecondary))
            else ...[
              Text(
                  'Já passaram mais de {0} min. Cancelar agora tem um custo:'.trArgs([graceMin]),
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
                        'Custo de cancelamento: €{0}'.trArgs([(feeCents / 100).toStringAsFixed(2)]),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Text('Corresponde ao valor total da corrida.'.tr,
                  style:
                      const TextStyle(color: AppColors.textSubtle, fontSize: 12.5)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Voltar'.tr)),
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
              ? 'A corrida já tinha terminado.'.tr
              : 'A corrida já estava cancelada.')));
      context.read<TvdeStore>().clearActiveRide();
      Navigator.pop(context);
      return;
    }
    context.read<TvdeStore>().refreshActiveRide();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível cancelar.'.tr)),
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
      return Scaffold(
        appBar: BoraScreenAppBar(title: 'A tua corrida'.tr),
        body: Center(child: Text('Sem corrida ativa.'.tr)),
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
    // [2A] Chegou = o estado do servidor OU o carro já ali (o realtime pode
    // demorar, e quem vê o carro à porta não pode ler "chega em ~1 min").
    final chegou = ride.hasArrived || _motoristaNoPonto(ride);
    final panel = _StatusPanel(
      ride: ride,
      busy: _accaoEmCurso,
      driverName: _driverName,
      driverRating: _driverRating,
      driverRatingsCount: _driverRatingsCount,
      driverPhotoUrl: _driverPhotoUrl,
      driverCar: _driverCar,
      driverCarColor: _driverCarColor,
      driverPlate: _driverPlate,
      hasPhone: _driverPhone != null && _driverPhone!.isNotEmpty,
      driverArrived: chegou,
      // [2C · 05/09] Posição PERDIDA (>tvde_driver_lost_seconds) diz o mesmo
      // que a leitura falhada: "A ligar-se ao motorista…". É a frase que já
      // existia para isto — não se inventa uma segunda para o mesmo estado.
      driverCardDegraded: _driverCardDegraded || _sinalPerdido,
      // Velha mas ainda não perdida → dizer há quanto tempo é.
      lastFixSeconds:
          _sinalVelho && !_sinalPerdido ? _segundosDesdeFix : null,
      // [2B] O painel recebe o número JÁ com o desconto de apresentação.
      etaMinutes: _etaShownMinutes(ride),
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
      // [PADRAO_BORA 3.13 · 05/09] As três acções passam pelo guarda LOCAL.
      // Antes travavam no `busy` GLOBAL do `TvdeStore`, o que aqui era o pior
      // dos dois mundos: o botão podia nascer desligado por causa de um poll
      // qualquer, e ao mesmo tempo o global era largado por outra operação a
      // terminar — deixando "Pagar de novo" e "Cancelar" a descoberto no
      // instante que interessa. O guarda local trava no PRIMEIRO toque e só
      // solta quando esta acção responde.
      onCancel: () => _comGuarda(() => _cancel(ride)),
      onPayAgain: ride.isAwaitingPayment &&
              ride.paymentMethod == 'card' &&
              store.cardClientSecretFor(ride.id) != null
          ? () => _comGuarda(() => _pagarDeNovo(ride))
          : null,
      onRetry: () => _comGuarda(() => _retry(ride, store)),
      onClose: () {
        store.clearActiveRide();
        Navigator.pop(context);
      },
    );

    return Scaffold(
      appBar: BoraScreenAppBar(title: 'A tua corrida'.tr),
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
                      etaMinutes: _etaShownMinutes(ride),
                      driverFirstName: _primeiroNome(_driverName),
                      driverArrived: chegou,
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

/// [1C · 05/09] Primeiro nome do motorista. "Danilo chega em ~8 min" é uma
/// pessoa a caminho; "Motorista a caminho" é uma abstração. Vazio → null, para
/// o texto cair no genérico em vez de mostrar espaço em branco.
String? _primeiroNome(String? completo) {
  final n = completo?.trim();
  if (n == null || n.isEmpty) return null;
  final primeiro = n.split(RegExp(r'\s+')).first;
  return primeiro.isEmpty ? null : primeiro;
}

/// [1C · 05/09] Matrícula portuguesa em pares: "CH90PX" → "CH-90-PX". É por
/// ela que o passageiro reconhece o carro certo na rua, por isso tem de estar
/// legível. Já com traços — ou com outro número de caracteres — fica como
/// está: nunca se inventa formato em cima do que a base tem.
String _formataMatricula(String bruta) {
  final t = bruta.trim().toUpperCase();
  if (t.contains('-')) return t;
  final limpa = t.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (limpa.length != 6) return t;
  return '${limpa.substring(0, 2)}-${limpa.substring(2, 4)}-'
      '${limpa.substring(4, 6)}';
}

/// [Bloco 5, 30/08] A fitinha do fundo — estilo Uber: uma linha com o estado,
/// o ETA e o preço; puxar para cima mostra o painel completo (paradas,
/// mensagem, ligar, cancelar).
class _CompactStrip extends StatelessWidget {
  const _CompactStrip({
    required this.ride,
    required this.fare,
    required this.etaMinutes,
    required this.driverFirstName,
    required this.driverArrived,
  });

  final TvdeRide ride;
  final TvdeFareView fare;

  /// Já com o desconto de apresentação (2B) — nunca o ETA real.
  final int? etaMinutes;
  final String? driverFirstName;
  final bool driverArrived;

  /// [2A · 05/09] Os textos falam do motorista pelo nome e mexem-se com o ETA.
  String get _texto {
    final quem = driverFirstName;
    if (ride.isInProgress) {
      return etaMinutes != null
          ? 'Chegas ao destino em ~{0} min'.trArgs([etaMinutes])
          : 'Viagem em curso'.tr;
    }
    if (driverArrived) {
      return quem != null ? '{0} chegou'.trArgs([quem]) : 'O motorista chegou'.tr;
    }
    if (etaMinutes == null) {
      return quem != null
          ? '{0} está a caminho'.trArgs([quem])
          : 'Motorista a caminho'.tr;
    }
    return quem != null
        ? '{0} chega em ~{1} min'.trArgs([quem, etaMinutes])
        : 'Motorista a caminho · chega em ~{0} min'.trArgs([etaMinutes]);
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
    required this.driverRatingsCount,
    required this.driverPhotoUrl,
    required this.driverCar,
    required this.driverCarColor,
    required this.driverPlate,
    required this.hasPhone,
    required this.driverArrived,
    required this.driverCardDegraded,
    required this.lastFixSeconds,
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

  /// [1C] Nº de avaliações — "5,0" sozinho não vale nada se for de uma só.
  final int? driverRatingsCount;
  // D1 — cartão completo do motorista.
  final String? driverPhotoUrl;
  final String? driverCar;
  final String? driverCarColor;
  final String? driverPlate;
  final bool hasPhone;

  /// [2A] Chegou (estado do servidor ou carro já no ponto).
  final bool driverArrived;

  /// [1A] Três leituras seguidas falhadas → dizer ao cliente que estamos a
  /// tentar, em vez de o deixar a olhar para um cartão vazio.
  final bool driverCardDegraded;

  /// [2C · 05/09] Há quantos segundos é a última posição do motorista, quando
  /// ela já é VELHA (mas ainda não perdida). Null = posição fresca, ou já
  /// perdida — nesse caso quem fala é o `driverCardDegraded`.
  ///
  /// Dizer "há 3 min" é o que separa um GPS morto de um carro parado no
  /// trânsito. Sem isto, o cliente vê o mesmo ecrã nos dois casos.
  final int? lastFixSeconds;

  /// C5 — "chega em ~X min" (recolha) / "destino em ~X min" (em viagem).
  /// Já com o desconto de apresentação (2B).
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

  /// [1C] Linha do carro: "Hyundai Ioniq 5 · Azul". A matrícula saiu daqui de
  /// propósito — é o dado que serve para reconhecer o carro na rua e passou a
  /// ter destaque próprio, não mais uma palavra numa linha comprida.
  String? _carLine() {
    final parts = <String>[
      if (driverCar != null && driverCar!.isNotEmpty) driverCar!,
      if (driverCarColor != null && driverCarColor!.isNotEmpty) driverCarColor!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// [2A] Linha do ETA, pelo nome do motorista. O número já vem com o
  /// desconto de apresentação — aqui só se escolhe a frase.
  String _etaTexto(int minutos) {
    if (ride.isInProgress) {
      return 'Chegas ao destino em ~{0} min'.trArgs([minutos]);
    }
    final quem = _primeiroNome(driverName);
    return quem != null
        ? '{0} chega em ~{1} min'.trArgs([quem, minutos])
        : 'O motorista chega em ~{0} min'.trArgs([minutos]);
  }

  /// [1C] Cabeçalho do cartão: uma pessoa, não uma função.
  String _headline() {
    final quem = _primeiroNome(driverName);
    if (quem == null) return 'Motorista'.tr;
    if (ride.isInProgress) return quem;
    if (driverArrived) return '{0} chegou'.trArgs([quem]);
    return '{0} está a caminho'.trArgs([quem]);
  }

  @override
  Widget build(BuildContext context) {
    final fare = TvdeFareView.of(ride, packageCents: packageCents);
    return Container(
      width: double.infinity,
      // [botoes-navbar-eta 31/08] margem inferior soma o viewPadding do
      // sistema: sem isto o "Cancelar corrida" colava na navbar de 3 botões
      // nos estados em que o cartão assenta no fundo do ecrã.
      margin: EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md,
          Spacing.md + MediaQuery.of(context).viewPadding.bottom),
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
          // [1C · 05/09] O cartão vive também EM VIAGEM: antes só aparecia com
          // `isAssigned`, e a linha do ETA ao destino aqui dentro nunca chegava
          // a ser desenhada. Quem já embarcou continua a precisar do contacto.
          if ((ride.isAssigned || ride.isInProgress) &&
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
                      Text(_headline(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textPrimary)),
                      // [1C] carro: marca/modelo · cor (a matrícula vai à parte).
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
                  // [1C] "5,0" de uma única avaliação não é o mesmo que de 200.
                  if (driverRatingsCount != null && driverRatingsCount! > 0) ...[
                    const SizedBox(width: 3),
                    Text('($driverRatingsCount)',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSubtle)),
                  ],
                ],
              ],
            ),
            // [1C] MATRÍCULA — o elemento mais importante do cartão: é por ela
            // que o passageiro reconhece o carro certo na rua, muitas vezes ao
            // longe e com pressa. Grande, espaçada e com moldura própria.
            if (driverPlate != null && driverPlate!.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: Spacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: AppColors.dividerStrong, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.directions_car,
                        size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        _formataMatricula(driverPlate!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                      label: Text('Mensagem'.tr),
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
                      label: Text('Ligar'.tr),
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
            // [2A] ETA do motorista (recolha ou destino), pelo nome dele.
            // Chegou → deixa de haver contagem: já ali está.
            if (driverArrived && !ride.isInProgress) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  const Icon(Icons.where_to_vote,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 4),
                  // O cabeçalho já diz "{Nome} chegou" — aqui vale a pena o
                  // dado a mais, não repetir a mesma frase duas vezes.
                  Text(
                    'O carro já está no ponto de recolha.'.tr,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ] else if (etaMinutes != null && !ride.isQueued) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _etaTexto(etaMinutes!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700),
                    ),
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
                        ? 'A confirmar pagamento…'.tr
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('Incluída no plano'.tr,
                          style: const TextStyle(
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
          // [1A] Não conseguimos ler o cartão do motorista há três tentativas.
          // Dizê-lo baixinho é melhor do que deixar o cliente a olhar para um
          // ecrã parado sem perceber se é dele, se é nosso.
          if (driverCardDegraded) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                const Icon(Icons.sync_problem,
                    size: 14, color: AppColors.textSubtle),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'A ligar-se ao motorista…'.tr,
                    style: const TextStyle(
                        color: AppColors.textSubtle, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ]
          // [2C · 05/09] Posição velha mas ainda não perdida: o carro no mapa
          // está esbatido e parado — aqui diz-se PORQUÊ, em vez de deixar o
          // cliente a achar que o motorista é que não anda.
          else if (lastFixSeconds != null) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                const Icon(Icons.gps_off,
                    size: 14, color: AppColors.textSubtle),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    lastFixSeconds! < 60
                        ? 'Última posição há {0} s'.trArgs([lastFixSeconds!])
                        : 'Última posição há {0} min'
                            .trArgs([lastFixSeconds! ~/ 60]),
                    style: const TextStyle(
                        color: AppColors.textSubtle, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
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
                  ? 'À espera da confirmação do MB Way. Abre a app do teu banco e confirma o pagamento — só depois começamos a procurar motorista.'.tr
                  : onPayAgain != null
                      // Sheet aberta e abandonada sem pagar (d947b446): dizer
                      // a verdade e dar a saída, em vez de prometer que
                      // "aparece dentro de momentos".
                      ? 'O pagamento não foi concluído — ainda não começámos a procurar motorista e não foste cobrado. Toca em «Pagar de novo» ou cancela sem custo.'.tr
                      : 'Ainda não começámos a procurar motorista — estamos à espera da confirmação do pagamento. Se já confirmaste, aparece dentro de momentos.'.tr,
              style: const TextStyle(
                  color: AppColors.textSubtle, fontSize: 12),
            ),
            if (onPayAgain != null) ...[
              const SizedBox(height: Spacing.md),
              BoraAccentButton(
                label: 'Pagar de novo'.tr,
                icon: Icons.credit_card,
                loading: busy,
                onPressed: onPayAgain!,
              ),
            ],
          ],
          // Back-to-back — passageiro em fila: contexto claro, sem spinner.
          if (ride.isQueued && ride.isAssigned) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Serás o próximo: o motorista está a terminar uma viagem perto de ti e segue logo para a tua recolha.'.tr,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ],
          _buildStops(context),
          const SizedBox(height: Spacing.lg),
          if (ride.isNoDriver) ...[
            Text(
              'De momento não há motoristas disponíveis. Podes tentar novamente.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.md),
            BoraAccentButton(
              label: 'Tentar de novo'.tr,
              icon: Icons.refresh,
              loading: busy,
              onPressed: onRetry,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: onClose, child: Text('Fechar'.tr)),
          ] else if (ride.isInProgress) ...[
            Text('Boa viagem! O valor final é calculado pela distância real.'.tr,
                style: const TextStyle(color: AppColors.textSubtle, fontSize: 12)),
          ] else ...[
            OutlinedButton.icon(
              onPressed: busy ? null : onCancel,
              icon: const Icon(Icons.close),
              label: Text('Cancelar corrida'.tr),
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
            Expanded(
              child: Text('Paradas'.tr,
                  style: const TextStyle(
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
          'Passa por outro sítio a caminho — €{0} por parada. A parada não está incluída no plano.{1}'.trArgs([feePerStopEur.toStringAsFixed(2), ride.isPaidOnline ? ' Pagas a parada na hora.' : ' Pagas ao motorista no fim.']),
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
          Text('Máximo de {0} paradas atingido.'.trArgs([maxStops]),
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12)),
        if (stops.isNotEmpty) ...[
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: Text('Paradas ({0} × €{1})'.trArgs([stops.length, feePerStopEur.toStringAsFixed(2)]),
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
      appBar: BoraScreenAppBar(title: 'A tua corrida'.tr),
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
                  label: 'Fechar'.tr, icon: Icons.check, onPressed: onClose),
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
              tooltip: 'Remover parada'.tr,
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
        setState(() => _phoneError = 'Indica um número com 9 dígitos.'.tr);
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
                child: Text('Parada extra — {0}'.trArgs([eur]),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                tooltip: 'Fechar'.tr,
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text(widget.label,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: Spacing.md),
          Text(
            isMbway
                ? 'Esta corrida foi paga por MB Way. A parada é cobrada agora — só é adicionada depois de confirmares no MB Way.'.tr
                : 'Esta corrida foi paga no cartão. A parada é cobrada agora — só é adicionada depois de o pagamento passar.'.tr,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (isMbway) ...[
            const SizedBox(height: Spacing.md),
            TextField(
              key: const Key('tvde_stop_mbway_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Número MBWay'.tr,
                hintText: '9XXXXXXXX'.tr,
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
            label: 'Pagar {0} e adicionar'.trArgs([eur]),
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
                  Expanded(
                    child: Text('Adicionar parada'.tr,
                        style: const TextStyle(
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
              Text(
                  'Escolhe onde o motorista deve passar a caminho do destino.'.tr,
                  style:
                      const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: Spacing.md),
              AddressAutocompleteField(
                controller: _controller,
                labelText: 'Morada da parada'.tr,
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
