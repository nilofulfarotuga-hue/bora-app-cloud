import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/maps_config.dart';
import '../../../services/directions_service.dart';
import '../../../services/location_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import 'tvde_plans_screen.dart';
import 'tvde_rides_history_screen.dart';
import 'tvde_ride_tracking_screen.dart';

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

  int _estimateCents = -1;
  bool _estimating = false;
  bool _locating = true;

  // B1 — distância efetiva usada na estimativa/pedido: rota real (Directions,
  // mesma chave) com fallback haversine. `_distanceSource` regista qual foi.
  double? _effectiveKm;
  String _distanceSource = 'route';

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
        _estimateCents = -1;
      });
      return;
    }
    setState(() => _estimating = true);
    double km = fallback;
    String source = 'haversine';
    try {
      final route = await _directions.fetchRoute(
        origin: _pickup!,
        destination: _dest!,
      );
      if (route != null && route.distanceKm > 0) {
        km = double.parse(route.distanceKm.toStringAsFixed(2));
        source = 'route';
      }
    } catch (_) {
      // mantém haversine
    }
    final cents = await context.read<TvdeStore>().estimateFareCents(km);
    if (!mounted) return;
    setState(() {
      _effectiveKm = km;
      _distanceSource = source;
      _estimateCents = cents;
      _estimating = false;
    });
  }

  Future<void> _solicitar() async {
    final store = context.read<TvdeStore>();
    final km = _effectiveKm;
    if (_pickup == null || _dest == null || km == null) return;
    try {
      await store.requestRide(
        originLat: _pickup!.latitude,
        originLng: _pickup!.longitude,
        originLabel: _pickupLabel,
        destLat: _dest!.latitude,
        destLng: _dest!.longitude,
        destLabel: _destLabel,
        distanceKm: km,
      );
      if (!mounted) return;
      _openTracking();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('ride_in_progress')
          ? 'Já tens uma corrida em curso.'
          : 'Não foi possível pedir a corrida.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
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
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                    _estimateCents = -1;
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            _EstimateCard(
              cents: _estimateCents,
              km: _effectiveKm,
              loading: _estimating,
            ),
            const SizedBox(height: Spacing.xl),
            BoraAccentButton(
              label: 'Solicitar corrida',
              icon: Icons.local_taxi,
              loading: store.busy,
              onPressed: canRequest ? _solicitar : null,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Pagamento em dinheiro ao motorista. O valor final é calculado '
              'pela distância real da viagem.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
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
        child: Row(
          children: [
            const Icon(Icons.card_membership, color: AppColors.primary),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Planos Bora Motorista',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Corridas incluídas por dia a partir de €3. Vê e adere.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSubtle)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard(
      {required this.cents, required this.km, required this.loading});
  final int cents;
  final double? km;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final hasEstimate = cents > 0 && km != null;
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
                const Text('Valor estimado',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                if (loading)
                  const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                else
                  Text(
                    hasEstimate
                        ? '€${(cents / 100).toStringAsFixed(2)}  ·  ${km!.toStringAsFixed(1)} km'
                        : 'Escolhe o destino',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
