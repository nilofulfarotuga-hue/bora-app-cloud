import 'dart:async';
import 'dart:math' as math;

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
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../widgets/bora/bora.dart';
import '../../shared/tvde_chat_screen.dart';
import 'tvde_rate_screen.dart';

/// TVDE — Mapa em tempo real do estado da corrida (reusa google_maps_flutter,
/// o mesmo stack de mapa do delivery). Consome o realtime de tvde_rides
/// produzido pela Fase 2.
class TvdeRideTrackingScreen extends StatefulWidget {
  const TvdeRideTrackingScreen({super.key});

  @override
  State<TvdeRideTrackingScreen> createState() => _TvdeRideTrackingScreenState();
}

class _TvdeRideTrackingScreenState extends State<TvdeRideTrackingScreen> {
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

  /// C5 — mesma velocidade média do dispatch (30 km/h) para o ETA.
  static const double _avgSpeedKmh = 30.0;

  // ── B2 — rota real grossa recolha→destino (mesmo DirectionsService/chave). ──
  final DirectionsService _directions = DirectionsService();
  Set<Polyline> _routePolys = <Polyline>{};
  String? _routeKey;

  @override
  void initState() {
    super.initState();
    _driverPoll = Timer.periodic(const Duration(seconds: 5), (_) => _pollDriver());
  }

  @override
  void dispose() {
    _driverPoll?.cancel();
    _animTimer?.cancel();
    _map?.dispose();
    _directions.dispose();
    super.dispose();
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

  /// B5 — botão mira: recentra na posição do motorista (ou no ponto de recolha).
  Future<void> _recenter(TvdeRide ride) async {
    final c = _map;
    if (c == null) return;
    final target = _driverPos ?? LatLng(ride.originLat, ride.originLng);
    await c.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
  }

  /// C4 — animação suave do carro entre polls (12 passos × 80 ms, o mesmo
  /// padrão do DriverStore no delivery). Sem saltos de marker.
  void _setDriverPos(LatLng target) {
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
        if (lat != null && lng != null) _setDriverPos(LatLng(lat, lng));
      }
    } catch (_) {}
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

  /// E — abre o chat com o motorista (scoped por corrida).
  void _openChat(TvdeRide ride) {
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

  Future<void> _cancel(TvdeRide ride) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar corrida?'),
        content: const Text('Tens a certeza que queres cancelar esta corrida?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Não')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sim, cancelar')),
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível cancelar.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final ride = store.activeRide;

    if (ride == null) {
      return Scaffold(
        appBar: const BoraScreenAppBar(title: 'A tua corrida'),
        body: const Center(child: Text('Sem corrida ativa.')),
      );
    }

    _maybeGoToRate(ride);

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

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'A tua corrida'),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers(ride),
            polylines: _routePolys, // B2 — rota grossa recolha→destino
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) => _map = c,
          ),
          // B5 — botão mira (recentra no motorista/recolha).
          Positioned(
            right: Spacing.md,
            bottom: 200,
            child: FloatingActionButton.small(
              heroTag: 'tvde_client_recenter',
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              onPressed: () => _recenter(ride),
              child: const Icon(Icons.my_location),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _StatusPanel(
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
              onChat: () => _openChat(ride),
              onCall: _call,
              onCancel: () => _cancel(ride),
              onRetry: () => store.retryRide(),
              onClose: () {
                store.clearActiveRide();
                Navigator.pop(context);
              },
            ),
          ),
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
    required this.onChat,
    required this.onCall,
    required this.onCancel,
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
  final VoidCallback onChat;
  final VoidCallback onCall;
  final VoidCallback onCancel;
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
                            style: TextStyle(
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
              if (ride.isSearching)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(_icon(ride), color: AppColors.primary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(ride.statusLabel,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Text('€${(ride.displayFareCents / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            '${ride.originLabel ?? 'Recolha'} → ${ride.destLabel ?? 'Destino'}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          // Back-to-back — passageiro em fila: contexto claro, sem spinner.
          if (ride.isQueued && ride.isAssigned) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              'Serás o próximo: o motorista está a terminar uma viagem perto '
              'de ti e segue logo para a tua recolha.',
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          if (ride.isNoDriver) ...[
            Text(
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
            Text('Boa viagem! O valor final é calculado pela distância real.',
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
