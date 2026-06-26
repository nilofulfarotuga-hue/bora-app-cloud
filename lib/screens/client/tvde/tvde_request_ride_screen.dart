import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/maps_config.dart';
import '../../../services/location_service.dart';
import '../../../stores/tvde_store.dart';
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

  LatLng? _pickup;
  String _pickupLabel = 'A obter localização…';
  LatLng? _dest;
  String? _destLabel;

  int _estimateCents = -1;
  bool _estimating = false;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _destController.dispose();
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
        _locating = false;
      });
    } else {
      setState(() {
        _pickupLabel = 'Localização indisponível';
        _locating = false;
      });
    }
  }

  double? get _distanceKm {
    if (_pickup == null || _dest == null) return null;
    final km = const Distance().as(LengthUnit.Kilometer, _pickup!, _dest!);
    return double.parse(km.toStringAsFixed(2));
  }

  Future<void> _recalcEstimate() async {
    final km = _distanceKm;
    if (km == null) {
      setState(() => _estimateCents = -1);
      return;
    }
    setState(() => _estimating = true);
    final cents = await context.read<TvdeStore>().estimateFareCents(km);
    if (!mounted) return;
    setState(() {
      _estimateCents = cents;
      _estimating = false;
    });
  }

  Future<void> _solicitar() async {
    final store = context.read<TvdeStore>();
    final km = _distanceKm;
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
    final canRequest =
        _pickup != null && _dest != null && !store.busy && !_locating;

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
            _PickupTile(label: _pickupLabel, locating: _locating, onRefresh: _detectPickup),
            const SizedBox(height: Spacing.md),
            AddressAutocompleteField(
              controller: _destController,
              labelText: 'Para onde vais?',
              prefixIcon: const Icon(Icons.flag_outlined),
              onSelected: (address, coords) {
                setState(() {
                  _dest = coords;
                  _destLabel = address;
                });
                _recalcEstimate();
              },
              onChanged: (_) {
                if (_dest != null) {
                  setState(() {
                    _dest = null;
                    _estimateCents = -1;
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            _EstimateCard(
              cents: _estimateCents,
              km: _distanceKm,
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
          ],
        ),
      ),
    );
  }
}

class _PickupTile extends StatelessWidget {
  const _PickupTile(
      {required this.label, required this.locating, required this.onRefresh});
  final String label;
  final bool locating;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.my_location, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recolha',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          if (locating)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: onRefresh,
            ),
        ],
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
