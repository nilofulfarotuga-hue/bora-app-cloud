import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../widgets/bora/bora.dart';
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

  Set<Marker> _markers(TvdeRide ride, LatLng? driverPos) {
    final m = <Marker>{
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
    if (driverPos != null) {
      m.add(Marker(
        markerId: const MarkerId('driver'),
        position: driverPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Tu'),
      ));
    }
    return m;
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

  Future<void> _finish(TvdeRide ride) async {
    try {
      // Sem odómetro: a distância real usada é a estimada origem→destino. É o
      // seam para, no futuro, ligar a distância medida por GPS.
      await context.read<TvdeDriverStore>().finishRide(ride.id, ride.estDistanceKm);
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
      await context.read<TvdeDriverStore>().cancelRide(ride.id, noShow: noShow);
      if (!mounted) return;
      context.read<TvdeDriverStore>().clearActive();
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

    // Finalizada → avaliar passageiro.
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
                  const PopupMenuItem(
                      value: 'no_show', child: Text('Passageiro não compareceu')),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 13),
            markers: _markers(ride, driverPos),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
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
          const SizedBox(height: Spacing.lg),
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
