import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show kIsWeb;
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
import '../../../models/falha_de_acao.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/directions_service.dart';
import '../../../services/driver_location_ping_service.dart';
import '../../../services/navigation_service.dart';
import '../../../services/tvde_corrida_localizacao_service.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/tvde_chat_store.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../utils/route_deviation.dart';
import '../../../utils/tvde_stops_route.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/payments/collect_badge.dart';
import '../../../widgets/payments/collect_reminder_dialog.dart';
import '../../../widgets/tvde/tvde_pay_badge.dart';
import '../../../widgets/tvde/tvde_roundtrip_driver_notice.dart';
import '../../shared/tvde_chat_screen.dart';
import 'tvde_driver_rate_screen.dart';

/// [Uma corrida = uma stream · 05/09] `true` enquanto o ecrã de corrida activa
/// tiver GPS PRÓPRIO a funcionar. A home escuta isto e SUSPENDE a stream dela
/// — antes ficavam as duas abertas ao mesmo tempo durante a corrida inteira
/// (`bestForNavigation`/3 m aqui, `medium`/50 m lá), a gastar bateria a dobrar
/// para desenhar o mesmo carro.
///
/// Só passa a `true` depois de a stream deste ecrã ter DADO a primeira posição.
/// A ordem importa: a stream da home é a que alimenta o servidor com a posição
/// do motorista, e essa é a fonte do matching de corridas. Suspendê-la antes de
/// haver quem a substitua deixaria o servidor sem posição. Na Web, onde este
/// ecrã não abre GPS nenhum, isto nunca fica `true` e a home continua como
/// sempre esteve.
final ValueNotifier<bool> tvdeCorridaControlaGps = ValueNotifier<bool>(false);

/// TVDE — Corrida ativa do motorista: a caminho → cheguei → iniciar →
/// finalizar. Reusa o stack de mapa do delivery (google_maps_flutter). A
/// posição do motorista vem do DriverStore (GPS já a correr na home).
class TvdeRideActiveScreen extends StatefulWidget {
  const TvdeRideActiveScreen({super.key});

  @override
  State<TvdeRideActiveScreen> createState() => _TvdeRideActiveScreenState();
}

class _TvdeRideActiveScreenState extends State<TvdeRideActiveScreen> {
  bool _navigatedToRate = false;

  /// [Ronda 2] Enquanto true, a corrida já está 'finalizada' mas o ecrã NÃO
  /// avança para a avaliação — falta o motorista ver o lembrete de cobrança.
  bool _collectReminderPending = false;

  /// Corrida atualmente renderizada — quando muda (back-to-back: finalizar
  /// ativa a corrida em fila no MESMO ecrã), o estado por-corrida reinicia.
  String? _rideId;

  /// [Item I] chat da corrida — ouvido para o badge de nao-lidas mesmo com o
  /// chat fechado. Guardamos a store para poder dar unlisten no dispose.
  TvdeChatStore? _chatStore;
  String? _chatRideId;

  /// M16/D2 — cartão do passageiro (RPC tvde_ride_passenger_card, só o
  /// motorista da corrida consegue ler). Best-effort.
  String? _passengerName;
  String? _passengerPhotoUrl;
  String? _passengerPhone;

  /// 4c — ticker de 1s enquanto 'motorista_chegou' para o temporizador de
  /// espera e para habilitar o no-show quando a janela passa.
  Timer? _waitTicker;

  // ── [CAMPO-02 · F1] Paradas adicionais do cliente ─────────────────────────
  /// Paradas ativas (read-only), ordenadas por seq. Vazia até carregar.
  List<TvdeRideStop> _stops = const [];

  /// Assinatura (id + nº de paradas) da última lista carregada — evita refetch
  /// a cada rebuild; muda quando o cliente adiciona/remove parada (realtime).
  String? _stopsKey;

  /// Assinatura do último desacordo lista-vs-linha já reparado. Impede que uma
  /// discordância persistente (servidor mesmo assim diferente) vire um ciclo de
  /// refetches.
  String? _staleFixKey;

  /// Ticker 1s enquanto houver parada alcançada com contagem a decorrer.
  Timer? _stopsTicker;

  /// Duração da espera grátis por parada (platform_settings; só informativo).
  int _stopTimerSeconds = 120;

  /// Tecto de paradas por corrida (`tvde_max_stops`). Guarda para o caso de
  /// virem mais paradas do que o permitido — usa as primeiras por `seq`.
  int _maxStops = 2;
  bool _stopTimerLoaded = false;

  /// Assinatura das paradas que já foram registadas como "acima do tecto".
  /// Sem isto o aviso saía em cada build — dezenas de linhas por segundo.
  String? _stopsIgnoradasKey;

  /// [Paragens na rota · 05/09] Pinos NUMERADOS das paragens, desenhados uma
  /// vez por (número, alcançada) e reutilizados. `_markers` corre dentro do
  /// build e não pode gerar bitmaps — por isso o cache é preenchido fora dele.
  /// Vazio na Web (`BitmapDescriptor.bytes` não existe lá) → cai nos pinos de
  /// cor, que continuam a distinguir paragem de recolha/destino.
  final Map<String, BitmapDescriptor> _stopIcons = <String, BitmapDescriptor>{};
  String? _stopIconsKey;

  // ── B2/B6 — rota real + ETA (mesmo DirectionsService/chave do estafeta) ────
  final DirectionsService _directions = DirectionsService();
  GoogleMapController? _mapCtrl;
  Set<Polyline> _routePolys = <Polyline>{};

  /// [nav 05/09] Rota COMPLETA como veio do Directions. É a fonte da verdade:
  /// a polilinha desenhada é recortada a partir daqui a cada leitura de GPS,
  /// nunca destruída — se o carro parar ou recuar, a linha reaparece certa.
  List<ll.LatLng> _routePoints = const [];

  /// ETA para o motorista (B6): até à recolha (a caminho) ou ao destino (viagem).
  String? _etaText;

  // [botoes-navbar-eta 31/08] ETA VIVO: a duração da rota desenhada é a fonte
  // enquanto fresca; velha (>45 s ou carro >150 m do ponto do pedido) cai no
  // fallback distância ÷ `eta_avg_speed_kmh` (platform_settings, fallback 28).
  // Recalcula a cada posição nova e, parado, num ticker de 30 s — o número
  // nunca congela no valor inicial.
  double? _routeEtaMin;
  DateTime? _routeEtaAt;
  LatLng? _routeEtaFrom;
  int _etaSpeedKmh = 28;
  bool _etaSpeedLoaded = false;
  Timer? _etaTicker;

  /// [nav 05/09] Assinatura da FASE (corrida + troço + nº de paradas) da última
  /// rota desenhada com sucesso. A posição do carro JÁ NÃO entra na chave: era
  /// isso que pedia rota nova a cada ~111 m (`toStringAsFixed(3)`), ou seja de
  /// 8 em 8 segundos a conduzir. Agora só se pede rota por fase nova, por falta
  /// de linha, ou por DESVIO real (ver `_maybeFetchRoute`).
  String? _routeKey;

  /// Assinatura da última fase TENTADA (mesmo que a chamada falhe). Serve para
  /// distinguir "fase nova, pede já" de "a mesma fase a retentar" — sem isto,
  /// uma falha do Directions voltava a parecer fase nova a cada frame.
  String? _routeAttemptKey;

  /// Instante da última TENTATIVA de rota. Impõe o intervalo mínimo entre
  /// recálculos (`tvde_nav_reroute_min_seconds`). Marcado no início da chamada,
  /// não no fim — uma chamada falhada também conta, senão volta a martelar.
  DateTime? _lastRouteFetchAt;

  /// [Perf] Já há um pedido de rota em voo (evita rajada de pedidos ao
  /// Directions quando um deles é lento ou falha).
  bool _routeFetchInFlight = false;

  /// [nav 05/09] Deteta que o carro saiu da linha (matemática pura em
  /// `lib/utils/route_deviation.dart`). Limites vêm de `platform_settings`.
  final OffRouteDetector _offRoute = OffRouteDetector();

  /// Onde começava a linha da última vez que a desenhámos. Serve para NÃO
  /// reenviar a polilinha inteira ao mapa quando o pé da perpendicular quase
  /// não andou (carro parado no semáforo, ruído de GPS) — aí o redesenho só
  /// custava canal e fazia a ponta da linha tremer.
  int? _drawnSeg;
  ll.LatLng? _drawnFrom;

  /// [Perf] Já há uma callback de pós-frame agendada (uma de cada vez).
  bool _afterFrameScheduled = false;

  /// [Item N] Seta verde rotativa do motorista (paridade com a home). Fallback
  /// à bolinha azul nativa enquanto não carrega e sempre na Web.
  BitmapDescriptor? _driverArrowIcon;
  double _bearing = 0;
  LatLng? _lastArrowPos;

  /// [PART1 2026-07-07] Follow heading-up contínuo (estilo Waze). A câmara
  /// segue o motorista e RODA com a direção de marcha. O gesto do utilizador
  /// pausa o seguimento; o botão mira volta a ligar. `_progCamMove` distingue
  /// movimento programático (nosso animateCamera) de gesto do dedo.
  bool _followCam = true;
  bool _progCamMove = false;

  /// [nav 05/09] GPS PRÓPRIO deste ecrã. O ecrã do motorista deixa de depender
  /// da posição interpolada do `DriverStore` (essa continua a existir e serve o
  /// mapa do CLIENTE — não foi tocada). Duas razões: (1) a home alimenta o
  /// store com `distanceFilter: 50`, ou seja um ponto a cada 50 m — o carro
  /// saltava meio quarteirão de cada vez; (2) o store notifica por qualquer
  /// motorista que se mexa, e o ecrã não tem de acordar por causa disso.
  StreamSubscription<Position>? _gps;
  LatLng? _gpsPos;

  /// [Uma corrida = uma stream · 05/09] Este ecrã assumiu o GPS (a stream da
  /// home está suspensa) → é ele que tem de alimentar o servidor.
  bool _donoDoGps = false;

  /// Última posição JÁ entregue ao servidor por este ecrã. O portão dos 50 m
  /// mede-se a partir daqui.
  LatLng? _ultimaEnviadaAoServidor;

  /// O MESMO `distanceFilter: 50` que a stream da home usava. É este número que
  /// garante que o servidor não passa a receber mais vezes do que recebia: o
  /// GPS deste ecrã é fino (3 m) para a navegação, mas ao servidor só sobe uma
  /// posição a cada 50 m, como antes.
  static const double _metrosEntreEnviosAoServidor = 50;

  /// Valores de navegação afináveis em `platform_settings` (categoria `tvde`).
  /// Os defaults abaixo são os valores que estavam cravados no código.
  double _navZoom = 17.5;
  double _navTilt = 45.0;
  int _camFollowMs = 900;
  int _rerouteMinSeconds = 15;
  bool _navSettingsLoaded = false;

