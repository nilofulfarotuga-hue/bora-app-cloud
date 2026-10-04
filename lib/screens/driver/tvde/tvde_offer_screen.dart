import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../services/sound_service.dart';
import '../../../stores/driver_store.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/tvde/tvde_counter_ride_badge.dart';
import '../../../widgets/tvde/tvde_offer_overlay_host.dart';
import '../../../widgets/tvde/tvde_pay_badge.dart';
import '../../../widgets/tvde/tvde_roundtrip_driver_notice.dart';

/// TVDE — Ecrã de OFERTA ao motorista (passageiros). Aceite por TOCAR aqui
/// (nunca pelos botões de ação da notificação — bug conhecido em background).
/// Countdown server-side: o `offer_expires_at` + sweep tratam o timeout; aqui
/// só refletimos. Aceite atómico — se a corrida já foi levada, mostramos aviso.
class TvdeOfferScreen extends StatefulWidget {
  const TvdeOfferScreen({super.key, required this.ride});
  final TvdeRide ride;

  /// SÓ PARA TESTES. O som (AudioPlayer) e o mini-mapa (vista nativa) não
  /// existem num teste de widget; com isto a true o ecrã monta-se sem eles e
  /// todo o resto — fechar, aceitar, recusar — é o código real. Nunca
  /// escrever aqui em código de produção.
  @visibleForTesting
  static bool debugSemPlataforma = false;

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

  /// [É dele · 04/10] O Aceitar DESTE ecrã vai a caminho do servidor (o
  /// `_acting` também serve o Recusar, por isso não chega para o rótulo).
  bool _aceitando = false;

  /// Som CONTÍNUO da oferta (padrão Uber/estafeta) — mesmo `SoundService` +
  /// `bora_alert.wav` que o fluxo de entrega usa em `playLoop`. Instância
  /// própria (AudioPlayer isolado, ver doc do SoundService).
  final SoundService? _sound =
      TvdeOfferScreen.debugSemPlataforma ? null : SoundService();

  // [Recusa fantasma · 25/09] Mesmas guardas do cartão sobreposto: o Recusar
  // não faz nada no primeiro segundo e pede um segundo toque.
  bool _podeRecusar = false;
  bool _confirmarRecusa = false;
  Timer? _guardaAparecer;
  Timer? _janelaRecusa;
  String? _guardaDe;

