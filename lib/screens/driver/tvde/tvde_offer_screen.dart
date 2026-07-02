import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Ecrã de OFERTA ao motorista (passageiros). Aceite por TOCAR aqui
/// (nunca pelos botões de ação da notificação — bug conhecido em background).
/// Countdown server-side: o `offer_expires_at` + sweep tratam o timeout; aqui
/// só refletimos. Aceite atómico — se a corrida já foi levada, mostramos aviso.
class TvdeOfferScreen extends StatefulWidget {
  const TvdeOfferScreen({super.key, required this.ride});
  final TvdeRide ride;

  @override
  State<TvdeOfferScreen> createState() => _TvdeOfferScreenState();
}

class _TvdeOfferScreenState extends State<TvdeOfferScreen> {
  Timer? _ticker;
  int _secondsLeft = 25;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final exp = widget.ride.offerExpiresAt;
    if (exp != null) {
      _secondsLeft = exp.difference(DateTime.now()).inSeconds;
    }
    if (_secondsLeft <= 0) _secondsLeft = 25;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) _autoClose();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _autoClose() {
    if (_closing) return;
    _closing = true;
    _ticker?.cancel();
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _accept() async {
    final store = context.read<TvdeDriverStore>();
    _closing = true; // guarda contra duplo-pop durante o rebuild reativo
    _ticker?.cancel();
    try {
      await store.acceptOffer(widget.ride.id);
      if (!mounted) return;
      Navigator.of(context).pop(true); // home roteia para o ecrã ativo
    } catch (_) {
      store.clearOffer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta corrida já não está disponível.')),
      );
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _reject() async {
    final store = context.read<TvdeDriverStore>();
    try {
      await store.rejectOffer(widget.ride.id);
    } catch (_) {/* best-effort */}
    if (mounted) _autoClose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    // Se o realtime tirou a oferta (passou ao próximo), fecha.
    if (store.offeredRide == null && !_closing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoClose());
    }

    final ride = widget.ride;
    final fare = (ride.estFareCents / 100).toStringAsFixed(2);
    final km = ride.estDistanceKm.toStringAsFixed(1);

    // M6 — distância do motorista até à recolha (estilo Uber Driver).
    final myPos = context.select<DriverStore, LatLng?>(
        (d) => d.currentDriver?.location);
    String? toPickup;
    if (myPos != null) {
      final d = const Distance().as(
          LengthUnit.Kilometer, myPos, LatLng(ride.originLat, ride.originLng));
      toPickup = 'Recolha a ${d.toStringAsFixed(1)} km de ti';
    }

    return PopScope(
      canPop: false, // decisão explícita: aceitar ou recusar
      child: Scaffold(
        backgroundColor: AppColors.primaryDeep,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Spacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.local_taxi, color: Colors.white, size: 28),
                    const SizedBox(width: Spacing.sm),
                    Text('Nova corrida',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: Spacing.xs),
                Center(
                  child: Text('$_secondsLeft s',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: Spacing.xl),
                Container(
                  padding: const EdgeInsets.all(Spacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text('€$fare',
                            style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                      ),
                      Center(
                        child: Text('$km km · pagamento em dinheiro',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ),
                      if (toPickup != null) ...[
                        const SizedBox(height: 2),
                        Center(
                          child: Text(toPickup,
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                      const SizedBox(height: Spacing.lg),
                      _PointRow(
                        icon: Icons.my_location,
                        color: AppColors.primary,
                        label: 'Recolha',
                        value: ride.originLabel ?? 'Local de recolha',
                      ),
                      const SizedBox(height: Spacing.md),
                      _PointRow(
                        icon: Icons.location_on,
                        color: AppColors.accent,
                        label: 'Destino',
                        value: ride.destLabel ?? 'Destino',
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                BoraAccentButton(
                  label: 'Aceitar',
                  icon: Icons.check,
                  loading: store.busy,
                  onPressed: _accept,
                ),
                const SizedBox(height: Spacing.sm),
                TextButton(
                  onPressed: store.busy ? null : _reject,
                  child: const Text('Recusar',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppColors.textSubtle,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