  /// [PERF 2026-07-08] Conjunto de marcadores REUTILIZADO — não recriamos a
  /// identidade do Set (nem os Marker) a cada rebuild; só o reconstruímos
  /// quando a assinatura (fase/alvo/posição/bearing/ícone) muda de facto.
  Set<Marker> _mapMarkers = <Marker>{};
  String? _markersKey;

  /// [Bloco 6, 30/08] Painel arrastável controlado: em "Viagem em curso" abre
  /// RECOLHIDO por defeito (só a linha estado·ganho) com o mapa quase cheio —
  /// o "Finalizar viagem" deixa de ficar fora do alcance porque se puxa o
  /// painel quando se quer os botões. `_sheetExtent` é seguido para a mira
  /// ficar SEMPRE acima do painel, em qualquer estado.
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();
  double _sheetExtent = 0.30;
  bool _sheetCollapsedForTrip = false;

  @override
  void initState() {
    super.initState();
    _loadDriverArrowIcon();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Semente: enquanto o GPS local não dá o primeiro ponto, mostra a última
      // posição conhecida do store (não fica mapa vazio ao abrir).
      _semearPosicaoDoStore();
      _ensureNavSettingsLoaded();
      _startGps();
    });
    // [31/08] parado (GPS sem tick novo), o ETA reavalia-se na mesma a cada 30 s.
    _etaTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Rede de segurança: GPS local sem permissão/sinal → volta ao store, que
      // a home continua a alimentar (este ecrã é `push`, a home fica montada).
      if (_gpsPos == null) _semearPosicaoDoStore();
      final ride = context.read<TvdeDriverStore>().activeRide;
      final pos = _gpsPos;
      if (ride != null && pos != null) _updateEtaLive(ride, pos);
    });
  }

  void _semearPosicaoDoStore() {
    if (!mounted) return;
    final loc = context.read<DriverStore>().currentDriver?.location;
    if (loc == null) return;
    final atual = _gpsPos;
    if (atual != null &&
        atual.latitude == loc.latitude &&
        atual.longitude == loc.longitude) {
      return; // igual → não repinta à toa
    }
    setState(() => _gpsPos = LatLng(loc.latitude, loc.longitude));
  }

  /// [nav 05/09] Stream de GPS do próprio ecrã, cadência de navegação.
  /// `bestForNavigation` + filtro curto: a conduzir chegam pontos ~1×/s (a
  /// câmara encadeia animações de 900 ms e nunca congela entre elas); PARADO o
  /// filtro de distância cala o stream — sem ticks, sem bateria, sem tremer.
  Future<void> _startGps() async {
    if (kIsWeb) return; // na Web fica a semente do store (sem FGS/navegação)
    await _gps?.cancel();
    // [Bloco 3B · 05/09] Serviço em primeiro plano do próprio geolocator, que
    // é o que impede o Android de estrangular o GPS quando o motorista
    // minimiza a app a meio da corrida. É EXACTAMENTE o que as entregas já
    // fazem (`driver_map_screen.dart` ~344) e que faltava só aqui.
    //
    // Não se acrescenta `location` ao serviço do `flutter_foreground_task` no
    // manifest: esse é PARTILHADO com o parceiro (`RestaurantStore` arranca-o
    // quando a loja abre) e o plugin arranca-o com TODOS os tipos declarados —
    // um restaurante sem GPS concedido rebentaria com SecurityException.
    // Ver o comentário no AndroidManifest.xml.
    //
    // Mesma precisão e cadência que estavam aqui cravadas (bestForNavigation,
    // 3 m, 700 ms); e se a permissão faltar, o serviço devolve as definições
    // SEM a notificação em vez de rebentar.
    final settings = await TvdeCorridaLocalizacao.definicoesDeCorrida();
    if (!mounted) return;
    try {
      _gps = Geolocator.getPositionStream(locationSettings: settings).listen(
        (p) {
          // A ordem é deliberada: primeiro assume-se o GPS (o que suspende a
          // stream da home), e só depois se alimenta o servidor — nesta mesma
          // leitura. O servidor nunca fica um ciclo sem quem lhe escreva.
          _assumirGps();
          _alimentarServidor(p);
          _onGpsFix(LatLng(p.latitude, p.longitude));
        },
        onError: (Object _) {
          // GPS deste ecrã morreu a meio (utilizador desligou a localização).
          // DEVOLVE já o GPS à home — se ninguém escrever a posição, o
          // motorista sai do matching e deixa de receber corridas.
          _libertarGps();
        },
      );
    } catch (_) {
      // sem GPS local → o ecrã continua com a posição do store, e a home
      // mantém a stream dela (nunca chegámos a assumir nada).
      _libertarGps();
    }
  }

  /// [Uma corrida = uma stream · 05/09] Assume o GPS: a home suspende a dela.
  void _assumirGps() {
    if (_donoDoGps) return;
    _donoDoGps = true;
    tvdeCorridaControlaGps.value = true;
  }

  /// Devolve o GPS à home. Idempotente — corre no `dispose`, no erro da stream
  /// e no arranque falhado.
  void _libertarGps() {
    _donoDoGps = false;
    _ultimaEnviadaAoServidor = null;
    tvdeCorridaControlaGps.value = false;
  }

  /// [Uma corrida = uma stream · 05/09] Enquanto este ecrã é o dono do GPS, é
  /// ele que alimenta o servidor com a posição do motorista. Isso é a fonte do
  /// matching de corridas — ZONA PROTEGIDA: não se toca no motor, mas também
  /// não se pode deixar secar a água que ele bebe.
  ///
  /// **A cadência não sobe.** São os mesmos dois destinos de sempre, chamados
  /// tal e qual a home os chamava:
  ///  - `DriverStore.updateDriverLocation` → `drivers.lat/lng` (+
  ///    `orders.driver_lat`), com o travão de 5 s que já lá vive;
  ///  - `DriverLocationPingService.ping` → `driver_locations` via a RPC
  ///    `driver_update_location`, com o travão de 45 s. É um SINGLETON
  ///    partilhado com a home, portanto o relógio do travão é literalmente o
  ///    mesmo objecto — não há como este ecrã pingar mais depressa.
  ///
  /// Por cima disso fica o portão dos 50 m, que é o `distanceFilter: 50` da
  /// stream da home reproduzido à mão. Sem ele, o GPS de 3 m deste ecrã
  /// entregaria posições de segundo a segundo e, em trânsito lento, o travão de
  /// 5 s deixaria passar MAIS escritas do que a home fazia. Com ele, o servidor
  /// recebe o que sempre recebeu.
  void _alimentarServidor(Position p) {
    if (!_donoDoGps || !mounted) return;
    final pos = LatLng(p.latitude, p.longitude);
    final anterior = _ultimaEnviadaAoServidor;
    if (anterior != null &&
        Geolocator.distanceBetween(anterior.latitude, anterior.longitude,
                pos.latitude, pos.longitude) <
            _metrosEntreEnviosAoServidor) {
      return;
    }
    _ultimaEnviadaAoServidor = pos;
    final store = context.read<DriverStore>();
    store.updateDriverLocation(
        store.currentDriverId, ll.LatLng(pos.latitude, pos.longitude));
    unawaited(DriverLocationPingService.instance.ping(
      latitude: pos.latitude,
      longitude: pos.longitude,
      heading: p.heading.isFinite ? p.heading : null,
      speedKmh: p.speed.isFinite ? p.speed * 3.6 : null,
      isOnline: true,
    ));
  }

  @override
  void dispose() {
    _waitTicker?.cancel();
    _stopsTicker?.cancel();
    _etaTicker?.cancel();
    _gps?.cancel();
    _gps = null;
    // [Uma corrida = uma stream · 05/09] Devolve o GPS à home ANTES de o resto
    // do estado desaparecer. A home volta a abrir a stream dela e o servidor
    // continua a receber a posição sem intervalo.
    _libertarGps();
    _mapCtrl?.dispose();
    _directions.dispose();
    _sheetCtrl.dispose();
    if (_chatRideId != null) _chatStore?.unlisten(_chatRideId!);
    super.dispose();
  }

  /// [nav 05/09] O CORAÇÃO do mapa: uma leitura de GPS → um `setState`.
  /// Antes cada tick do store repintava o ecrã inteiro; agora repinta-se ao
  /// ritmo do GPS (~1×/s a conduzir, 0 parado) e faz-se tudo de uma vez:
  /// bearing suavizado, câmara, recorte da rota atrás do carro, teste de
  /// desvio, e só então (se for caso disso) um pedido novo ao Directions.
  void _onGpsFix(LatLng pos) {
    if (!mounted) return;
    _atualizarBearing(pos);
    // Uma única varredura da rota devolve as DUAS coisas de que precisamos:
    // o troço que falta (para desenhar) e a distância perpendicular à linha.
    final prog = _routePoints.length >= 2
        ? projetarNaRota(_routePoints, ll.LatLng(pos.latitude, pos.longitude))
        : null;
    final Set<Polyline>? novaLinha = prog != null && _deveRedesenharRota(prog)
        ? {_polylineDaRota(prog.aFrente)}
        : null;
    setState(() {
      _gpsPos = pos;
      if (novaLinha != null) _routePolys = novaLinha;
    });
    _followDriver(pos);
    final ride = context.read<TvdeDriverStore>().activeRide;
    if (ride == null) return;
    _updateEtaLive(ride, pos);
    // Desvio: só dispara depois de N leituras SEGUIDAS fora da linha.
    final saiuDaRota =
        prog != null && _offRoute.adicionarDistancia(prog.distanciaMetros);
    _maybeFetchRoute(ride, pos, offRoute: saiuDaRota);
  }

  /// [Bloco B 2026-07-04] Câmara estilo Waze no modo corrida ativa: zoom
  /// aproximado + tilt 45° (sensação 3D de seguir a rua). Este ecrã é SEMPRE
  /// "em corrida", por isso aplica-se sempre aqui (a home mantém o seu zoom).
  /// [4E 05/09] "leitura dinâmica pendente" FECHADA: zoom, tilt, duração do
  /// follow e intervalo mínimo de recálculo vêm todos de `platform_settings`
  /// (categoria `tvde`), com os valores antigos como fallback. Uma leitura por
  /// abertura de ecrã; falha de rede → fica o default, o mapa nunca pára por
  /// causa disto.
  Future<void> _ensureNavSettingsLoaded() async {
    if (_navSettingsLoaded) return;
    _navSettingsLoaded = true;
    try {
      final store = context.read<TvdeStore>();
      final zoom = await store.getSettingDouble('tvde_nav_zoom', 17.5);
      final tilt = await store.getSettingDouble('tvde_nav_tilt', 45.0);
      final offM = await store.getSettingInt('tvde_nav_offroute_meters', 45);
      final offN = await store.getSettingInt('tvde_nav_offroute_fixes', 3);
      final minS =
          await store.getSettingInt('tvde_nav_reroute_min_seconds', 15);
      final camMs = await store.getSettingInt('tvde_nav_camera_follow_ms', 900);
      if (!mounted) return;
      setState(() {
        _navZoom = zoom > 0 ? zoom : _navZoom;
        _navTilt = tilt >= 0 ? tilt : _navTilt;
        _rerouteMinSeconds = minS > 0 ? minS : _rerouteMinSeconds;
        _camFollowMs = camMs > 0 ? camMs : _camFollowMs;
      });
      _offRoute
        ..metrosLimite = offM > 0 ? offM.toDouble() : _offRoute.metrosLimite
        ..leiturasSeguidas =
            offN > 0 ? offN : _offRoute.leiturasSeguidas;
    } catch (_) {/* ficam os defaults */}
  }

  /// B5 — botão mira: recentra a câmara no motorista (zoom Waze) e RELIGA o
  /// seguimento heading-up (o gesto do utilizador tinha-o pausado).
  Future<void> _recenter(LatLng? driverPos, LatLng fallback) async {
    final c = _mapCtrl;
    if (c == null) return;
    _followCam = true;
    _progCamMove = true;
    final target = driverPos ?? fallback;
    await c.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: target,
        zoom: _navZoom,
        tilt: _navTilt,
        bearing: _bearing,
      ),
    ));
  }

  /// [PART1] Câmara segue o motorista com heading-up CONTÍNUO (Waze): a cada
  /// posição nova anima para o carro com o bearing atual → o mapa RODA quando
  /// o motorista vira. No-op se o utilizador pausou o seguimento (arrastou).
  void _followDriver(LatLng target) {
    final c = _mapCtrl;
    if (c == null || !_followCam) return;
    // [4C 05/09] SEM trava de 15 m / 1 s. A trava antiga existia porque a fonte
    // era o store interpolado (muitos ticks por segundo); com o GPS próprio a
    // fonte já é rala, e travar por cima dela era o "travando": a câmara
    // deslizava 400 ms e congelava os outros 600. Agora anima-se CADA leitura
    // com uma duração (900 ms) MAIOR do que o intervalo entre leituras
    // (~700 ms) — a animação seguinte começa antes de a anterior acabar e o
    // movimento encadeia, sem parar entre pontos.
    _progCamMove = true;
    c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: _navZoom,
          tilt: _navTilt,
          bearing: _bearing,
        ),
      ),
      duration: Duration(milliseconds: _camFollowMs),
    );
  }

  /// [Item N] Seta verde do motorista (igual à home). Off-Web apenas —
  /// BitmapDescriptor.bytes não existe na Web (fallback: bolinha azul nativa).
  Future<void> _loadDriverArrowIcon() async {
    if (kIsWeb) return;
    try {
      final bytes = await _createArrowIcon();
      if (!mounted) return;
      setState(() => _driverArrowIcon = BitmapDescriptor.bytes(bytes));
    } catch (_) {/* fallback: bolinha nativa */}
  }

  Future<Uint8List> _createArrowIcon() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = 56.0;
    final paint = Paint()..color = AppColors.primary;
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

  /// [Item N / PART1] Direção de marcha da seta, a partir de posições GPS
  /// consecutivas. O bearing só é fiável em MOVIMENTO: atualiza quando andou
  /// ≥ 5 m; parado mantém o último (não gira à toa).
  ///
  /// [4C 05/09] Agora SUAVIZADO — `novo*0.3 + antigo*0.7`. Ruído de GPS de
  /// poucos metros dava saltos de dezenas de graus e a câmara arrancava para os
  /// lados; com o filtro a rotação entra devagar. A soma é feita pela diferença
  /// angular curta (359° → 1° passa por 0°, não pelo caminho longo de 180°).
  ///
  /// Não faz `setState` — quem chama (`_onGpsFix`) já repinta uma vez por
  /// leitura; dois setState na mesma leitura era frame perdido de borla.
  void _atualizarBearing(LatLng driverPos) {
    final prev = _lastArrowPos;
    _lastArrowPos = driverPos;
    if (prev == null) return;
    final moved = Geolocator.distanceBetween(
        prev.latitude, prev.longitude, driverPos.latitude, driverPos.longitude);
    if (moved < 5) return;
    var bruto = Geolocator.bearingBetween(prev.latitude, prev.longitude,
        driverPos.latitude, driverPos.longitude);
    if (bruto < 0) bruto += 360;
    var delta = bruto - _bearing;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    var suave = _bearing + delta * 0.3;
    if (suave < 0) suave += 360;
    if (suave >= 360) suave -= 360;
    _bearing = suave;
  }

  /// [4B 05/09] Vale a pena reenviar a linha ao mapa? Só se o carro passou de
  /// segmento ou se o pé da perpendicular andou ≥ 5 m (a ~1 px/m neste zoom,
  /// menos do que isso fica escondido debaixo da seta). Parado, não redesenha.
  bool _deveRedesenharRota(ProgressoNaRota prog) {
    final seg = _drawnSeg;
    final de = _drawnFrom;
    final novoPe = prog.aFrente.isEmpty ? null : prog.aFrente.first;
    if (novoPe == null) return false;
    if (seg == null || de == null || seg != prog.indiceSegmento) {
      _drawnSeg = prog.indiceSegmento;
      _drawnFrom = novoPe;
      return true;
    }
    if (distanciaEntrePontosMetros(de, novoPe) < 5) return false;
    _drawnFrom = novoPe;
    return true;
  }

  /// B2 — a linha grossa da rota (sempre com o mesmo id, o mapa só troca os
  /// pontos). Recebe já o troço recortado à frente do carro.
  Polyline _polylineDaRota(List<ll.LatLng> pontos) => Polyline(
        polylineId: const PolylineId('tvde_route'),
        points: pontos.toGMaps(),
        color: AppColors.primary,
        width: 12, // B2 — linha grossa (cobre quase a largura da rua)
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      );

  /// B2/B6 — pede a rota real (rua a rua) do troço atual e atualiza a polyline
  /// grossa + o ETA. Troço: a caminho/chegou → motorista→recolha; em viagem →
  /// motorista→destino.
  ///
  /// [4A 05/09] REGRA NOVA. Antes a chave incluía a posição arredondada a 3
  /// casas (~111 m): a conduzir eram dezenas de pedidos HTTP por corrida, um a
  /// cada ~8 s, cada um a redesenhar a linha toda dentro de um `setState` — e
  /// mesmo assim NUNCA recalculava na hora certa, porque ninguém perguntava se
  /// o carro tinha saído da estrada. Agora pede-se rota só quando:
  ///   (a) a FASE muda (a caminho → em viagem) ou entra/sai uma paragem;
  ///   (b) não há linha nenhuma desenhada (primeira vez, ou falha anterior);
  ///   (c) o carro está mesmo FORA da rota ([offRoute], ver OffRouteDetector).
  /// (a) passa já; (b) e (c) respeitam `tvde_nav_reroute_min_seconds`.
  Future<void> _maybeFetchRoute(TvdeRide ride, LatLng? driverPos,
      {bool offRoute = false}) async {
    final target = ride.isInProgress
        ? ll.LatLng(ride.destLat, ride.destLng)
        : ll.LatLng(ride.originLat, ride.originLng);
    final fromLl = driverPos != null
        ? ll.LatLng(driverPos.latitude, driverPos.longitude)
        : ll.LatLng(ride.originLat, ride.originLng);
    // [Paragens na rota · 05/09] As paradas entram na ROTA. Só valem depois de
    // o cliente estar a bordo — antes disso o motorista vai buscá-lo e as
    // paradas dele ainda não estão no caminho.
    final emViagem = ride.isInProgress;
    final viaParadas = emViagem
        ? waypointsDasStops(_stops, maxStops: _maxStops)
        : const <ll.LatLng>[];
    _registarParagensIgnoradas();
    // Chave da FASE — sem posição lá dentro (era essa a fuga de pedidos).
    //
    // As paradas por fazer entram na chave (`chaveFaseComStops`): marcar
    // chegada a uma parada muda a chave, logo conta como fase nova e a rota
    // refaz-se JÁ para a seguinte, sem ficar presa pela trava dos
    // `tvde_nav_reroute_min_seconds`. É esse o comportamento certo — o
    // motorista acabou de arrancar da parada e precisa da linha nova agora, não
    // daqui a 15 segundos. Vale nos dois sentidos: o cliente que ACRESCENTA uma
    // paragem a meio vê a linha mudar no mesmo instante.
    final key = chaveFaseComStops(
      ride.id,
      emViagem: emViagem,
      stops: _stops,
      maxStops: _maxStops,
    );
    final faseNova = key != _routeAttemptKey;
    final temLinha = _routePoints.length >= 2 && key == _routeKey;
    final agora = DateTime.now();
    final ultima = _lastRouteFetchAt;
    final arrefeceu = ultima == null ||
        agora.difference(ultima).inSeconds >= _rerouteMinSeconds;
    if (!faseNova && !((offRoute || !temLinha) && arrefeceu)) return;
    // [Perf] Trava de concorrência: sem isto, uma chamada lenta ou falhada ao
    // Directions deixava passar um pedido novo por frame — dezenas de pedidos
    // HTTP em voo ao mesmo tempo (custo Google e frames perdidos a sério).
    if (_routeFetchInFlight) return;
    _routeFetchInFlight = true;
    // Marcado ANTES da chamada: uma tentativa falhada também tem de arrefecer,
    // senão o retry de "sem linha" volta a martelar o Directions frame a frame.
    _lastRouteFetchAt = agora;
    _routeAttemptKey = key;
    if (faseNova) _offRoute.reset(); // rota velha não conta como desvio
    try {
      final route = await _directions.fetchRoute(
        origin: fromLl,
        destination: target,
        waypoints: viaParadas,
      );
      if (!mounted || route == null || route.points.isEmpty) return;
      // [Item N] Só trava a chave DEPOIS de uma rota válida — antes, uma falha
      // transitória do Directions prendia a chave e a rota NUNCA voltava a
      // desenhar (o "sumiu depois do build"). Sem polyline ainda → retenta.
      _routeKey = key;
      _offRoute.reset(); // linha nova: o carro está em cima dela outra vez
      setState(() {
        _routePoints = List<ll.LatLng>.unmodifiable(route.points);
        // Linha nova → os índices do recorte anterior deixam de valer.
        _drawnSeg = null;
        _drawnFrom = null;
        // Já nasce recortada no carro, sem esperar pela leitura seguinte.
        List<ll.LatLng> aFrente = _routePoints;
        if (driverPos != null) {
          final prog = projetarNaRota(_routePoints,
              ll.LatLng(driverPos.latitude, driverPos.longitude));
          aFrente = prog.aFrente;
          _drawnSeg = prog.indiceSegmento;
          _drawnFrom = prog.aFrente.first;
        }
        _routePolys = {_polylineDaRota(aFrente)};
        // [31/08] regista a fonte do ETA vivo; o texto sai do _updateEtaLive.
        //
        // [Paragens na rota · 05/09] O Directions devolve só o tempo a ANDAR.
        // Falta o tempo PARADO em cada parada que ainda falta — dois minutos
        // por parada, por `tvde_stop_timer_seconds`. Sem esta soma, uma corrida
        // com duas paradas prometia chegar quatro minutos antes do possível.
        final etaMin =
            route.durationMinutes + (emViagem ? _minutosParadosPendentes : 0);
        _routeEtaMin = etaMin;
        _routeEtaAt = DateTime.now();
        _routeEtaFrom = driverPos;
        final mins = etaMin.round();
        _etaText = ride.isInProgress
            ? 'Chegada ao destino em ~$mins min'
            : 'Recolha em ~$mins min';
      });
    } catch (_) {
      // Falha (offline/sem chave) → mantém o mapa sem rota; haversine é fallback.
    } finally {
      _routeFetchInFlight = false;
    }
  }

  /// [31/08] Lê `eta_avg_speed_kmh` uma vez (fallback 28). Nada cravado.
  Future<void> _ensureEtaSpeedLoaded() async {
    if (_etaSpeedLoaded) return;
    _etaSpeedLoaded = true;
    try {
      final v = await context
          .read<TvdeStore>()
          .getSettingInt('eta_avg_speed_kmh', 28);
      if (mounted && v > 0) setState(() => _etaSpeedKmh = v);
    } catch (_) {/* mantém o fallback */}
  }

  /// [31/08] Recalcula o ETA mostrado a partir da posição ATUAL. Fonte: rota
  /// fresca (ver campos _routeEta*); fallback: distância ÷ velocidade média.
  /// Só faz setState quando o texto muda — corre em ticks frequentes.
  void _updateEtaLive(TvdeRide ride, LatLng? pos) {
    if (pos == null) return;
    if (!(ride.isOnTheWay || ride.hasArrived || ride.isInProgress)) return;
    final target = ride.isInProgress
        ? LatLng(ride.destLat, ride.destLng)
        : LatLng(ride.originLat, ride.originLng);
    double minutes;
    final at = _routeEtaAt;
    final from = _routeEtaFrom;
    final routeMin = _routeEtaMin;
    final decorridoMin =
        at == null ? null : DateTime.now().difference(at).inSeconds / 60.0;
    final fresh = routeMin != null &&
        at != null &&
        from != null &&
        decorridoMin! < 0.75 && // 45 s
        Geolocator.distanceBetween(from.latitude, from.longitude,
                pos.latitude, pos.longitude) <
            150;
    // [4A 05/09] Nível do meio, novo. Com o recálculo por desvio a rota passa a
    // viver muito mais tempo (é esse o objetivo), e sem isto o ETA caía sempre
    // no haversine ao fim de 45 s — pior do que era antes, porque antes a rota
    // era repedida de ~8 em ~8 s. Enquanto a linha desenhada continuar a ser a
    // que estamos a seguir, desconta-se o tempo já andado à duração da rota.
    final double restante = routeMin != null && decorridoMin != null
        ? routeMin - decorridoMin
        : -1.0;
    if (fresh) {
      minutes = routeMin;
    } else if (_routePoints.length >= 2 && restante > 0.5) {
      minutes = restante;
    } else {
      final km = Geolocator.distanceBetween(pos.latitude, pos.longitude,
              target.latitude, target.longitude) /
          1000.0;
      minutes = km / _etaSpeedKmh * 60;
    }
    var mins = minutes.ceil();
    if (mins < 1) mins = 1;
    final text = ride.isInProgress
        ? 'Chegada ao destino em ~$mins min'
        : 'Recolha em ~$mins min';
    if (text != _etaText && mounted) {
      setState(() => _etaText = text);
    }
  }

  void _onRideChanged(TvdeRide ride) {
    if (_rideId == ride.id) return;
    _rideId = ride.id;
    _navigatedToRate = false;
    // [Bloco 6] corrida nova (back-to-back) → o recolher-em-viagem reinicia.
    _sheetCollapsedForTrip = false;
    _passengerName = null;
    _passengerPhotoUrl = null;
    _passengerPhone = null;
    // [CAMPO-02 · F1] nova corrida → limpa paradas; o post-frame recarrega.
    _stops = const [];
    _stopsKey = null;
    _ensureStopTimerLoaded();
    // [Item I] passa a ouvir o chat desta corrida (badge de nao-lidas).
    final chat = context.read<TvdeChatStore>();
    if (_chatRideId != null && _chatRideId != ride.id) {
      chat.unlisten(_chatRideId!);
    }
    _chatStore = chat;
    chat.listen(ride.id);
    _chatRideId = ride.id;
    _loadPassenger(ride);
  }

  Future<void> _loadPassenger(TvdeRide ride) async {
    try {
      final res = await Supabase.instance.client
          .rpc('tvde_ride_passenger_card', params: {'p_ride_id': ride.id});
      if (!mounted || _rideId != ride.id) return;
      final row = (res is List && res.isNotEmpty)
          ? Map<String, dynamic>.from(res.first as Map)
          : null;
      if (row != null) {
        setState(() {
          _passengerName = (row['name'] as String?)?.trim();
          _passengerPhotoUrl = (row['photo_url'] as String?)?.trim();
          _passengerPhone = (row['phone'] as String?)?.trim();
        });
      }
    } catch (_) {/* best-effort */}
  }

  /// E — ligar ao passageiro (tel:), se o número existir.
  Future<void> _callPassenger() async {
    final phone = _passengerPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// E — abre o chat com o passageiro (scoped por corrida).
  void _openChat(TvdeRide ride) {
    // [Item I] abrir a conversa marca as recebidas como lidas → badge zera.
    context.read<TvdeChatStore>().markRead(ride.id, 'driver');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TvdeChatScreen(
          rideId: ride.id,
          myRole: 'driver',
          title: _passengerName ?? 'Passageiro',
          otherPhone: _passengerPhone,
        ),
      ),
    );
  }

  /// 4c — segundos desde o "cheguei". Null se ainda não chegou.
  int? _waitSeconds(TvdeRide ride) {
    if (!ride.hasArrived) return null;
    final at = ride.arrivedAt;
    if (at == null) return null;
    return DateTime.now().difference(at.toLocal()).inSeconds;
  }

  /// 4c — no-show habilita depois da janela (default 5 min). Corridas antigas
  /// sem arrived_at não ficam presas: habilita logo.
  bool _noShowUnlocked(TvdeRide ride) {
    if (!ride.hasArrived) return false;
    final s = _waitSeconds(ride);
    if (s == null) return true;
    final windowS =
        context.read<TvdeDriverStore>().noshowWaitMinutes * 60;
    return s >= windowS;
  }

  void _syncWaitTicker(TvdeRide ride) {
    if (ride.hasArrived) {
      _waitTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _waitTicker?.cancel();
      _waitTicker = null;
    }
  }

  // ── [CAMPO-02 · F1] Paradas adicionais ────────────────────────────────────

  /// Lê a duração da espera grátis e o tecto de paradas (platform_settings).
  /// Uma vez só; em erro mantém os defaults. Nada de valores mágicos na UI.
  Future<void> _ensureStopTimerLoaded() async {
    if (_stopTimerLoaded) return;
    _stopTimerLoaded = true;
    try {
      final store = context.read<TvdeStore>();
      final s = await store.getSettingInt('tvde_stop_timer_seconds', 120);
      final m = await store.getSettingInt('tvde_max_stops', 2);
      if (mounted) {
        setState(() {
          _stopTimerSeconds = s;
          _maxStops = m;
        });
      }
    } catch (_) {/* mantém os defaults */}
  }

  /// As paradas que ainda FALTAM, por ordem de `seq`.
  ///
  /// [Paragens na rota · 05/09] O cliente paga por cada parada
  /// (`tvde_stop_fee_cents`) e até aqui a rota ignorava-as por completo:
  /// cobrava-se por um desvio que o mapa não fazia. Estas são as que entram
  /// como waypoints do Directions.
  ///
  /// Uma parada sai daqui assim que o motorista marca chegada (`reachedAt`) —
  /// a rota refaz-se para a seguinte, ou para o destino se já não houver.
  ///
  /// A matemática NÃO vive aqui: está em `lib/utils/tvde_stops_route.dart`,
  /// partilhada com o mapa do CLIENTE. Duas contas separadas para a mesma
  /// verdade era o caminho garantido para os dois mapas discordarem sobre por
  /// onde passa a corrida.
  List<TvdeRideStop> get _paragensPendentes =>
      stopsPendentes(_stops, maxStops: _maxStops);

  /// Minutos ainda por cumprir PARADO nas paradas que faltam.
  ///
  /// O ETA ao destino tem de contar com isto: uma rota que passa por duas
  /// paradas de 120 s chega quatro minutos mais tarde do que o Directions diz
  /// (a Google só conta o tempo a ANDAR). Sem esta soma, promete-se uma
  /// chegada que não é possível.
  double get _minutosParadosPendentes => minutosParadoPendente(
        _stops,
        stopTimerSeconds: _stopTimerSeconds,
        maxStops: _maxStops,
      );

  /// Regista, UMA vez por lista, as paradas que ficaram de fora do tecto
  /// `tvde_max_stops`. Não rebenta nada — a corrida segue com as primeiras por
  /// `seq` —, mas se isto aparecer no log há paradas a mais na corrida e
  /// alguém está a pagar por um desvio que o mapa não faz.
  void _registarParagensIgnoradas() {
    final fora = stopsIgnoradas(_stops, maxStops: _maxStops);
    if (fora.isEmpty) {
      _stopsIgnoradasKey = null;
      return;
    }
    final chave = fora.map((s) => '${s.seq}:${s.id}').join(',');
    if (chave == _stopsIgnoradasKey) return;
    _stopsIgnoradasKey = chave;
    debugPrint('[tvde] paragens ACIMA do tecto tvde_max_stops=$_maxStops '
        'ficaram fora da rota: $chave');
  }

  /// As paragens a DESENHAR no mapa, por ordem de `seq`: as que faltam (as
  /// mesmas que entram na rota) mais as já feitas.
  ///
  /// A numeração sai da posição nesta lista, por isso é ESTÁVEL: a paragem 1
  /// continua a ser a 1 depois de o motorista lá chegar. Se a numeração viesse
  /// só das pendentes, a paragem 2 passava a chamar-se 1 no instante em que a
  /// primeira ficava feita — exactamente quando o motorista está a olhar.
  ///
  /// Vazia enquanto o cliente não está a bordo: aí a linha vai para a recolha e
  /// as paragens ainda não fazem parte do caminho. Pinos que a linha não
  /// visita seriam uma promessa falsa.
  List<TvdeRideStop> _paragensDoMapa(TvdeRide ride) {
    if (!ride.isInProgress) return const <TvdeRideStop>[];
    final naRota = _paragensPendentes.map((s) => s.id).toSet();
    return _stops.where((s) => s.reached || naRota.contains(s.id)).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
  }

  /// Desenha (uma vez por número+estado) os pinos numerados das paragens.
  /// Corre FORA do build — `_markers` só lê o cache. Na Web não corre:
  /// `BitmapDescriptor.bytes` não existe lá e os pinos de cor cobrem o caso.
  Future<void> _ensureStopIcons(List<TvdeRideStop> paragens) async {
    if (kIsWeb || paragens.isEmpty) return;
    final chave = paragens.map((s) => s.reached ? 'v' : '.').join();
    if (chave == _stopIconsKey) return;
    // Marcado ANTES de desenhar: se o desenho falhar, fica o pino de cor e não
    // se tenta outra vez a cada frame (o telemóvel do Danilo tem 4 GB).
    _stopIconsKey = chave;
    try {
      var mudou = false;
      for (var i = 0; i < paragens.length; i++) {
        final k = '${i + 1}|${paragens[i].reached}';
        if (_stopIcons.containsKey(k)) continue;
        final bytes = await _createStopIcon(i + 1, feita: paragens[i].reached);
        if (!mounted) return;
        _stopIcons[k] = BitmapDescriptor.bytes(bytes);
        mudou = true;
      }
      // O `_stopIcons.length` faz parte da assinatura dos marcadores, por isso
      // este setState é o que troca os pinos de cor pelos numerados.
      if (mudou && mounted) setState(() {});
    } catch (_) {/* fallback: os pinos de cor já desenhados */}
  }

  /// Um pino redondo com o NÚMERO da paragem. Azul = ainda falta;
  /// cinzento = já foi feita. Mesma técnica da seta verde do motorista.
  Future<Uint8List> _createStopIcon(int numero, {required bool feita}) async {
    const size = 72.0;
    const centro = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      centro,
      size / 2 - 4,
      Paint()..color = feita ? const Color(0xFF9CA3AF) : const Color(0xFF2563EB),
    );
    canvas.drawCircle(
      centro,
      size / 2 - 4,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: '$numero',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 38,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(centro.dx - tp.width / 2, centro.dy - tp.height / 2),
    );
    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  /// Recarrega as paradas quando muda a corrida ou o nº de paradas (o cliente
  /// adicionou/removeu — chega pelo realtime da corrida, mesmo gancho do build).
  void _maybeReloadStops(TvdeRide ride) {
    // [Ronda 2] Carrega SEMPRE a lista à primeira vez que se vê a corrida, mesmo
    // com `extraStopsCount == 0`. Antes saía-se já aqui — e era exactamente no
    // caso em que a linha estava velha (a dizer 0 paradas) que mais fazia falta
    // ir ver ao servidor. Sem lista não havia como perceber que a linha mentia.
    final key = '${ride.id}|${ride.extraStopsCount}';
    if (key == _stopsKey) return;
    _stopsKey = key;
    _loadStops(ride);
  }

  Future<void> _loadStops(TvdeRide ride) async {
    try {
      final stops = await context.read<TvdeStore>().fetchRideStops(ride.id);
      if (!mounted || _rideId != ride.id) return;
      setState(() => _stops = stops);
      // [Ronda 2] A lista vem do servidor agora; a linha da corrida vem do
      // realtime e pode ter ficado para trás (app em background quando o cliente
      // pagou a parada). É da LINHA que sai o "COBRAR EM DINHEIRO" — se as duas
      // discordarem, quem manda é o servidor: puxa a linha outra vez. É esta a
      // diferença entre o motorista recolher €8 e recolher os €10 que são devidos.
      if (stops.length != ride.extraStopsCount && _staleFixKey != _stopsKey) {
        _staleFixKey = _stopsKey;
        unawaited(context.read<TvdeDriverStore>().loadCurrent());
      }
    } catch (_) {/* best-effort — UI fica sem lista, nunca crasha */}
  }

  /// Motorista marca chegada à parada → arranca o timer informativo. Recarrega
  /// para obter o reached_at do servidor (a fonte da verdade do countdown).
  Future<void> _reachStop(TvdeRide ride, TvdeRideStop stop) async {
    try {
      await context
          .read<TvdeStore>()
          .reachStop(ride.id, stop.id)
          .timeout(kAcaoTimeout);
      await _loadStops(ride);
    } catch (e) {
      await _falhouAcao(e, rideId: ride.id);
    }
  }

  /// Segundos restantes da espera grátis de uma parada alcançada (0 = concluída).
  int _stopRemaining(TvdeRideStop stop) {
    final at = stop.reachedAt;
    if (at == null) return _stopTimerSeconds;
    final rem =
        _stopTimerSeconds - DateTime.now().difference(at.toLocal()).inSeconds;
    return rem > 0 ? rem : 0;
  }

  void _syncStopsTicker() {
    final counting = _stops.any((s) => s.reached && _stopRemaining(s) > 0);
    if (counting) {
      _stopsTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _stopsTicker?.cancel();
      _stopsTicker = null;
    }
  }

  /// [Item N] Um só pino LARANJA no alvo atual (recolha até ao pickup, destino
  /// em viagem) + a SETA verde do motorista (paridade com a home). Sem o pino
  /// verde extra. Na Web (sem seta), a bolinha azul nativa marca o motorista.
  ///
  /// [PERF 2026-07-08] Reutiliza o mesmo Set entre rebuilds — só o reconstrói
  /// quando a assinatura muda (fase/alvo, posição do motorista ~1 m, bearing,
  /// ícone). Evita alocar um Set + Marker novos a cada tick de interpolação do
  /// DriverStore (o build corre várias vezes por segundo).
  Set<Marker> _markers(TvdeRide ride, LatLng? driverPos) {
    final target = ride.isInProgress
        ? LatLng(ride.destLat, ride.destLng)
        : LatLng(ride.originLat, ride.originLng);
    final label = ride.isInProgress
        ? (ride.destLabel ?? 'Destino')
        : (ride.originLabel ?? 'Recolha');
    // Assinatura barata: fase + alvo + posição do motorista (~5 casas ≈ 1 m) +
    // bearing (grau inteiro) + se a seta já carregou. Igual → devolve o cache.
    // As paragens entram na assinatura com o seu ESTADO: quando uma é
    // alcançada, o pino dela tem de mudar de aspeto na mesma volta em que sai
    // da rota. O tamanho do cache de ícones também entra — sem isso os pinos
    // numerados só apareciam no rebuild seguinte ao desenho dos bitmaps.
    final paradas = _paragensDoMapa(ride);
    final key = '${ride.isInProgress}|$label|'
        '${target.latitude.toStringAsFixed(5)},${target.longitude.toStringAsFixed(5)}|'
        '${driverPos?.latitude.toStringAsFixed(5)},${driverPos?.longitude.toStringAsFixed(5)}|'
        '${_bearing.round()}|${_driverArrowIcon != null}|'
        '${paradas.map((s) => '${s.seq}${s.reached ? 'v' : '.'}').join(',')}|'
        '${_stopIcons.length}';
    if (key == _markersKey) return _mapMarkers;
    _markersKey = key;
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('target'),
        position: target,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: label),
      ),
    };
    // [Paragens na rota · 05/09] Pinos das paragens, NUMERADOS pela ordem em
    // que se fazem (1, 2...) e em azul — distintos do laranja da
    // recolha/destino e da seta verde do motorista. O número está desenhado no
    // pino, não escondido numa bolha que é preciso tocar: o motorista tem de
    // perceber de relance quantas faltam e por que ordem.
    //
    // As já feitas ficam no mapa em CINZENTO — some-las escondia ao motorista o
    // que ele acabou de fazer, e a meio de uma corrida com duas paragens é isso
    // que responde à pergunta "esta é a primeira ou a segunda?".
    for (var i = 0; i < paradas.length; i++) {
      final s = paradas[i];
      final numero = i + 1;
      final redondo = _stopIcons['$numero|${s.reached}'];
      markers.add(Marker(
        markerId: MarkerId('paragem-${s.id}'),
        position: LatLng(s.lat, s.lng),
        icon: redondo ??
            BitmapDescriptor.defaultMarkerWithHue(s.reached
                ? BitmapDescriptor.hueViolet
                : BitmapDescriptor.hueAzure),
        // O pino redondo assenta pelo CENTRO; o de recurso é uma gota e assenta
        // pela ponta (o anchor por omissão).
        anchor: redondo != null ? const Offset(0.5, 0.5) : const Offset(0.5, 1),
        // `zIndex` (double) ficou deprecated: em algumas plataformas era
        // truncado para int e a ordem dos pinos saía instável.
        zIndexInt: s.reached ? 1 : 2, // a que falta fica por cima da já feita
        infoWindow: InfoWindow(
          title: s.reached
              ? 'Paragem $numero de ${paradas.length} — feita'
              : 'Paragem $numero de ${paradas.length}',
          snippet: s.label,
        ),
      ));
    }
    if (driverPos != null && _driverArrowIcon != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: driverPos,
        rotation: _bearing,
        icon: _driverArrowIcon!,
        anchor: const Offset(0.5, 0.5),
        flat: true,
      ));
    }
    _mapMarkers = markers;
    return _mapMarkers;
  }

  /// [Fix 2026-08-20] Botão "Vou a caminho" do painel, para a reserva que ainda
  /// está em `motorista_atribuido`. É a MESMA RPC do botão da notificação —
  /// idempotente, por isso as duas convivem.
  Future<void> _confirmarReservaACaminho(TvdeRide ride) async {
    final store = context.read<TvdeDriverStore>();
    try {
      final ok = await store.reservationReady(ride.id);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Não consegui confirmar. Atualiza e tenta outra vez.')));
        await _recarregarDoServidor();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Confirmado. Vai a caminho da recolha.')));
      // O servidor promove a corrida a 'motorista_a_caminho'; reler para o
      // painel passar logo ao botão certo.
      await store.loadCurrent();
      if (!mounted) return;
      await NavigationService.openNavigationOptions(
        context,
        ll.LatLng(ride.originLat, ride.originLng),
      );
    } catch (e) {
      await _falhouAcao(e, rideId: ride.id);
    }
  }

  /// [Bloco 4.4 — 2026-09-05] Devolver a reserva à Bora, com confirmação.
  ///
  /// A ideia é o motorista poder dizer cedo "não vou conseguir", em vez de
  /// segurar a reserva até o servidor lha tirar aos 5 minutos. Pergunta-se
  /// primeiro porque não tem volta: quem devolve perde-a.
  Future<void> _devolverReserva(TvdeRide ride) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Devolver esta reserva?'),
        content: const Text(
            'A Bora procura outro motorista. Deixas de ficar com esta corrida '
            'e não perdes nada por devolveres — vale mais avisares agora do que '
            'o cliente ficar à espera.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Fico com ela')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Devolver')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      final ok = await context
          .read<TvdeDriverStore>()
          .releaseReservation(ride.id, motivo: 'o motorista devolveu a reserva');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Reserva devolvida. A Bora procura outro motorista.'
              : 'Não consegui devolver. Atualiza e tenta outra vez.')));
      if (!ok) await _recarregarDoServidor();
    } catch (e) {
      await _falhouAcao(e, rideId: ride.id);
    }
  }

  /// [PADRAO_BORA 3.13 · 05/09] Guarda LOCAL das acções deste ecrã.
  ///
  /// Substitui o `busy` GLOBAL do `TvdeDriverStore`, que dezenas de operações
  /// mexem: bastava um refresh ou um poll a meio para o "Cheguei", o "Iniciar"
  /// ou o "Finalizar" nascerem desligados — o motorista com o passageiro ao
  /// lado e o botão morto.
  ///
  /// Protege MELHOR do que o global contra duplo disparo, e isso aqui importa:
  /// o `_finish` mede a distância real da rota, que dirige o preço final. Um
  /// guarda específico da acção não pode ser destravado por outra operação a
  /// terminar antes desta — o global podia.
  bool _agindo = false;

  Future<void> _comGuarda(Future<void> Function() accao) async {
    if (_agindo) return;
    setState(() => _agindo = true);
    try {
      await accao();
    } finally {
      // Reposto SEMPRE, também em erro: um botão a rodar para sempre é o
      // mesmo defeito por outra porta.
      if (mounted) setState(() => _agindo = false);
    }
  }

  Future<void> _arrived(TvdeRide ride) => _comGuarda(() async {
        try {
          await context.read<TvdeDriverStore>().markArrived(ride.id);
        } catch (e) {
          await _falhouAcao(e, rideId: ride.id);
        }
      });

  Future<void> _start(TvdeRide ride) => _comGuarda(() async {
        try {
          await context.read<TvdeDriverStore>().startRide(ride.id);
        } catch (e) {
          await _falhouAcao(e, rideId: ride.id);
        }
      });

  /// Abre a navegação externa (Google Maps/Waze). A caminho → até à recolha;
  /// em viagem → até ao destino. Reusa o mesmo helper do delivery.
  Future<void> _navigate(TvdeRide ride) async {
    final target = ride.isInProgress
        ? ll.LatLng(ride.destLat, ride.destLng)
        : ll.LatLng(ride.originLat, ride.originLng);
    await NavigationService.openNavigationOptions(context, target);
  }

  /// Finalizar corrida — envolvido no guarda local. O corpo NÃO foi tocado:
  /// mede a distância real da rota, que dirige o preço final, e isso é zona de
  /// dinheiro. Só se lhe pôs a trava de re-entrada à volta.
  Future<void> _finish(TvdeRide ride) =>
      _comGuarda(() => _finishInterno(ride));

  Future<void> _finishInterno(TvdeRide ride) async {
    try {
      // B1 — distância REAL de ROTA recolha→destino (DirectionsService, mesma
      // chave do estafeta). Fallback: estimativa guardada (haversine) se a rota
      // falhar (offline/erro API). A fonte fica registada no ride.
      final store = context.read<TvdeDriverStore>();
      double km = ride.estDistanceKm;
      String source = 'haversine';
      // [Item D] distância final = ROTA real (dirige o preço final). 2 tentativas
      // porque o Directions falha às vezes de forma transitória; sem isto o
      // fallback usa a estimativa (que ja pode ser linha reta) e subestima.
      for (var attempt = 0; attempt < 2 && source == 'haversine'; attempt++) {
        try {
          final route = await _directions.fetchRoute(
            origin: ll.LatLng(ride.originLat, ride.originLng),
            destination: ll.LatLng(ride.destLat, ride.destLng),
          );
          if (route != null && route.distanceKm > 0) {
            km = double.parse(route.distanceKm.toStringAsFixed(2));
            source = 'route';
          }
        } catch (_) {
          // mantém a estimativa guardada; volta a tentar se ainda houver tentativa
        }
      }
      // [Ronda 2] Segura a ida para a avaliação até o lembrete de cobrança ser
      // visto. Sem isto o `pushReplacement` do `_goToRate` (post-frame, assim
      // que a corrida fica 'finalizada') trocava a rota por baixo do diálogo.
      _collectReminderPending = true;
      final finished =
          await store.finishRide(ride.id, km, distanceSource: source);
      if (!mounted) return;
      await _showCollectReminder(finished);
      if (!mounted) return;
      // Back-to-back: se o backend ativou a corrida em fila, o ecrã transita
      // para ela (mesma tela) — mostra o ganho num aviso e NÃO vai à avaliação.
      final next = store.activeRide;
      if (next != null && next.id != ride.id && next.isLive) {
        final earn =
            ((finished.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Corrida finalizada — ganhaste €$earn. Próxima corrida ativada.')));
      }
    } catch (e) {
      if (mounted) setState(() => _collectReminderPending = false);
      await _falhouAcao(e, rideId: ride.id);
    }
  }

  /// [Ronda 2] Lembrete impossível de ignorar, no único momento que interessa:
  /// o passageiro ainda está no carro. O valor sai de [TvdeFareView] — a MESMA
  /// fonte do badge e do ecrã do cliente — e nunca de `final_fare_cents`, que
  /// numa perna do pacote traz só as paradas (mostraria €2 em vez do total).
  Future<void> _showCollectReminder(TvdeRide finished) async {
    try {
      final pkg = finished.isRoundtripLeg
          ? await TvdeRoundtripPrice.loadForRide(
              context.read<TvdeStore>(), finished)
          : TvdeRoundtripPrice.fallbackCents;
      if (!mounted) return;
      final fare = TvdeFareView.of(finished, packageCents: pkg);
      await showCollectReminderDialog(
        context,
        state: fare.driverCollectCents > 0
            ? CollectState.collectCash
            : (fare.coveredByPlan
                ? CollectState.coveredByPlan
                : CollectState.paidOnline),
        amountCents: fare.driverCollectCents,
        earnedCents: finished.driverEarnCents ?? 0,
      );
    } catch (_) {/* o lembrete nunca pode impedir o fecho da corrida */}
    if (mounted) setState(() => _collectReminderPending = false);
  }

  Future<void> _cancel(TvdeRide ride, {required bool noShow}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(noShow ? 'Passageiro não compareceu?' : 'Cancelar corrida?'),
        content: Text(noShow
            ? 'Marca como "não compareceu" se o passageiro não apareceu no local.'
            : 'Tens a certeza que queres cancelar esta corrida?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final store = context.read<TvdeDriverStore>();
      await store.cancelRide(ride.id, noShow: noShow);
      if (!mounted) return;
      // Parte 8 (rodada 2) — confirma ao motorista o resultado do no-show: a taxa
      // de espera é creditada server-side (tvde_cancel_ride actor=no_show). Sem
      // hardcode do valor (a setting manda) — só informa que foi creditada.
      if (noShow) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Registado: passageiro não compareceu. A taxa de espera foi creditada a ti.')));
      }
      // Back-to-back: se a fila foi ativada pelo cancelamento, fica no ecrã
      // (a corrida ativada é renderizada); caso contrário volta à home.
      final next = store.activeRide;
      if (next != null && next.id != ride.id && next.isLive) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Próxima corrida na fila ativada.')));
        return;
      }
      store.clearActive();
      Navigator.of(context).maybePop();
    } catch (e) {
      await _falhouAcao(e, rideId: ride.id);
    }
  }

  /// [Fix botão preso 2026-08-20] Antes isto era um snackbar com o erro cru
  /// (`Não foi possível: PostgrestException(...)`) e mais nada: o ecrã ficava
  /// exactamente como estava, a mostrar um estado que já não era verdade. E se
  /// a RPC nem chegava a responder, o `busy` do store nunca baixava e todos os
  /// botões ficavam a girar para sempre.
  ///
  /// Agora, em qualquer falha de acção: (1) frase em português simples que diz
  /// o que aconteceu e o que fazer; (2) o estado é relido do SERVIDOR, porque a
  /// acção pode ter-se aplicado e só a resposta se ter perdido — o ecrã tem de
  /// mostrar a verdade, não a suposição; (3) se a corrida já não existe, sai do
  /// ecrã em vez de deixar o motorista preso.
  Future<void> _falhouAcao(Object e, {String? rideId}) async {
    if (!mounted) return;
    final store = context.read<TvdeDriverStore>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagemDeFalhaDeAcao(e,
            trabalho: TrabalhoEmCurso.corrida)),
      ),
    );

    try {
      await store.loadCurrent();
    } catch (_) {/* best-effort: sem rede, fica o que já estava */}
    if (!mounted) return;

    // Sair do ecrã quando não há nada para mostrar. Dois casos:
    //  - o servidor já não devolve corrida activa nenhuma;
    //  - o servidor disse que ESTA corrida não existe e a recarga não a
    //    substituiu (ex.: a rede caiu logo a seguir). Sem isto, o motorista
    //    ficava num ecrã de uma corrida que já não existe.
    // Nota back-to-back: se a recarga trouxe OUTRA corrida, fica-se aqui —
    // é a corrida seguinte, e essa é para trabalhar.
    final activa = store.activeRide;
    final estaCorridaMorreu =
        rideId != null && falhaFechaOEcra(e) && activa?.id == rideId;
    if (activa == null || estaCorridaMorreu) {
      store.clearActive();
      Navigator.of(context).maybePop();
    }
  }

  /// Relê a corrida do servidor. É a saída do estado "A processar…", que antes
  /// era um botão morto.
  Future<void> _recarregarDoServidor() async {
    final store = context.read<TvdeDriverStore>();
    try {
      await store.loadCurrent();
    } catch (e) {
      await _falhouAcao(e);
      return;
    }
    if (!mounted) return;
    if (store.activeRide == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Já não tens nenhuma corrida a decorrer.')));
      Navigator.of(context).maybePop();
    }
  }

  void _goToRate(TvdeRide ride) {
    if (_navigatedToRate) return;
    _navigatedToRate = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => TvdeDriverRateScreen(ride: ride)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    final ride = store.activeRide;
    // [4D 05/09] A posição vem do GPS PRÓPRIO deste ecrã (`_gpsPos`), já não de
    // `context.select<DriverStore>`. O store continua a interpolar as posições
    // — isso é o que faz o carro deslizar no mapa do CLIENTE e não se mexeu —,
    // mas este ecrã deixa de acordar a esse ritmo. Além disso a home alimenta o
    // store só de 50 em 50 m; aqui o carro anda de metros em metros.
    final LatLng? driverPos = _gpsPos;

    if (ride == null) {
      // Corrida terminou e foi limpa — volta à home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    _onRideChanged(ride);
    _syncWaitTicker(ride);
    _syncStopsTicker();
    // [Bloco 6, 30/08] Ao entrar em "Viagem em curso", recolhe o painel para a
    // linha única (estado · ganho) e dá o mapa inteiro — uma vez por corrida;
    // o motorista continua livre de o puxar quando quiser os botões.
    if (ride.isInProgress && !_sheetCollapsedForTrip) {
      _sheetCollapsedForTrip = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sheetCtrl.isAttached) {
          _sheetCtrl.animateTo(0.14,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      });
    }
    // [4A 05/09] Aqui trata-se só do que muda por ESTADO da corrida: fase nova
    // (a caminho → em viagem), paragens novas, ETA. O bearing e a câmara saíram
    // daqui — vivem em `_onGpsFix`, ao ritmo do GPS. `_maybeFetchRoute` já não
    // olha para a posição: se a fase não mudou e há linha, não pede nada.
    if (!_afterFrameScheduled) {
      _afterFrameScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _afterFrameScheduled = false;
        if (!mounted) return;
        _maybeFetchRoute(ride, driverPos);
        _maybeReloadStops(ride);
        // [Paragens na rota · 05/09] Os bitmaps numerados nascem aqui, fora do
        // build. É no-op enquanto a lista de paragens não mudar de estado.
        unawaited(_ensureStopIcons(_paragensDoMapa(ride)));
        // [31/08] ETA vivo: recalcula com a posição realtime (throttle
        // interno — só repinta quando o minuto muda).
        _ensureEtaSpeedLoaded();
        _updateEtaLive(ride, driverPos);
      });
    }

    // Finalizada → avaliar passageiro (sem fila; com fila o _finish transita).
    // [Ronda 2] Espera pelo lembrete de cobrança — só depois se muda de ecrã.
    if (ride.isFinished && !_collectReminderPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToRate(ride));
    } else if (ride.isCancelled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        store.clearActive();
        Navigator.of(context).maybePop();
      });
    }

    final center = LatLng(
      (ride.originLat + ride.destLat) / 2,
      (ride.originLng + ride.destLng) / 2,
    );

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Corrida',
        actions: [
          if (ride.isOnTheWay || ride.hasArrived)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'cancel') _cancel(ride, noShow: false);
                if (v == 'no_show') _cancel(ride, noShow: true);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'cancel', child: Text('Cancelar corrida')),
                if (ride.hasArrived)
                  PopupMenuItem(
                      value: 'no_show',
                      // 4c — só habilita depois da janela de espera (padrão
                      // Uber; default 5 min, configurável no admin).
                      enabled: _noShowUnlocked(ride),
                      child: const Text('Passageiro não compareceu')),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          // [Perf] RepaintBoundary: isola a camada do mapa do resto do ecrã —
          // os contadores de 1 s (espera/paradas) repintam o texto sem forçar
          // repintura da textura do mapa por baixo.
          RepaintBoundary(
            child: GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers(ride, driverPos),
            polylines: _routePolys, // B2 — rota real grossa
            myLocationEnabled: _driverArrowIcon == null, // [Item N] seta ou bolinha
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true, // [Item G] paridade com o mapa do estafeta
            mapToolbarEnabled: false,
            onMapCreated: (c) => _mapCtrl = c,
            // [PART1] Gesto do dedo pausa o seguimento (deixa explorar o mapa);
            // o nosso animateCamera (com _progCamMove) não conta como gesto.
            // [4C 05/09] A flag passa a ser CONSUMIDA no primeiro arranque de
            // câmara em vez de esperar pelo `onCameraIdle`: com as animações
            // encadeadas o mapa quase nunca fica parado, e à espera do idle a
            // flag ficava presa em `true` — o arrastar do dedo deixava de
            // pausar o seguimento. Cada `animateCamera` nosso gera exactamente
            // um arranque; gastamo-lo aqui, e o seguinte já é do utilizador.
            onCameraMoveStarted: () {
              if (_progCamMove) {
                _progCamMove = false;
                return;
              }
              if (_followCam) setState(() => _followCam = false);
            },
            onCameraIdle: () => _progCamMove = false,
            ),
          ),
          // B5 — botão mira (recentra no motorista), igual ao estafeta.
          // [Bloco 6, 30/08] Acompanha a altura REAL do painel (via
          // _sheetExtent) — antes ficava escondida atrás dele.
          Positioned(
            right: Spacing.md,
            bottom: MediaQuery.of(context).size.height * _sheetExtent +
                Spacing.md,
            child: FloatingActionButton.small(
              heroTag: 'tvde_recenter',
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              onPressed: () => _recenter(driverPos, center),
              child: const Icon(Icons.my_location),
            ),
          ),
          // Back-to-back: oferta compacta DURANTE a viagem (nunca modal
          // full-screen com passageiro a bordo — segurança). Som vem do push.
          if (store.offeredRide != null && ride.isInProgress)
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                child: _QueuedOfferBanner(offer: store.offeredRide!),
              ),
            ),
          // [Item N] Card arrastável (bottom sheet), igual ao delivery: puxar
          // para baixo encolhe (mostra só o essencial e liberta o mapa), puxar
          // para cima expande. O mapa (com a rota) ocupa o resto.
          // [Bloco 6, 30/08] Em viagem começa RECOLHIDO (mapa quase cheio); o
          // NotificationListener segue a altura para posicionar a mira.
          Positioned.fill(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (n) {
                if (mounted && (n.extent - _sheetExtent).abs() > 0.01) {
                  setState(() => _sheetExtent = n.extent);
                }
                return false;
              },
              child: DraggableScrollableSheet(
              controller: _sheetCtrl,
              initialChildSize: ride.isInProgress ? 0.14 : 0.30,
              minChildSize: 0.14,
              maxChildSize: 0.52,
              snap: true,
              snapSizes: const [0.14, 0.30, 0.52],
              builder: (ctx, scrollController) => Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(Radii.lg)),
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 16,
                        offset: Offset(0, -2)),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin:
                            const EdgeInsets.symmetric(vertical: Spacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // [PADRAO_BORA 3.13] `_agindo` LOCAL, não o `busy` global.
                    _ActionPanel(ride: ride, busy: _agindo, actions: this),
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

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.ride, required this.busy, required this.actions});
  final TvdeRide ride;
  final bool busy;
  final _TvdeRideActiveScreenState actions;

  @override
  Widget build(BuildContext context) {
    // [Item C] o motorista vê o SEU líquido (ganho), não o total do cliente.
    final net = ((ride.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    // [Item I] badge de mensagens por ler (lado do motorista).
    final unread = context.watch<TvdeChatStore>().unreadFor(ride.id, 'driver');

    String label;
    IconData icon;
    VoidCallback? onPressed;
    if (ride.isOnTheWay) {
      label = 'Cheguei ao passageiro';
      icon = Icons.where_to_vote;
      onPressed = busy ? null : () => actions._arrived(ride);
    } else if (ride.hasArrived) {
      label = 'Iniciar viagem';
      icon = Icons.play_arrow;
      onPressed = busy ? null : () => actions._start(ride);
    } else if (ride.isInProgress) {
      label = 'Finalizar viagem';
      icon = Icons.flag;
      onPressed = busy ? null : () => actions._finish(ride);
    } else if (ride.status == 'motorista_atribuido' && ride.isReservation) {
      // [Fix 2026-08-20] A reserva fica NESTE estado entre os 20 e os 10
      // minutos da hora (o sweep activa aos 20; aos 10 é que promove quem está
      // vivo a 'motorista_a_caminho'). O painel não tinha ramo para aqui e o
      // motorista via "A processar…" — sem perceber que só tinha de confirmar.
      label = 'Vou a caminho';
      icon = Icons.directions_car_filled;
      onPressed = busy ? null : () => actions._confirmarReservaACaminho(ride);
    } else if (ride.status == 'motorista_atribuido' && ride.isQueued) {
      // Back-to-back: usa o mesmo estado, mas não há nada a confirmar — esta
      // arranca sozinha quando a viagem actual terminar.
      label = 'Começa ao terminares esta viagem';
      icon = Icons.queue;
      onPressed = null;
    } else {
      // [Fix botão preso 2026-08-20] Rede para estados que o ecrã não sabe
      // tratar. Era um botão MORTO — sem acção, sem explicação, sem saída.
      label = 'A processar… toca para atualizar';
      icon = Icons.refresh;
      onPressed = busy ? null : () => actions._recarregarDoServidor();
    }

    // [botoes-navbar-eta 31/08] O conteúdo fica no Padding; os BOTÕES finais
    // saem para o BoraBottomActionBar — no Samsung do Danilo (navbar de 3
    // botões) o "Finalizar viagem" ficava tapado pela barra do sistema.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, 0),
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.directions_car, color: AppColors.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                // [Bloco 6] Estado + ETA na PRIMEIRA linha: é a única coisa
                // visível com o painel recolhido em viagem, e o ETA tem de lá
                // estar (padrão Waze/Uber).
                child: Text(
                    actions._etaText != null &&
                            (ride.isOnTheWay ||
                                ride.hasArrived ||
                                ride.isInProgress)
                        ? '${ride.statusLabel} · ${actions._etaText}'
                        : ride.statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Text('€$net',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text('${ride.originLabel ?? 'Recolha'} → ${ride.destLabel ?? 'Destino'}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          // [Fix 2026-08-20] Reserva ainda por confirmar: dizer a hora marcada
          // e quanto falta. Sem isto o motorista via só "Motorista atribuído"
          // e não sabia que a corrida é para daqui a bocado.
          if (ride.status == 'motorista_atribuido' &&
              ride.isReservation &&
              ride.scheduledAt != null) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                const Icon(Icons.schedule, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(avisoDaReserva(ride.scheduledAt!),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
              ],
            ),
            // [Bloco 4.4 — 2026-09-05] Devolver a reserva. A função do servidor
            // (`tvde_reservation_release`) já existia e estava provada; faltava
            // maneira de lhe chamar do telemóvel. Sem isto, o motorista que
            // percebe a meio que não vai conseguir não tinha como avisar — ou
            // segurava a reserva até ao corte automático, ou desaparecia.
            // Devolver cedo dá tempo à Bora de arranjar outro.
            const SizedBox(height: Spacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    busy ? null : () => actions._devolverReserva(ride),
                icon: const Icon(Icons.undo, size: 17),
                label: const Text('Devolver reserva'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          // PART2 — método de pagamento + quanto COBRAR ao passageiro (paridade
          // com o estafeta do delivery). Hoje as corridas são todas em dinheiro.
          const SizedBox(height: Spacing.sm),
          TvdePayBadge(ride: ride),
          // [Fase B] Pacote €8: separar o que ele GANHA do que o cliente PAGA.
          if (ride.isRoundtripLeg) ...[
            const SizedBox(height: Spacing.xs),
            TvdeRoundtripDriverNotice(ride: ride),
          ],
          // [CAMPO-02 · F1] ganho extra por paradas (some ao líquido do motorista).
          if (ride.extraStopsDriverCents > 0) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                const Icon(Icons.add_location_alt,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                    'Paradas: +€${(ride.extraStopsDriverCents / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          // B6 — ETA para o motorista (rota real). Escondido quando a viagem
          // terminou/processa ou a rota ainda não chegou.
          if (actions._etaText != null &&
              (ride.isOnTheWay || ride.hasArrived || ride.isInProgress)) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                const Icon(Icons.schedule,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(actions._etaText!,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          // M16/D2 — cartão do passageiro (foto + nome) + falar (chat/ligar).
          if (actions._passengerName != null) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  backgroundImage: (actions._passengerPhotoUrl != null &&
                          actions._passengerPhotoUrl!.isNotEmpty)
                      ? NetworkImage(actions._passengerPhotoUrl!)
                      : null,
                  child: (actions._passengerPhotoUrl == null ||
                          actions._passengerPhotoUrl!.isEmpty)
                      ? const Icon(Icons.person,
                          size: 18, color: AppColors.primary)
                      : null,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(actions._passengerName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: IconButton(
                    onPressed: () => actions._openChat(ride),
                    icon: const Icon(Icons.chat_bubble_outline),
                    color: AppColors.primary,
                    tooltip: 'Mensagem',
                  ),
                ),
                if (actions._passengerPhone != null &&
                    actions._passengerPhone!.isNotEmpty)
                  IconButton(
                    onPressed: actions._callPassenger,
                    icon: const Icon(Icons.call),
                    color: AppColors.primary,
                    tooltip: 'Ligar',
                  ),
              ],
            ),
          ],
          // [CAMPO-02 · F1] Paradas do cliente — lista numerada, "Cheguei à
          // parada" e countdown informativo de espera grátis. Só se houver.
          if (ride.hasExtraStops)
            _StopsSection(
              stops: actions._stops,
              timerSeconds: actions._stopTimerSeconds,
              busy: busy,
              onReach: (stop) => actions._reachStop(ride, stop),
            ),
          // 4c — temporizador de espera no pickup (padrão Uber).
          if (ride.hasArrived) ...[
            const SizedBox(height: Spacing.sm),
            _WaitChip(
              seconds: actions._waitSeconds(ride) ?? 0,
              unlocked: actions._noShowUnlocked(ride),
            ),
          ],
          // Back-to-back — indicador de corrida em fila.
          if (context.select<TvdeDriverStore, bool>(
              (s) => s.queuedRide != null)) ...[
            const SizedBox(height: Spacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.queue, size: 15, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Próxima corrida na fila',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
          ],
          ),
        ),
        // Navegar (Google Maps/Waze) + ação principal, no rodapé aprovado:
        // padding do sistema somado UMA vez, toque ≥56, largura total.
        BoraBottomActionBar(
          topPadding: Spacing.lg,
          children: [
            if (ride.isOnTheWay || ride.hasArrived || ride.isInProgress)
              OutlinedButton.icon(
                onPressed: () => actions._navigate(ride),
                icon: const Icon(Icons.navigation),
                label: Text(ride.isInProgress
                    ? 'Navegar até ao destino'
                    : 'Navegar até à recolha'),
                // D3 — botão arredondado (radius do design system).
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md)),
                ),
              ),
            BoraAccentButton(
              label: label,
              icon: icon,
              loading: busy,
              onPressed: onPressed,
            ),
          ],
        ),
      ],
    );
  }
}

