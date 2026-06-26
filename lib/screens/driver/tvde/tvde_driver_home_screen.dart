import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/driver_model.dart';
import '../../../services/heartbeat_service.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/tvde_driver_store.dart';
import 'tvde_offer_screen.dart';
import 'tvde_ride_active_screen.dart';

/// TVDE — Bora Motorista. Home do motorista de passageiros (modo escondido,
/// roteado a partir do _RootNavigator quando vehicle_type='carro_passageiros').
/// Reusa o MESMO mecanismo de is_online + heartbeat (90s) + GPS do delivery —
/// não cria heartbeat novo. 100% isolado do dispatch de entregas.
class TvdeDriverHomeScreen extends StatefulWidget {
  const TvdeDriverHomeScreen({super.key});

  @override
  State<TvdeDriverHomeScreen> createState() => _TvdeDriverHomeScreenState();
}

class _TvdeDriverHomeScreenState extends State<TvdeDriverHomeScreen>
    with WidgetsBindingObserver {
  final HeartbeatService _heartbeat = HeartbeatService();
  StreamSubscription<Position>? _gps;
  bool _offerOpen = false;
  bool _activeOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<TvdeDriverStore>().start();
      // Se o motorista já estava Online (re-abertura), retoma heartbeat+GPS.
      final isOnline =
          context.read<DriverStore>().currentDriver?.isOnline ?? false;
      if (isOnline) {
        unawaited(_heartbeat.start());
        unawaited(_startGps());
      }
      _syncNav();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tocar na notificação de oferta traz o app à frente → re-lê oferta/corrida
    // ativa (a par do realtime) para o ecrã de oferta aparecer.
    if (state == AppLifecycleState.resumed && mounted) {
      final driverStore = context.read<DriverStore>();
      if (driverStore.currentDriver?.isOnline == true) {
        unawaited(_heartbeat.start());
      }
      context.read<TvdeDriverStore>().loadCurrent().then((_) {
        if (mounted) _syncNav();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat.stop();
    _gps?.cancel();
    super.dispose();
  }

  // ── Navegação reativa para oferta / corrida ativa ──────────────────────────
  void _syncNav() {
    if (!mounted) return;
    final store = context.read<TvdeDriverStore>();
    final active = store.activeRide;
    if (active != null && active.isLive && !_activeOpen) {
      _activeOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => const TvdeRideActiveScreen()))
          .then((_) => _activeOpen = false);
      return;
    }
    final offer = store.offeredRide;
    if (offer != null && !_offerOpen && !_activeOpen) {
      _offerOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute<void>(
              builder: (_) => TvdeOfferScreen(ride: offer)))
          .then((_) => _offerOpen = false);
    }
  }

  // ── Online toggle (reuso DriverStore + heartbeat + GPS) ────────────────────
  Future<void> _toggleOnline(bool value) async {
    final driverStore = context.read<DriverStore>();
    final id = driverStore.currentDriverId;
    final ok = driverStore.toggleAvailability(id, value);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conclui a corrida atual antes de ficar offline.')));
      }
      return;
    }
    if (value) {
      unawaited(_heartbeat.start());
      await _startGps();
    } else {
      unawaited(_heartbeat.stop());
      await _gps?.cancel();
      _gps = null;
    }
  }

  Future<void> _startGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ative o GPS para receber corridas.')));
      }
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    await _gps?.cancel();
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
      ),
    ).listen((pos) {
      if (!mounted) return;
      final store = context.read<DriverStore>();
      store.updateDriverLocation(
          store.currentDriverId, LatLng(pos.latitude, pos.longitude));
    });
  }

  void _logout() {
    _heartbeat.stop();
    _gps?.cancel();
    context.read<AuthStore>().logout();
  }

  @override
  Widget build(BuildContext context) {
    // Dispara a navegação reativa sempre que o store muda.
    context.watch<TvdeDriverStore>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNav());

    final status = context.watch<AuthStore>().currentDriverStatus;
    if (status != DriverStatus.approved) {
      return _GateScreen(status: status, onLogout: _logout);
    }

    final isOnline =
        context.select<DriverStore, bool>((d) => d.currentDriver?.isOnline ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Bora Motorista'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.xl),
            Icon(
              isOnline ? Icons.local_taxi : Icons.local_taxi_outlined,
              size: 88,
              color: isOnline ? AppColors.primary : AppColors.textSubtle,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              isOnline ? 'Estás online' : 'Estás offline',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              isOnline
                  ? 'À espera de corridas de passageiros.'
                  : 'Fica online para receber corridas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg, vertical: Spacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(isOnline ? 'Online' : 'Offline',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  Switch(
                    value: isOnline,
                    activeColor: AppColors.primary,
                    onChanged: _toggleOnline,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Ecrã de espera quando o motorista ainda não foi aprovado (ou foi rejeitado).
class _GateScreen extends StatelessWidget {
  const _GateScreen({required this.status, required this.onLogout});
  final DriverStatus status;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final rejected = status == DriverStatus.rejected;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(rejected ? Icons.cancel : Icons.hourglass_top,
                  size: 72,
                  color: rejected ? AppColors.error : AppColors.primary),
              const SizedBox(height: Spacing.lg),
              Text(
                rejected ? 'Candidatura rejeitada' : 'Candidatura em análise',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                rejected
                    ? 'A tua candidatura a motorista de passageiros foi rejeitada. Contacta o suporte.'
                    : 'Vamos rever a tua candidatura a motorista de passageiros. Avisamos-te assim que for aprovada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.xl),
              TextButton(onPressed: onLogout, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}