  void _armarGuardaRecusa(String rideId) {
    _guardaDe = rideId;
    _podeRecusar = false;
    _confirmarRecusa = false;
    _janelaRecusa?.cancel();
    _guardaAparecer?.cancel();
    _guardaAparecer = Timer(kTvdeRecusaGuardaAoAparecer, () {
      if (mounted) setState(() => _podeRecusar = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _armarGuardaRecusa(widget.ride.id);
    // [Oferta sobreposta 20/09] Enquanto este ecrã mostra a oferta em ecrã
    // inteiro, o cartão global (TvdeOfferOverlayHost) não a duplica por cima.
    _marcarEcraInteiro(widget.ride.id);
    // A1 — arranca o som contínuo até aceitar/recusar/expirar.
    _sound?.playLoop();
    // A contagem é recalculada a cada segundo a partir da oferta VIVA (store)
    // no build — assim um re-offer renova o tempo em vez de ficar preso em "0 s".
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (TvdeOfferPresentation.fullScreenRideId.value == _marcada) {
      TvdeOfferPresentation.fullScreenRideId.value = null;
    }
    _ticker?.cancel();
    _guardaAparecer?.cancel();
    _janelaRecusa?.cancel();
    _sound?.stop();
    _sound?.dispose();
    super.dispose();
  }

  /// A corrida que este ecrã está a anunciar ao cartão global. Num re-offer
  /// (outra corrida a entrar com este ecrã aberto) acompanha a nova.
  String? _marcada;
  void _marcarEcraInteiro(String rideId) {
    _marcada = rideId;
    TvdeOfferPresentation.fullScreenRideId.value = rideId;
  }

  /// A rota DESTE ecrã, guardada para se poder fechar a si próprio mesmo
  /// quando já não é o ecrã de cima.
  ModalRoute<dynamic>? _rota;
  bool _fechada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rota = ModalRoute.of(context);
  }

  /// [Oferta fantasma · 01/10 · corrida 03874579] Fecha ESTE ecrã — nunca
  /// "o ecrã de cima".
  ///
  /// O Danilo aceitou 1 s depois do push. O realtime chegou antes da resposta
  /// do aceite, a home abriu o ecrã da corrida POR CIMA deste, e o
  /// `Navigator.pop()` que vinha a seguir fechou a corrida em vez da oferta.
  /// A oferta ficou por baixo, já sem som nem contagem e com os botões
  /// mortos; ao terminar a viagem reapareceu, e o `PopScope` não o deixava
  /// sair. Por isso: se este ecrã está em cima, `pop` (explícito — o
  /// `maybePop` é travado pelo `canPop: false`); se está por baixo de outro,
  /// tira-se a rota do meio sem tocar na de cima.
  void _fecharEstaRota([Object? resultado]) {
    if (_fechada || !mounted) return;
    final rota = _rota;
    if (rota == null || !rota.isActive) return;
    _fechada = true;
    final nav = Navigator.of(context);
    if (rota.isCurrent) {
      nav.pop(resultado);
    } else {
      nav.removeRoute(rota);
    }
  }

  void _autoClose() {
    if (_closing) return;
    _closing = true;
    _ticker?.cancel();
    _sound?.stop();
    _fecharEstaRota();
  }

  Future<void> _accept() async {
    if (_acting) return;
    _acting = true;
    _aceitando = true;
    final store = context.read<TvdeDriverStore>();
    _closing = true; // guarda contra duplo-pop durante o rebuild reativo
    _ticker?.cancel();
    _sound?.stop();
    try {
      await store.acceptOffer(widget.ride.id);
      _fecharEstaRota(true); // home roteia para o ecrã ativo
    } catch (_) {
      store.clearOffer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta corrida já não está disponível.')),
      );
      _fecharEstaRota();
    }
  }

  Future<void> _reject() async {
    if (_acting || !_podeRecusar) return;
    if (!_confirmarRecusa) {
      setState(() => _confirmarRecusa = true);
      _janelaRecusa?.cancel();
      _janelaRecusa = Timer(kTvdeRecusaJanelaConfirmar, () {
        if (mounted) setState(() => _confirmarRecusa = false);
      });
      return;
    }
    _janelaRecusa?.cancel();
    _acting = true;
    _sound?.stop();
    final store = context.read<TvdeDriverStore>();
    final rideId = widget.ride.id;
    // [Recusar não fecha · 03/10 · corrida 540b738a] Fecha JÁ; a recusa
    // segue em fundo. Antes o ecrã esperava pela rede e o motorista
    // carregava várias vezes.
    _autoClose();
    try {
      await store.rejectOffer(rideId);
    } catch (_) {
      // best-effort — o dispatch trata a rotação/sem_motorista
      store.clearOffer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    // Oferta VIVA: a store atualiza-a no re-offer, por isso o ecrã reflete
    // sempre a oferta atual — a contagem e os dados RENOVAM no re-offer.
    final ride = store.offeredRide ?? widget.ride;
    if (!_closing && _marcada != ride.id) {
      // Fora do build (mexer no notifier aqui rebentava o host a meio do
      // frame): no fim do frame o cartão global fica a saber da nova.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closing) {
          _marcarEcraInteiro(ride.id);
          // Re-offer: a oferta nova ganha as mesmas guardas do Recusar.
          if (_guardaDe != ride.id) setState(() => _armarGuardaRecusa(ride.id));
        }
      });
    }
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
    // [Oferta fantasma 01/10] Rede de segurança: a corrida deste ecrã já é
    // dele (activa ou em fila), ou deixou de estar à procura de motorista.
    // Este ecrã não tem mais nada a mostrar — sai, mesmo com `_closing` a
    // true (o aceite ainda à espera da resposta) e mesmo por baixo de outro.
    final jaNaoEOferta = store.activeRide?.id == widget.ride.id ||
        store.queuedRide?.id == widget.ride.id ||
        ride.status != 'solicitada';
    if (jaNaoEOferta && !_fechada) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _closing = true;
        _ticker?.cancel();
        _sound?.stop();
        _fecharEstaRota();
      });
    }
    // [É dele · 04/10 · corrida 8c7f5ca6] Com o aceite a caminho do servidor
    // (por este ecrã ou pelo botão da notificação) o prazo já não conta: não
    // se diz "A reatribuir…" de uma corrida que ele acabou de aceitar.
    // [Nada por cima · 04/10] Aceitou pelo botão da NOTIFICAÇÃO com este ecrã
    // aberto: o som em ciclo cala-se já e os botões daqui deixam de responder
    // (um segundo aceite falhava). O ecrã fecha quando a corrida for dele —
    // ou, se o aceite falhar, quando o gancho limpar a oferta.
    if (!_aceitando && store.aceiteEmCurso(ride.id)) {
      _aceitando = true;
      _acting = true;
      _sound?.stop();
    }
    final countdownLabel = _aceitando
        ? 'A aceitar…'
        : (secs > 0 ? '$secs s' : 'A reatribuir…');

    // [Item C] o motorista vê o SEU líquido (ganho), não o total do cliente.
    // [Balcão] o valor combinado manda quando existe — nunca recalculado aqui.
    final net = (ride.netDriverEarnCents / 100).toStringAsFixed(2);
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
                const SizedBox(height: Spacing.md),
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
                const SizedBox(height: Spacing.md),
                // O cartão rola quando não cabe (ecrãs baixos/teclado) — os
                // botões Aceitar/Recusar ficam SEMPRE visíveis em baixo.
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
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
                      // PART2 — método de pagamento visível já na oferta.
                      const SizedBox(height: Spacing.sm),
                      Center(child: TvdePayBadge(ride: ride)),
                      // [Balcão] cliente sem app — selo visível desde a oferta.
                      if (ride.isCounterRide) ...[
                        const SizedBox(height: Spacing.xs),
                        const Center(child: TvdeCounterRideBadge()),
                      ],
                      // [Fase B] Pacote €8: o motorista tem de saber, ANTES de
                      // aceitar, que os €8 do cliente não são o ganho dele.
                      if (ride.isRoundtripLeg) ...[
                        const SizedBox(height: Spacing.sm),
                        TvdeRoundtripDriverNotice(ride: ride),
                      ],
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
                      // Mini-mapa recolha→destino (padrão Uber/Bolt/99): o
                      // motorista vê ONDE é a corrida antes de aceitar.
                      const SizedBox(height: Spacing.md),
                      if (!TvdeOfferScreen.debugSemPlataforma)
                        _OfferMiniMap(ride: ride),
                      const SizedBox(height: Spacing.md),
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
                  ),
                ),
                const SizedBox(height: Spacing.md),
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
                  key: const Key('tvde_ecra_oferta_recusar'),
                  onPressed: _acting ? null : _reject,
                  child: Text(
                      _confirmarRecusa
                          ? 'Toca outra vez para recusar'
                          : 'Recusar',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: _confirmarRecusa
                              ? FontWeight.w800
                              : FontWeight.w400)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini-mapa NÃO interativo da oferta: recolha (verde) → destino (laranja) com
