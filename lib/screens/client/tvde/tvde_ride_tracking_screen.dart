import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';
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
  Timer? _driverPoll;
  bool _navigatedToRate = false;

  @override
  void initState() {
    super.initState();
    _driverPoll = Timer.periodic(const Duration(seconds: 5), (_) => _pollDriver());
  }

  @override
  void dispose() {
    _driverPoll?.cancel();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _pollDriver() async {
    final ride = context.read<TvdeStore>().activeRide;
    if (ride == null || ride.driverId == null || !ride.isAssigned) return;
    try {
      // `driver_id` = auth uid do motorista → a linha resolve por user_id
      // (em motoristas reais drivers.id <> user_id; usar 'id' não encontrava
      // nada e o marker/cartão do motorista nunca aparecia).
      final row = await Supabase.instance.client
          .from('drivers')
          .select('name, avg_rating, lat, lng')
          .eq('user_id', ride.driverId!)
          .maybeSingle();
      final lat = (row?['lat'] as num?)?.toDouble();
      final lng = (row?['lng'] as num?)?.toDouble();
      if (mounted) {
        setState(() {
          if (lat != null && lng != null) _driverPos = LatLng(lat, lng);
          _driverName = (row?['name'] as String?)?.trim();
          _driverRating = (row?['avg_rating'] as num?)?.toDouble();
        });
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

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'A tua corrida'),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers(ride),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _map = c,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _StatusPanel(
              ride: ride,
              busy: store.busy,
              driverName: _driverName,
              driverRating: _driverRating,
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
    required this.onCancel,
    required this.onRetry,
    required this.onClose,
  });

  final TvdeRide ride;
  final bool busy;
  final String? driverName;
  final double? driverRating;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onClose;

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
                  radius: 18,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: const Icon(Icons.person, color: AppColors.primary),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(driverName!,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary)),
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
