import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/sound_service.dart';
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
  bool _closing = false;

  /// Guarda local de ação (aceitar/recusar) — NÃO depende de `store.busy`
  /// (partilhado): garante que Recusar nunca fica "morto" por um busy preso
  /// de outra operação (bug do teste no device).
  bool _acting = false;

  /// Som CONTÍNUO da oferta (padrão Uber/estafeta) — mesmo `SoundService` +
  /// `bora_alert.wav` que o fluxo de entrega usa em `playLoop`. Instância
  /// própria (AudioPlayer isolado, ver doc do SoundService).
  final SoundService _sound = SoundService();

  @override
  void initState() {
    super.initState();
    // A1 — arranca o som contínuo até aceitar/recusar/expirar.
    _sound.playLoop();
    // A contagem é recalculada a cada segundo a partir da oferta VIVA (store)
    // no build — assim um re-offer renova o tempo em vez de ficar preso em "0 s".
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sound.stop();
    _sound.dispose();
    super.dispose();
  }

  void _autoClose() {
    if (_closing) return;
    _closing = true;
    _ticker?.cancel();
    _sound.stop();
    // pop() explícito (NÃO maybePop): o PopScope canPop:false BLOQUEIA o
    // maybePop → era exatamente isto que prendia o ecrã em "0 s" e matava o
    // Recusar. O pop() explícito não consulta o canPop e fecha mesmo.
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_acting) return;
    _acting = true;
    final store = context.read<TvdeDriverStore>();
    _closing = true; // guarda contra duplo-pop durante o rebuild reativo
    _ticker?.cancel();
    _sound.stop();
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
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  Future<void> _reject() async {
    if (_acting) return;
    _acting = true;
    _sound.stop();
    final store = context.read<TvdeDriverStore>();
    try {
      await store.rejectOffer(widget.ride.id);
    } catch (_) {/* best-effort — o dispatch trata a rotação/sem_motorista */}
    if (mounted) _autoClose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    // Oferta VIVA: a store atualiza-a no re-offer, por isso o ecrã reflete
    // sempre a oferta atual — a contagem e os dados RENOVAM no re-offer.
    final ride = store.offeredRide ?? widget.ride;
    final exp = ride.offerExpiresAt;
    final secs = exp == null ? 0 : exp.difference(DateTime.now()).inSeconds;
    // [Item E/M] Fecha AUTOMATICAMENTE quando: (a) o realtime tira a oferta, OU
    // (b) o TTL local esgota (offer_expires_at já passou). (b) é o caminho
    // FIÁVEL: o evento de limpeza do servidor pode NÃO chegar a este motorista
    // (a RLS esconde a linha de tvde_rides quando current_offer_driver_id deixa
    // de ser ele), por isso a expiração LOCAL fecha o ecrã sem depender do
    // realtime — e clearOffer() limpa a store para o home não reabrir a mesma.
    final expiredLocally = exp != null && secs <= 0;
    if (!_closing && (store.offeredRide == null || expiredLocally)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (expiredLocally) store.clearOffer();
        _autoClose();
      });
    }
    final countdownLabel = secs > 0 ? '$secs s' : 'A reatribuir…';

    // [Item C] o motorista vê o SEU líquido (ganho), não o total do cliente.
    final net = ((ride.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
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
                  child: Text(countdownLabel,
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
                        child: Text('€$net',
                            style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                      ),
                      Center(
                        child: Text('O teu ganho · $km km',
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
                  loading: store.busy && _acting,
                  onPressed: _accept,
                ),
                const SizedBox(height: Spacing.sm),
                // Recusar é SEMPRE a saída garantida (bug do device: ficava
                // "morto" por partilhar o `store.busy` do Aceitar). Agora só o
                // guard local `_acting` o protege contra duplo-toque.
                TextButton(
                  onPressed: _acting ? null : _reject,
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