/// [CAMPO-02 · F1] Secção "Paradas do cliente" — lista numerada das paradas
/// adicionais. Cada parada por alcançar tem "Cheguei à parada"; já alcançada
/// mostra o countdown informativo de espera grátis (não cobra, não bloqueia).
class _StopsSection extends StatelessWidget {
  const _StopsSection({
    required this.stops,
    required this.timerSeconds,
    required this.busy,
    required this.onReach,
  });

  final List<TvdeRideStop> stops;
  final int timerSeconds;
  final bool busy;
  final void Function(TvdeRideStop stop) onReach;

  @override
  Widget build(BuildContext context) {
    // Ainda a carregar (ou lista vazia) → nada a mostrar, sem espaço morto.
    if (stops.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.route, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text('Paradas do cliente',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          for (final stop in stops)
            _StopTile(
              stop: stop,
              remaining: _remaining(stop),
              busy: busy,
              onReach: () => onReach(stop),
            ),
        ],
      ),
    );
  }

  /// Segundos restantes da espera grátis (0 = concluída). Espelha o cálculo do
  /// ticker no state; usa timerSeconds (das settings) e reachedAt do servidor.
  int _remaining(TvdeRideStop stop) {
    final at = stop.reachedAt;
    if (at == null) return timerSeconds;
    final rem = timerSeconds - DateTime.now().difference(at.toLocal()).inSeconds;
    return rem > 0 ? rem : 0;
  }
}

