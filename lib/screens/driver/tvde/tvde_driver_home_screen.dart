import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/auth_store.dart';
import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/driver_model.dart';
import '../../../services/driver_location_ping_service.dart';
import '../../../services/heartbeat_service.dart';
import '../../../services/notification_service.dart';
import '../../../services/permission_gate_service.dart';
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
  Position? _lastPos;
  Timer? _offerPoll;
  bool _offerOpen = false;
  bool _activeOpen = false;

  gmaps.GoogleMapController? _mapController;
  gmaps.LatLng? _lastCameraTarget;

  /// Centro por omissão (Guarda) enquanto não há 1º fix de GPS — garante que o
  /// mapa nunca aparece vazio/branco: renderiza sempre com câmara válida.
  static const gmaps.LatLng _guardaCenter = gmaps.LatLng(40.5373, -7.2657);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // [TVDE P0] Push de oferta força reload do store → a tela de oferta aparece
    // mesmo que o realtime tenha caído (fallback triplo: push → realtime → poll).
    NotificationService.tvdeOfferReload = _reloadOffer;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Reflete admin approve/reject pós-login sem relogin (espelha o
      // DriverHomeScreen de entrega: refreshApprovalStatus → notifyListeners →
      // o gate em build() reage via context.watch<AuthStore>()).
      await context.read<AuthStore>().refreshApprovalStatus();
      if (!mounted) return;
      await context.read<TvdeDriverStore>().start();
      // Se o motorista já estava Online (re-abertura), retoma heartbeat+GPS.
      final isOnline =
          context.read<DriverStore>().currentDriver?.isOnline ?? false;
      if (isOnline) {
        unawaited(_heartbeat.start());
        unawaited(_startGps());
        _startOfferPoll();
      }
      _syncNav();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Tocar na notificação de oferta traz o app à frente → re-lê oferta/corrida
    // ativa (a par do realtime) para o ecrã de oferta aparecer.
    if (state == AppLifecycleState.resumed && mounted) {
      // Apanha admin approve/reject enquanto o app esteve em background — o
      // motorista volta ao app já aprovado e o gate atualiza sem relogin.
      unawaited(context.read<AuthStore>().refreshApprovalStatus());
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
    if (NotificationService.tvdeOfferReload == _reloadOffer) {
      NotificationService.tvdeOfferReload = null;
    }
    _heartbeat.stop();
    _gps?.cancel();
    _offerPoll?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  /// Recarrega a oferta/corrida do servidor e reavalia a navegação. Ligado ao
  /// push `new_tvde_ride_offer` (chegada + tap) via NotificationService.
  void _reloadOffer() {
    if (!mounted) return;
    context.read<TvdeDriverStore>().loadCurrent().then((_) {
      if (mounted) _syncNav();
    });
  }

  /// Rede de segurança: enquanto online e sem oferta/corrida, relê a cada 10s.
  /// Garante a oferta mesmo que push E realtime falhem (Uber-grade). Barato —
  /// só corre quando online e ocioso.
  void _startOfferPoll() {
    _offerPoll?.cancel();
    _offerPoll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final driverStore = context.read<DriverStore>();
      if (driverStore.currentDriver?.isOnline != true) return;
      final tvde = context.read<TvdeDriverStore>();
      if (tvde.offeredRide != null || tvde.activeRide != null) return;
      tvde.loadCurrent().then((_) {
        if (mounted) _syncNav();
      });
    });
  }

  void _stopOfferPoll() {
    _offerPoll?.cancel();
    _offerPoll = null;
  }

  /// Segue a posição do motorista com a câmara (best-effort). Só anima quando o
  /// alvo muda de facto — evita animações a cada rebuild.
  void _followCamera(gmaps.LatLng target) {
    final c = _mapController;
    if (c == null) return;
    final prev = _lastCameraTarget;
    if (prev != null &&
        (prev.latitude - target.latitude).abs() < 0.0002 &&
        (prev.longitude - target.longitude).abs() < 0.0002) {
      return;
    }
    _lastCameraTarget = target;
    c.animateCamera(gmaps.CameraUpdate.newLatLng(target));
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
          .then((_) {
        _activeOpen = false;
        // Corrida terminou → atualiza os ganhos do dia.
        if (mounted) context.read<TvdeDriverStore>().loadTodayEarnings();
      });
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
      // [A] 2026-06-30 — gate MÍNIMO partilhado com o estafeta. Antes o TVDE
      // não tinha gate nenhum. Garante a notificação persistente (best-effort)
      // e oferece o overlay no máximo uma vez. NUNCA bloqueia ir online — o
      // toggleAvailability acima já passou; overlay é só um bónus.
      await PermissionGateService.ensureMinimumOnlinePermissions(context);
      if (!mounted) return;
      unawaited(OverlayPermissionGate.maybeOfferOnce(context));
      unawaited(_heartbeat.start());
      await _startGps();
      _startOfferPoll();
    } else {
      unawaited(_heartbeat.stop());
      await _gps?.cancel();
      _gps = null;
      _stopOfferPoll();
      await _goOfflinePing();
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
    // Ping imediato → aparece já uma linha fresca em driver_locations (fonte do
    // matching TVDE) sem esperar o 1º fix do stream.
    try {
      final first = await Geolocator.getCurrentPosition();
      _lastPos = first;
      await DriverLocationPingService.instance.ping(
        latitude: first.latitude,
        longitude: first.longitude,
        heading: first.heading.isFinite ? first.heading : null,
        speedKmh: first.speed.isFinite ? first.speed * 3.6 : null,
        isOnline: true,
      );
    } catch (_) {/* o stream cobre o ping seguinte */}

    await _gps?.cancel();
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
      ),
    ).listen((pos) {
      if (!mounted) return;
      _lastPos = pos;
      final store = context.read<DriverStore>();
      store.updateDriverLocation(
          store.currentDriverId, LatLng(pos.latitude, pos.longitude));
      // Alimenta driver_locations por user_id via RPC partilhada (throttle 45s).
      // É a fonte que o tvde_offer_to_next lê para elegibilidade.
      DriverLocationPingService.instance.ping(
        latitude: pos.latitude,
        longitude: pos.longitude,
        heading: pos.heading.isFinite ? pos.heading : null,
        speedKmh: pos.speed.isFinite ? pos.speed * 3.6 : null,
        isOnline: true,
      );
    });
  }

  /// Marca driver_locations.is_online=false (por user_id) ao ficar offline/logout
  /// — sai do matching de imediato, sem esperar a janela de frescura. Reusa a RPC
  /// partilhada driver_update_location (apenas CHAMADA, não alterada).
  Future<void> _goOfflinePing() async {
    final pos = _lastPos;
    if (pos == null) return; // sem fix prévio: a frescura (janela) já exclui
    try {
      await Supabase.instance.client.rpc('driver_update_location', params: {
        'p_latitude': pos.latitude,
        'p_longitude': pos.longitude,
        'p_is_online': false,
      });
    } catch (_) {/* best-effort */}
  }

  void _logout() {
    _heartbeat.stop();
    _gps?.cancel();
    unawaited(_goOfflinePing());
    context.read<AuthStore>().logout();
  }

  // ── Preferências de trabalho (só corridas vs tudo) ─────────────────────────
  void _openWorkModeSheet() {
    final mode = context.read<TvdeDriverStore>().workMode;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
              child: Text('O que queres aceitar?',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            RadioListTile<String>(
              value: 'rides_only',
              groupValue: mode,
              activeColor: AppColors.primary,
              title: const Text('Só corridas de passageiros'),
              subtitle: const Text('Recebes apenas viagens Bora Motorista.'),
              onChanged: (v) => _applyWorkMode(ctx, v!),
            ),
            RadioListTile<String>(
              value: 'everything',
              groupValue: mode,
              activeColor: AppColors.primary,
              title: const Text('Tudo'),
              subtitle: const Text(
                  'Corridas + entregas de restaurante, supermercado e favores.'),
              onChanged: (v) => _applyWorkMode(ctx, v!),
            ),
            const SizedBox(height: Spacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _applyWorkMode(BuildContext sheetCtx, String mode) async {
    Navigator.pop(sheetCtx);
    try {
      await context.read<TvdeDriverStore>().setWorkMode(mode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(mode == 'rides_only'
              ? 'Preferência guardada: só corridas.'
              : 'Preferência guardada: tudo.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível guardar a preferência.')));
    }
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
    final LatLng? locLl =
        context.select<DriverStore, LatLng?>((d) => d.currentDriver?.location);
    final gmaps.LatLng? mePos =
        locLl == null ? null : gmaps.LatLng(locLl.latitude, locLl.longitude);
    if (mePos != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _followCamera(mePos));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Bora Motorista'),
        actions: [
          IconButton(
            tooltip: 'Preferências',
            onPressed: _openWorkModeSheet,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      // Estilo Uber Driver: mapa em tela cheia com a posição própria + cartão de
      // estado/toggle flutuante. O cartão vive num Stack por CIMA do mapa, logo
      // renderiza SEMPRE (mesmo que a platform view do GoogleMap demore) — é o
      // fallback defensivo contra tela sem controlo.
      body: Stack(
        children: [
          gmaps.GoogleMap(
            initialCameraPosition: gmaps.CameraPosition(
              target: mePos ?? _guardaCenter,
              zoom: 14.5,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              if (mePos != null) {
                _lastCameraTarget = mePos;
                c.moveCamera(gmaps.CameraUpdate.newLatLng(mePos));
              }
            },
            markers: mePos == null
                ? <gmaps.Marker>{}
                : {
                    gmaps.Marker(
                      markerId: const gmaps.MarkerId('me'),
                      position: mePos,
                      icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                          gmaps.BitmapDescriptor.hueAzure),
                      infoWindow: const gmaps.InfoWindow(title: 'Tu'),
                    ),
                  },
          ),
          if (mePos == null) const _LocatingBanner(),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: _OnlinePanel(
                isOnline: isOnline,
                todayEarnCents:
                    context.read<TvdeDriverStore>().todayEarnCents,
                onChanged: _toggleOnline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cartão flutuante de estado + toggle online/offline (estilo Uber Driver).
class _OnlinePanel extends StatelessWidget {
  const _OnlinePanel({
    required this.isOnline,
    required this.todayEarnCents,
    required this.onChanged,
  });
  final bool isOnline;
  final int todayEarnCents;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(Spacing.md),
      padding:
          const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [
          BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: Spacing.sm),
                const Text('Ganhos de hoje',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                const Spacer(),
                Text('€${(todayEarnCents / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
          Icon(isOnline ? Icons.local_taxi : Icons.local_taxi_outlined,
              size: 32,
              color: isOnline ? AppColors.primary : AppColors.textSubtle),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(isOnline ? 'Estás online' : 'Estás offline',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                Text(
                  isOnline
                      ? 'À espera de corridas de passageiros.'
                      : 'Fica online para receber corridas.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Switch(
            value: isOnline,
            activeColor: AppColors.primary,
            onChanged: onChanged,
          ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip "a localizar" no topo enquanto não há 1º fix de GPS.
class _LocatingBanner extends StatelessWidget {
  const _LocatingBanner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.all(Spacing.md),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg, vertical: Spacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: Spacing.sm),
              Text('A obter a tua localização…',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
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