/// linha tracejada. `liteModeEnabled` (Android) renderiza como bitmap — barato,
/// não rouba frames ao mapa da home que fica por baixo. Câmara ajustada por
/// heurística de zoom (fallback) + fit aos bounds no onMapCreated (best-effort).
class _OfferMiniMap extends StatelessWidget {
  const _OfferMiniMap({required this.ride});
  final TvdeRide ride;

  @override
  Widget build(BuildContext context) {
    final origin = gmaps.LatLng(ride.originLat, ride.originLng);
    final dest = gmaps.LatLng(ride.destLat, ride.destLng);
    final center = gmaps.LatLng(
      (ride.originLat + ride.destLat) / 2,
      (ride.originLng + ride.destLng) / 2,
    );
    final km = ride.estDistanceKm;
    final double zoom = km <= 1
        ? 14
        : km <= 2
            ? 13
            : km <= 4
                ? 12.2
                : km <= 8
                    ? 11.2
                    : km <= 16
                        ? 10.2
                        : 9;
    final bounds = gmaps.LatLngBounds(
      southwest: gmaps.LatLng(
        origin.latitude < dest.latitude ? origin.latitude : dest.latitude,
        origin.longitude < dest.longitude ? origin.longitude : dest.longitude,
      ),
      northeast: gmaps.LatLng(
        origin.latitude > dest.latitude ? origin.latitude : dest.latitude,
        origin.longitude > dest.longitude ? origin.longitude : dest.longitude,
      ),
    );
    final compact = MediaQuery.of(context).size.height < 700;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        height: compact ? 110 : 150,
        child: IgnorePointer(
          child: gmaps.GoogleMap(
            initialCameraPosition:
                gmaps.CameraPosition(target: center, zoom: zoom),
            liteModeEnabled: !kIsWeb,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            markers: {
              gmaps.Marker(
                markerId: const gmaps.MarkerId('offer_origin'),
                position: origin,
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                    gmaps.BitmapDescriptor.hueGreen),
              ),
              gmaps.Marker(
                markerId: const gmaps.MarkerId('offer_dest'),
                position: dest,
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                    gmaps.BitmapDescriptor.hueOrange),
              ),
            },
            polylines: {
              gmaps.Polyline(
                polylineId: const gmaps.PolylineId('offer_line'),
                points: [origin, dest],
                color: AppColors.primary,
                width: 4,
                patterns: [gmaps.PatternItem.dash(18), gmaps.PatternItem.gap(10)],
              ),
            },
            onMapCreated: (c) {
              // Fit exato aos dois pontos; se o mapa ainda não tiver layout,
              // fica a heurística de zoom (nunca rebenta a oferta por isto).
              try {
                c.moveCamera(gmaps.CameraUpdate.newLatLngBounds(bounds, 36));
              } catch (_) {}
            },
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
