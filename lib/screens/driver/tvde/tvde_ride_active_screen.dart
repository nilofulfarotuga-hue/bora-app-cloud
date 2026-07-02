import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/directions_service.dart';
import '../../../services/navigation_service.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../utils/map_utils.dart';
import '../../../widgets/bora/bora.dart';
import '../../shared/tvde_chat_screen.dart';
import 'tvde_driver_rate_screen.dart';

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

  /// Corrida atualmente renderizada — quando muda (back-to-back: finalizar
  /// ativa a corrida em fila no MESMO ecrã), o estado por-corrida reinicia.
  String? _rideId;

  /// M16/D2 — cartão do passageiro (RPC tvde_ride_passenger_card, só o
  /// motorista da corrida consegue ler). Best-effort.
  String? _passengerName;
  String? _passengerPhotoUrl;
  String? _passengerPhone;

  /// 4c — ticker de 1s enquanto 'motorista_chegou' para o temporizador de
  /// espera e para habilitar o no-show quando a janela passa.
  Timer? _waitTicker;

  // ── B2/B6 — rota real + ETA (mesmo DirectionsService/chave do estafeta) ────
  final DirectionsService _directions = DirectionsService();
  GoogleMapController? _mapCtrl;
  Set<Polyline> _routePolys = <Polyline>{};

  /// ETA para o motorista (B6): até à recolha (a caminho) ou ao destino (viagem).
  String? _etaText;

  /// Assinatura (fase + posição grosseira) da última rota pedida — evita
  /// refazer o pedido Directions a cada rebuild/movimento pequeno.
  String? _routeKey;

  @override
  void dispose() {
    _waitTicker?.cancel();
    _mapCtrl?.dispose();
    _directions.dispose();
    super.dispose();
  }

  /// B5 — botão mira: recentra a câmara na posição do motorista.
  Future<void> _recenter(LatLng? driverPos, LatLng fallback) async {
    final c = _mapCtrl;
    if (c == null) return;
    await c.animateCamera(CameraUpdate.newLatLngZoom(driverPos ?? fallback, 15));
  }

  /// B2/B6 — pede a rota real (rua a rua) do troço atual e atualiza a polyline
  /// grossa + o ETA. Troço: a caminho/chegou → motorista→recolha; em viagem →
  /// motorista→destino. Idempotente por `_routeKey` (fase + posição ~100 m).
  Future<void> _maybeFetchRoute(TvdeRide ride, LatLng? driverPos) async {
    final target = ride.isInProgress
        ? ll.LatLng(ride.destLat, ride.destLng)
        : ll.LatLng(ride.originLat, ride.originLng);
    final fromLl = driverPos != null
        ? ll.LatLng(driverPos.latitude, driverPos.longitude)
        : ll.LatLng(ride.originLat, ride.originLng);
    // Chave grosseira: fase + origem arredondada a ~100 m + id da corrida.
    final key = '${ride.id}|${ride.isInProgress}|'
        '${fromLl.latitude.toStringAsFixed(3)},${fromLl.longitude.toStringAsFixed(3)}';
    if (key == _routeKey) return;
    _routeKey = key;
    try {
      final route =
          await _directions.fetchRoute(origin: fromLl, destination: target);
      if (!mounted || route == null || route.points.isEmpty) return;
      setState(() {
        _routePolys = {
          Polyline(
            polylineId: const PolylineId('tvde_route'),
            points: route.points.toGMaps(),
            color: AppColors.primary,
            width: 12, // B2 — linha grossa (cobre quase a largura da rua)
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        };
        final mins = route.durationMinutes.round();
        _etaText = ride.isInProgress
            ? 'Chegada ao destino em ~$mins min'
            : 'Recolha em ~$mins min';
      });
    } catch (_) {
      // Falha (offline/sem chave) → mantém o mapa sem rota; haversine é fallback.
    }
  }

  void _onRideChanged(TvdeRide ride) {
    if (_rideId == ride.id) return;
    _rideId = ride.id;
    _navigatedToRate = false;
    _passengerName = null;
    _passengerPhotoUrl = null;
    _passengerPhone = null;
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

  /// B4 — só recolha (verde) + destino (laranja). A posição do motorista é a
  /// BOLINHA azul nativa (myLocationEnabled), igual ao estafeta — sem pin extra.
  Set<Marker> _markers(TvdeRide ride) {
    return <Marker>{
      Marker(
        markerId: const MarkerId('origin'),
        position: LatLng(ride.originLat, ride.originLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: ride.originLabel ?? 'Recolha'),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: LatLng(ride.destLat, ride.destLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: ride.destLabel ?? 'Destino'),
      ),
    };
  }

  Future<void> _arrived(TvdeRide ride) async {
    try {
      await context.read<TvdeDriverStore>().markArrived(ride.id);
    } catch (e) {
      _err(e);
    }
  }

  Future<void> _start(TvdeRide ride) async {
    try {
      await context.read<TvdeDriverStore>().startRide(ride.id);
    } catch (e) {
      _err(e);
    }
  }

  /// Abre a navegação externa (Google Maps/Waze). A caminho → até à recolha;
  /// em viagem → até ao destino. Reusa o mesmo helper do delivery.
  Future<void> _navigate(TvdeRide ride) async {
    final target = ride.isInProgress
        ? ll.LatLng(ride.destLat, ride.destLng)
        : ll.LatLng(ride.originLat, ride.originLng);
    await NavigationService.openNavigationOptions(context, target);
  }

  Future<void> _finish(TvdeRide ride) async {
    try {
      // B1 — distância REAL de ROTA recolha→destino (DirectionsService, mesma
      // chave do estafeta). Fallback: estimativa guardada (haversine) se a rota
      // falhar (offline/erro API). A fonte fica registada no ride.
      final store = context.read<TvdeDriverStore>();
      double km = ride.estDistanceKm;
      String source = 'haversine';
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
        // mantém a estimativa guardada
      }
      final finished =
          await store.finishRide(ride.id, km, distanceSource: source);
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
      _err(e);
    }
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
      _err(e);
    }
  }

  void _err(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Não foi possível: $e')),
    );
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
    final ll.LatLng? driverLl =
        context.select<DriverStore, ll.LatLng?>((d) => d.currentDriver?.location);
    final LatLng? driverPos =
        driverLl == null ? null : LatLng(driverLl.latitude, driverLl.longitude);

    if (ride == null) {
      // Corrida terminou e foi limpa — volta à home.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    _onRideChanged(ride);
    _syncWaitTicker(ride);
    // B2/B6 — mantém a rota real + ETA atualizados (idempotente por _routeKey).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeFetchRoute(ride, driverPos));

    // Finalizada → avaliar passageiro (sem fila; com fila o _finish transita).
    if (ride.isFinished) {
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
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers(ride),
            polylines: _routePolys, // B2 — rota real grossa
            myLocationEnabled: true, // B4 — bolinha azul nativa (sem pin extra)
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) => _mapCtrl = c,
          ),
          // B5 — botão mira (recentra no motorista), igual ao estafeta.
          Positioned(
            right: Spacing.md,
            bottom: 200,
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
                child: _QueuedOfferBanner(
                  offer: store.offeredRide!,
                  busy: store.busy,
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ActionPanel(ride: ride, busy: store.busy, actions: this),
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
    final fare = (ride.displayFareCents / 100).toStringAsFixed(2);

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
    } else {
      label = 'A processar…';
      icon = Icons.hourglass_top;
      onPressed = null;
    }

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
          Row(
            children: [
              Icon(Icons.directions_car, color: AppColors.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(ride.statusLabel,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Text('€$fare',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text('${ride.originLabel ?? 'Recolha'} → ${ride.destLabel ?? 'Destino'}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                IconButton(
                  onPressed: () => actions._openChat(ride),
                  icon: const Icon(Icons.chat_bubble_outline),
                  color: AppColors.primary,
                  tooltip: 'Mensagem',
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
          const SizedBox(height: Spacing.lg),
          // Navegar (Google Maps/Waze) — estilo Uber Driver. Escondido quando a
          // viagem terminou/processa.
          if (ride.isOnTheWay || ride.hasArrived || ride.isInProgress) ...[
            OutlinedButton.icon(
              onPressed: () => actions._navigate(ride),
              icon: const Icon(Icons.navigation),
              label: Text(ride.isInProgress
                  ? 'Navegar até ao destino'
                  : 'Navegar até à recolha'),
              // D3 — botão arredondado (radius do design system, paridade UI).
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
              ),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          BoraAccentButton(
            label: label,
            icon: icon,
            loading: busy,
            onPressed: onPressed,
          ),
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
  const _QueuedOfferBanner({required this.offer, required this.busy});
  final TvdeRide offer;
  final bool busy;

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

  Future<void> _accept() async {
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
  }

  Future<void> _reject() async {
    final store = context.read<TvdeDriverStore>();
    try {
      await store.rejectOffer(widget.offer.id);
    } catch (_) {/* best-effort */}
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final fare = (offer.estFareCents / 100).toStringAsFixed(2);
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
            '€$fare · ${offer.originLabel ?? 'Recolha próxima do destino'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.busy ? null : _reject,
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
                  onPressed: widget.busy ? null : _accept,
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