/// [CAMPO-02 · F1] Uma linha da lista de paradas: nº + label, e o estado —
/// botão "Cheguei à parada" (por alcançar) ou countdown/"Espera concluída".
class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.remaining,
    required this.busy,
    required this.onReach,
  });

  final TvdeRideStop stop;
  final int remaining;
  final bool busy;
  final VoidCallback onReach;

  @override
  Widget build(BuildContext context) {
    final mm = (remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining % 60).toString().padLeft(2, '0');
    final hasLabel = stop.label != null && stop.label!.trim().isNotEmpty;
    final label = hasLabel ? stop.label!.trim() : 'Parada ${stop.seq}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stop.reached
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text('${stop.seq}',
                    style: TextStyle(
                        color: stop.reached ? Colors.white : AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              if (stop.reached)
                const Icon(Icons.check_circle,
                    size: 18, color: AppColors.primary),
            ],
          ),
          if (!stop.reached) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: busy ? null : onReach,
              icon: const Icon(Icons.where_to_vote, size: 18),
              label: const Text('Cheguei à parada'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side:
                    BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(remaining > 0 ? Icons.timer : Icons.check,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  remaining > 0 ? 'Espera grátis · $mm:$ss' : 'Espera concluída',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 4c — chip do temporizador de espera no pickup. Depois da janela, avisa que
/// o no-show ficou disponível (menu ⋮ no topo).
class _WaitChip extends StatelessWidget {
  const _WaitChip({required this.seconds, required this.unlocked});
  final int seconds;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: (unlocked ? AppColors.error : AppColors.primary)
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(unlocked ? Icons.person_off : Icons.timer,
              size: 15,
              color: unlocked ? AppColors.error : AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              unlocked
                  ? 'Espera $mm:$ss — podes marcar "não compareceu" (menu ⋮)'
                  : 'À espera do passageiro · $mm:$ss',
              style: TextStyle(
                  color: unlocked ? AppColors.error : AppColors.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Back-to-back — oferta COMPACTA durante a viagem (banner no topo): valor,
/// recolha e countdown, com aceitar/recusar. Nunca modal full-screen com
/// passageiro a bordo. O som vem do push (notify-tvde-driver, intacto).
class _QueuedOfferBanner extends StatefulWidget {
  const _QueuedOfferBanner({required this.offer});
  final TvdeRide offer;

  @override
  State<_QueuedOfferBanner> createState() => _QueuedOfferBannerState();
}

class _QueuedOfferBannerState extends State<_QueuedOfferBanner> {
  Timer? _ticker;
  int _secondsLeft = 25;

  @override
  void initState() {
    super.initState();
    _syncCountdown();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void didUpdateWidget(covariant _QueuedOfferBanner old) {
    super.didUpdateWidget(old);
    if (old.offer.id != widget.offer.id) _syncCountdown();
  }

  void _syncCountdown() {
    final exp = widget.offer.offerExpiresAt;
    _secondsLeft =
        exp == null ? 25 : exp.difference(DateTime.now()).inSeconds;
    if (_secondsLeft <= 0) _secondsLeft = 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// [Bloco 3C · 05/09] Guarda LOCAL desta oferta. Antes, os dois botões
  /// dependiam do `busy` GLOBAL do store: bastava outra operação a meio — um
  /// refresh, o ETA, um poll — para "Recusar" e "Aceitar" nascerem mortos.
  /// E esta oferta tem contagem decrescente: um botão morto durante alguns
  /// segundos é a oferta a expirar sozinha nas mãos do motorista. É a mesma
  /// cicatriz que prendeu um passageiro no ecrã de avaliação a 05/09/2026, e
  /// a mesma que já tinha sido paga uma vez no `tvde_offer_screen`.
  bool _respondendo = false;

  Future<void> _accept() async {
    if (_respondendo) return;
    setState(() => _respondendo = true);
    final store = context.read<TvdeDriverStore>();
    try {
      await store.acceptOffer(widget.offer.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Corrida em fila — inicia ao terminares esta viagem.')));
    } catch (_) {
      store.clearOffer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esta corrida já não está disponível.')));
    }
    if (mounted) setState(() => _respondendo = false);
  }

  Future<void> _reject() async {
    if (_respondendo) return;
    setState(() => _respondendo = true);
    final store = context.read<TvdeDriverStore>();
    try {
      await store.rejectOffer(widget.offer.id);
    } catch (_) {/* best-effort */}
    if (mounted) setState(() => _respondendo = false);
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    // [Item C] líquido do motorista (não o total do cliente) na oferta em fila.
    final net = ((offer.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    // Expirada (sweep roda ao próximo) — o realtime limpa; não renderiza lixo.
    if (_secondsLeft <= 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(Spacing.md),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryDeep,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.queue, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Próxima corrida perto do teu destino',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800)),
              ),
              Text('${_secondsLeft}s',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '€$net · ${offer.originLabel ?? 'Recolha próxima do destino'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _respondendo ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _respondendo ? null : _accept,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Aceitar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
