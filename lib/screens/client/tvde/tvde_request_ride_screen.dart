import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../config/maps_config.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/directions_service.dart';
import '../../../services/location_service.dart';
import '../../../services/payment_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../utils/map_utils.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/tvde/tvde_payment_selector.dart';
import 'tvde_plans_screen.dart';
import 'tvde_rides_history_screen.dart';
import 'tvde_ride_tracking_screen.dart';

/// Frente 4 — como o cliente paga ESTA corrida, decidido pela cobertura do
/// plano. Espelha a matemática do `tvde_finish_ride` para mostrar o valor e o
/// porquê ANTES de pedir (nunca cobrar sem o cliente ver).
enum _PayCase {
  normal, // sem plano (ou plano não cobre hoje) → tarifa cheia
  freeCovered, // coberta e ≤ base_km → grátis, não abre pagamento
  excess, // coberta mas > base_km → só o excesso (€/km acima)
  extra, // membro sem corridas hoje → €4,50 + excesso
}

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

  bool _estimating = false;
  bool _locating = true;

  // B1 — distância efetiva usada na estimativa/pedido: rota real (Directions,
  // mesma chave) com fallback haversine. `_distanceSource` regista qual foi.
  double? _effectiveKm;
  // ignore: unused_field — [Item D] guardado para futura persistência no ride.
  String _distanceSource = 'route';

  // Frente 4 — caso de pagamento decidido pela cobertura do plano (preview
  // read-only). Espelha o `tvde_finish_ride`: grátis / só-excesso / extra-membro
  // / normal, com o valor e a mensagem que o cliente vê ANTES de pedir.
  _PayCase _payCase = _PayCase.normal;
  int _payableCents = 0;
  String? _payMessage;

  // [CAMPO-02 · Feature 3] "Garantir a volta": pacote ida+volta pago adiantado.
  bool _roundtrip = false;
  int _roundtripPriceCents = 800; // fallback; sobrescrito por platform_settings
  Map<String, dynamic>? _activeCredit; // vale-volta ativo (mostra "Chamar a volta")

  // Cartão + MB Way só aparecem (na FOLHA de pagamento, depois do botão) se o
  // kill switch estiver ligado (`tvde_card_payments_enabled`). Preços do plano
  // vêm do backend (platform_settings) para a UI bater certo com o finish.
  bool _cardEnabled = false;
  int _perKmCents = 50;
  int _baseKm = 6;
  int _extraRideCents = 450;

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
    // [F3] preço do pacote ida-volta + vale ativo (para "Chamar a minha volta").
    final price = await store.getSettingInt('tvde_roundtrip_price_cents', 800);
    final credit = await store.activeRoundtripCredit();
    // Kill switch de card/mbway (falha fechada → só dinheiro).
    final cardEnabled =
        await store.getSettingBool('tvde_card_payments_enabled', false);
    // Preços do plano (mesmos que o backend usa no finish) para a UI mostrar o
    // valor certo do excesso/extra ANTES de pedir.
    final perKm = await store.getSettingInt('tvde_extra_per_km_cents', 50);
    final baseKm = await store.getSettingInt('tvde_base_distance_km', 6);
    final extraRide = await store.getSettingInt('tvde_extra_ride_cents', 450);
    if (mounted) {
      setState(() {
        _roundtripPriceCents = price;
        _activeCredit = credit;
        _cardEnabled = cardEnabled;
        _perKmCents = perKm;
        _baseKm = baseKm;
        _extraRideCents = extraRide;
      });
    }
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
        _payCase = _PayCase.normal;
        _payableCents = 0;
        _payMessage = null;
      });
      return;
    }
    setState(() => _estimating = true);
    double km = fallback;
    String source = 'haversine';
    // [Item D] a rota real é a FONTE do preço. O Directions falha às vezes de
    // forma transitória (rede/limite de QPS) e, ao cair para haversine, o km e o
    // preço ficam SUBESTIMADOS (linha reta << rota real). Uma 2ª tentativa
    // recupera a rota real na esmagadora maioria desses casos.
    for (var attempt = 0; attempt < 2 && source == 'haversine'; attempt++) {
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
        // mantém haversine; volta a tentar se ainda houver tentativa
      }
    }
    final cents = await context.read<TvdeStore>().estimateFareCents(km);
    // [Item B] cobertura pelo plano (read-only, NÃO consome — só o finish consome).
    final cov = await context.read<TvdeStore>().previewCoverage();
    if (!mounted) return;
    // Planos só cobrem Segunda a Sexta — a RPC tvde_preview_coverage não checa
    // o dia da semana (só o consumo no finish o faz), então replicamos aqui
    // para não mostrar "Incluída no plano" ao fim de semana por engano.
    final isWeekend =
        DateTime.now().weekday == DateTime.saturday || DateTime.now().weekday == DateTime.sunday;
    final covered = !isWeekend && cov['covered'] == true;
    final used = (cov['daily_used'] as num?)?.toInt();
    final incl = (cov['daily_included'] as num?)?.toInt();
    final reason = cov['reason'] as String?;
    // Membro = tem plano ativo (mesmo que hoje não cubra: fim de semana ou já
    // usou as de hoje). O finish cobra €4,50 + excesso a membros não-cobertos.
    final isMember = covered || reason == 'daily_limit';
    final excessKm = km > _baseKm ? (km - _baseKm).ceil() : 0;
    final excessCents = excessKm * _perKmCents;

    _PayCase pc;
    int payable;
    String? message;
    if (covered) {
      if (excessKm == 0) {
        pc = _PayCase.freeCovered;
        payable = 0;
        message = (used != null && incl != null)
            ? 'Incluída no teu plano · ${used + 1}.ª de $incl hoje'
            : 'Incluída no teu plano';
      } else {
        pc = _PayCase.excess;
        payable = excessCents;
        message = 'Corrida do plano — só pagas o excesso: '
            '$excessKm km acima de $_baseKm = €${(payable / 100).toStringAsFixed(2)}';
      }
    } else if (isMember) {
      pc = _PayCase.extra;
      payable = _extraRideCents + excessCents;
      message = 'Já usaste as corridas de hoje — esta fica '
          '€${(payable / 100).toStringAsFixed(2)} (preço de membro).';
    } else {
      pc = _PayCase.normal;
      payable = cents;
      message = null;
    }
    setState(() {
      _effectiveKm = km;
      _distanceSource = source;
      _payCase = pc;
      _payableCents = payable;
      _payMessage = message;
      _estimating = false;
    });
  }

  /// Frente 3 — carregar em "Solicitar corrida" abre a FOLHA de pagamento
  /// (como no checkout do delivery: método só APÓS o botão). Grátis (coberta
  /// ≤ base_km) cria já, sem folha.
  Future<void> _onRequestPressed() async {
    if (_payCase == _PayCase.freeCovered) {
      await _solicitar('cash');
      return;
    }
    // Online (cartão/MB Way) em QUALQUER corrida com valor > 0. A Edge Function
    // cobra o valor do plano (`tvde_ride_charge_cents`), não a tarifa cheia — por
    // isso excesso/extra também pagam por cartão/MB Way sem sobre-cobrar.
    final allowOnline = _cardEnabled && _payableCents > 0;
    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TvdePaymentSheet(
        amountCents: _payableCents,
        message: _payMessage,
        allowOnline: allowOnline,
      ),
    );
    if (method == null || !mounted) return;
    await _solicitar(method);
  }

  Future<void> _solicitar(String method) async {
    final store = context.read<TvdeStore>();
    final km = _effectiveKm;
    if (_pickup == null || _dest == null || km == null) return;
    try {
      if (method == 'card' || method == 'mbway') {
        // Pagamento online ANTES de criar a corrida (a Edge Function autoriza/
        // cobra no Stripe e só então cria a ride). Só chega aqui com o switch on.
        await store.requestRidePaid(
          originLat: _pickup!.latitude,
          originLng: _pickup!.longitude,
          originLabel: _pickupLabel,
          destLat: _dest!.latitude,
          destLng: _dest!.longitude,
          destLabel: _destLabel,
          distanceKm: km,
          method: method,
          confirmCard: (clientSecret) =>
              PaymentService().processPayment(clientSecret),
        );
      } else {
        await store.requestRide(
          originLat: _pickup!.latitude,
          originLng: _pickup!.longitude,
          originLabel: _pickupLabel,
          destLat: _dest!.latitude,
          destLng: _dest!.longitude,
          destLabel: _destLabel,
          distanceKm: km,
          paymentMethod: 'cash',
        );
      }
      if (!mounted) return;
      _openTracking();
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      final msg = s.contains('ride_in_progress')
          ? 'Já tens uma corrida em curso.'
          : s.contains('card_payments_not_enabled')
              ? 'Pagamento por cartão ainda não está disponível.'
              : s.contains('cancel') || s.contains('Cancel')
                  ? 'Pagamento cancelado.'
                  : 'Não foi possível pedir a corrida.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// [F3] Pedido "garantir a volta": paga €8 (cartão, mesmo PaymentService do
  /// plano) → cria a corrida de IDA → liga-a ao vale-volta. A volta é disparada
  /// depois pelo cliente (desacoplada). MB Way reusa a Edge Fn (create_roundtrip_mbway).
  Future<void> _solicitarRoundtrip() async {
    final store = context.read<TvdeStore>();
    final km = _effectiveKm;
    if (_pickup == null || _dest == null || km == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final created = await store.createRoundtripPayment();
    if (!mounted) return;
    if (created == null || created['clientSecret'] == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível iniciar o pagamento da volta.')));
      return;
    }
    try {
      await PaymentService().processPayment(created['clientSecret'] as String);
    } catch (_) {
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Pagamento cancelado.')));
      return;
    }

    TvdeRide? ida;
    try {
      ida = await store.requestRide(
        originLat: _pickup!.latitude,
        originLng: _pickup!.longitude,
        originLabel: _pickupLabel,
        destLat: _dest!.latitude,
        destLng: _dest!.longitude,
        destLabel: _destLabel,
        distanceKm: km,
      );
    } catch (_) {}
    if (!mounted) return;
    if (ida == null) {
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Pago, mas falhou criar a corrida. Fala com o suporte.')));
      return;
    }
    await store.activateRoundtrip(
        ida.id, created['paymentIntentId'] as String);
    if (!mounted) return;
    _openTracking();
  }

  /// [F3] Dispara a corrida de VOLTA usando o vale ativo (pede o destino).
  Future<void> _callReturn() async {
    final credit = _activeCredit;
    if (credit == null || _pickup == null) return;
    final store = context.read<TvdeStore>();
    final picked = await showModalBottomSheet<_ReturnDest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ReturnSheet(),
    );
    if (picked == null || !mounted) return;
    // distância por rota real (fallback haversine) da recolha atual até ao destino.
    double km = const Distance()
        .as(LengthUnit.Kilometer, _pickup!, LatLng(picked.lat, picked.lng));
    try {
      final route = await _directions.fetchRoute(
          origin: _pickup!, destination: LatLng(picked.lat, picked.lng));
      if (route != null && route.distanceKm > 0) km = route.distanceKm;
    } catch (_) {}
    if (!mounted) return;
    try {
      await store.requestReturnRide(
        creditId: credit['id'] as String,
        originLat: _pickup!.latitude,
        originLng: _pickup!.longitude,
        originLabel: _pickupLabel,
        destLat: picked.lat,
        destLng: picked.lng,
        destLabel: picked.label,
        distanceKm: double.parse(km.toStringAsFixed(2)),
      );
      if (!mounted) return;
      _openTracking();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível chamar a volta.')));
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
            // [F3] vale-volta ativo → "Chamar a minha volta".
            if (_activeCredit != null) ...[
              _ReturnCreditCard(
                credit: _activeCredit!,
                busy: store.busy,
                onCall: _callReturn,
              ),
              const SizedBox(height: Spacing.md),
            ],
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
                    _payableCents = 0;
                  });
                }
              },
            ),
            const SizedBox(height: Spacing.lg),
            _EstimateCard(
              payableCents: _payableCents,
              km: _effectiveKm,
              loading: _estimating,
              isFree: _payCase == _PayCase.freeCovered,
              message: _payMessage,
            ),
            const SizedBox(height: Spacing.md),
            // [F3] "Garantir a volta" — pacote ida+volta pago adiantado.
            _RoundtripToggle(
              value: _roundtrip,
              priceCents: _roundtripPriceCents,
              onChanged: (v) => setState(() => _roundtrip = v),
            ),
            const SizedBox(height: Spacing.xl),
            BoraAccentButton(
              label: _roundtrip
                  ? 'Garantir ida e volta · €${(_roundtripPriceCents / 100).toStringAsFixed(2)}'
                  : 'Solicitar corrida',
              icon: _roundtrip ? Icons.sync_alt : Icons.local_taxi,
              loading: store.busy,
              onPressed: canRequest
                  ? (_roundtrip ? _solicitarRoundtrip : _onRequestPressed)
                  : null,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              _payCase == _PayCase.freeCovered
                  ? 'Incluída no teu plano — não pagas nada ao motorista.'
                  : 'Escolhes como pagar depois de solicitares.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
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
        child: const Row(
          children: [
            Icon(Icons.card_membership, color: AppColors.primary),
            SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Planos Bora Motorista',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 2),
                  Text('Corridas incluídas por dia a partir de €3. Vê e adere.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSubtle)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.payableCents,
    required this.km,
    required this.loading,
    required this.isFree,
    this.message,
  });
  final int payableCents;
  final double? km;
  final bool loading;
  final bool isFree; // coberta ≤ base_km → cliente paga €0
  final String? message; // linha do porquê (plano/excesso/extra)

  @override
  Widget build(BuildContext context) {
    final hasKm = km != null;
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
                Text(isFree ? 'Plano' : 'Valor estimado',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                if (loading)
                  const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                else
                  Text(
                    !hasKm
                        ? 'Escolhe o destino'
                        : isFree
                            ? 'Grátis  ·  ${km!.toStringAsFixed(1)} km'
                            : '€${(payableCents / 100).toStringAsFixed(2)}  ·  ${km!.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700),
                  ),
                if (message != null && hasKm) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(isFree ? Icons.check_circle : Icons.info_outline,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(message!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Frente 3 — folha de pagamento (aparece SÓ depois de "Solicitar corrida",
/// como no checkout do delivery): mostra o valor final + os métodos e confirma.
/// Dinheiro sempre; Cartão/MB Way só se [allowOnline] (switch on + tarifa normal).
class _TvdePaymentSheet extends StatefulWidget {
  const _TvdePaymentSheet({
    required this.amountCents,
    required this.message,
    required this.allowOnline,
  });
  final int amountCents;
  final String? message;
  final bool allowOnline;

  @override
  State<_TvdePaymentSheet> createState() => _TvdePaymentSheetState();
}

class _TvdePaymentSheetState extends State<_TvdePaymentSheet> {
  String _method = 'cash';

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final eur = '€${(widget.amountCents / 100).toStringAsFixed(2)}';
    return Padding(
      padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: Spacing.lg + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.payments_outlined, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              const Expanded(
                child: Text('Pagamento',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          Text('Total: $eur',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          if (widget.message != null) ...[
            const SizedBox(height: 4),
            Text(widget.message!,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: Spacing.md),
          TvdePaymentSelector(
            current: _method,
            cardEnabled: widget.allowOnline,
            onChanged: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: Spacing.lg),
          BoraAccentButton(
            label: _method == 'cash'
                ? 'Confirmar · pagar em dinheiro'
                : 'Pagar $eur',
            icon: Icons.check,
            onPressed: () => Navigator.pop(context, _method),
          ),
        ],
      ),
    );
  }
}

/// [F3] Toggle "Garantir a volta" — pacote ida+volta pago adiantado.
class _RoundtripToggle extends StatelessWidget {
  const _RoundtripToggle(
      {required this.value, required this.priceCents, required this.onChanged});
  final bool value;
  final int priceCents;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(
            color: value ? AppColors.primary : AppColors.divider),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.md),
        title: const Row(
          children: [
            Icon(Icons.sync_alt, size: 18, color: AppColors.primary),
            SizedBox(width: Spacing.sm),
            Text('Garantir a volta',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Pacote ida + volta por €${(priceCents / 100).toStringAsFixed(2)}, pago já. '
            'Chamas a volta quando quiseres, dentro do prazo.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSubtle),
          ),
        ),
      ),
    );
  }
}

/// [F3] Card do vale-volta ativo (topo do ecrã) com "Chamar a volta".
class _ReturnCreditCard extends StatelessWidget {
  const _ReturnCreditCard(
      {required this.credit, required this.busy, required this.onCall});
  final Map<String, dynamic> credit;
  final bool busy;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final expStr = credit['expires_at']?.toString();
    final exp = expStr == null ? null : DateTime.tryParse(expStr);
    String prazo = '';
    if (exp != null) {
      final left = exp.difference(DateTime.now());
      if (!left.isNegative) {
        final h = left.inHours;
        final m = left.inMinutes % 60;
        prazo = h > 0
            ? 'Válido mais ${h}h${m.toString().padLeft(2, '0')}'
            : 'Válido mais ${left.inMinutes} min';
      }
    }
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_alt, color: Colors.white),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tens uma volta garantida',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                if (prazo.isNotEmpty)
                  Text(prazo,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          FilledButton(
            onPressed: busy ? null : onCall,
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary),
            child: const Text('Chamar a volta'),
          ),
        ],
      ),
    );
  }
}

/// Destino escolhido para a corrida de volta.
class _ReturnDest {
  const _ReturnDest({required this.label, required this.lat, required this.lng});
  final String label;
  final double lat;
  final double lng;
}

/// [F3] Folha para escolher o destino da volta (reusa AddressAutocompleteField).
class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet();
  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final TextEditingController _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.lg,
          bottom: Spacing.lg + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_alt, color: AppColors.primary),
              const SizedBox(width: Spacing.sm),
              const Expanded(
                child: Text('Chamar a minha volta',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          const Text('Para onde vais agora? A recolha é a tua localização atual.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: Spacing.md),
          AddressAutocompleteField(
            controller: _c,
            labelText: 'Destino da volta',
            onSelected: (address, coords) {
              if (coords == null) return;
              Navigator.pop(
                  context,
                  _ReturnDest(
                      label: address,
                      lat: coords.latitude,
                      lng: coords.longitude));
            },
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }
}
