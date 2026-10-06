import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/tvde_ride.dart';
import '../../screens/driver/tvde/tvde_ride_active_screen.dart';
import '../../services/notification_service.dart';
import '../../stores/tvde_driver_store.dart';
import 'tvde_counter_ride_badge.dart';
import 'tvde_pay_badge.dart';
import 'tvde_reservation_offer_card.dart';

/// [Oferta sobreposta 20/09/2026] O ÚNICO caminho de apresentação de uma
/// oferta TVDE dentro da app — esteja o motorista onde estiver.
///
/// **A cicatriz.** A 20/09 o Danilo estava no ecrã da corrida activa quando
/// lhe entrou a oferta da reserva da meia-noite. O toque chegou, o cartão não:
/// o `TvdeReservationOfferCard` vivia SÓ dentro da home do motorista, tapado
/// pelo ecrã da corrida. Não havia forma de aceitar. E a faixa da oferta
/// imediata só existia nesse ecrã da corrida — no chat com o passageiro, na
/// agenda, nos ganhos, no fluxo de entrega, nada.
///
/// **Como passou a ser.** Este widget envolve o `Navigator` inteiro (vive no
/// `MaterialApp.builder`, ver `main.dart`), por isso o cartão desenha-se POR
/// CIMA de qualquer rota: corrida activa, chat, agenda, ganhos, definições,
/// entregas, outro papel. Lê o `TvdeDriverStore` e mostra:
///  - a oferta IMEDIATA (`current_offer_driver_id`) — "agora" se ele está
///    livre, "depois desta corrida" se leva passageiro;
///  - a oferta de RESERVA (`reservation_offer_driver_id`) — com a hora
///    marcada. É o caso que falhou a 20/09.
///
/// Aceitar e Recusar estão SEMPRE visíveis e clicáveis enquanto a oferta
/// vive. Quando o prazo passa nas mãos dele, o cartão diz-lhe que a corrida
/// já foi para outro motorista e fecha-se sozinho — nunca desaparece em
/// silêncio (era o `SizedBox.shrink()` da faixa antiga).
///
/// O ecrã de oferta em ecrã inteiro (`TvdeOfferScreen`, motorista livre na
/// home) continua a existir: enquanto ele está aberto para essa corrida, este
/// cartão esconde-se — ver [TvdeOfferPresentation].
///
/// **[A11 · 22/09] Por cima, mas sem tapar a corrida.** A correcção de 21/09
/// pôs o cartão global no topo de TODOS os ecrãs — e no ecrã da corrida
/// activa isso tapava a AppBar (o menu "Cancelar corrida / Passageiro não
/// compareceu") e o topo do mapa durante os 5 minutos da oferta de reserva,
/// sem botão para fechar. Regra que fica: com a corrida activa aberta
/// ([TvdeOfferPresentation.corridaActivaAberta]) o cartão desce para BAIXO
/// da AppBar; a oferta imediata continua inteira (Aceitar/Recusar com
/// contagem — é urgente) e a de reserva entra COMPACTA (uma faixa com "Ver"
/// e "Recusar"; "Ver" abre o cartão inteiro, que se volta a minimizar). Em
/// qualquer outro ecrã nada mudou: cartão inteiro, no topo.
class TvdeOfferOverlayHost extends StatefulWidget {
  const TvdeOfferOverlayHost({super.key, required this.child});

  final Widget child;

  @override
  State<TvdeOfferOverlayHost> createState() => _TvdeOfferOverlayHostState();
}

/// [Recusa fantasma · 25/09] Guardas do Recusar da oferta imediata, iguais no
/// cartão sobreposto e no `TvdeOfferScreen`: o primeiro segundo depois de a
/// oferta aparecer não recusa (o toque era para o ecrã de baixo) e recusar
/// pede um segundo toque dentro desta janela.
const Duration kTvdeRecusaGuardaAoAparecer = Duration(seconds: 1);
const Duration kTvdeRecusaJanelaConfirmar = Duration(seconds: 3);

/// [Cartão preso · 06/10] Prazo a 0 com o aceite "a decorrer": ao fim de
/// quanto tempo o cartão pergunta ao servidor de quem é a corrida (e de
/// quanto em quanto volta a perguntar), e quando desiste de esperar. 16 s
/// passa folgado o tempo máximo do aceite (`kAcaoTimeout`, 12 s).
const Duration kTvdeAceitePenduradoPergunta = Duration(seconds: 4);
const Duration kTvdeAceitePenduradoDesiste = Duration(seconds: 16);

/// Coordenação entre o cartão global e o `TvdeOfferScreen` (ecrã inteiro).
class TvdeOfferPresentation {
  TvdeOfferPresentation._();

  /// Corrida que o `TvdeOfferScreen` está a mostrar em ecrã inteiro. Enquanto
  /// for a mesma da oferta, o cartão global não a duplica.
  static final ValueNotifier<String?> fullScreenRideId =
      ValueNotifier<String?>(null);

  /// [A11 · 22/09] SÓ PARA TESTES. `TvdeRideActiveScreen.estaAberto` conta
  /// ecrãs montados e não se finge num teste de widget sem montar o ecrã real
  /// (mapa, GPS, Supabase). Quando isto NÃO é null substitui essa leitura:
  /// `true` = "o ecrã da corrida activa está aberto", `false` = "não está".
  /// A outra metade da decisão (`store.activeRide?.isLive`) continua a valer
  /// — finge-se com `TvdeDriverStore.debugInjectar(activa: …)`. Nunca
  /// escrever aqui em código de produção; o teste repõe a null no fim.
  static final ValueNotifier<bool?> activeRideOpenOverride =
      ValueNotifier<bool?>(null);

  /// [Cartão preso · 06/10 · corrida 3835a143] A corrida que o
  /// `TvdeRideActiveScreen` está a mostrar (null = nenhum aberto). O cartão
  /// nunca desenha a oferta dessa corrida, diga o store o que disser: o
  /// motorista já a está a fazer.
  static final ValueNotifier<String?> corridaMostrada =
      ValueNotifier<String?>(null);

  /// A corrida activa manda no ecrã? Sim quando o ecrã dela está montado OU
  /// há uma corrida viva no store (a home abre o ecrã por causa dela). Nesse
  /// caso a oferta desenha-se ABAIXO da AppBar e a reserva em modo compacto
  /// — ver [TvdeOfferOverlayHost].
  static bool corridaActivaAberta(TvdeDriverStore store) {
    final ecraAberto =
        activeRideOpenOverride.value ?? TvdeRideActiveScreen.estaAberto;
    return ecraAberto || (store.activeRide?.isLive == true);
  }
}

class _TvdeOfferOverlayHostState extends State<TvdeOfferOverlayHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TvdeOfferPresentation.fullScreenRideId.addListener(_onPresentationChanged);
    TvdeOfferPresentation.activeRideOpenOverride
        .addListener(_onPresentationChanged);
    TvdeOfferPresentation.corridaMostrada.addListener(_onPresentationChanged);
  }

  @override
  void dispose() {
    TvdeOfferPresentation.fullScreenRideId
        .removeListener(_onPresentationChanged);
    TvdeOfferPresentation.activeRideOpenOverride
        .removeListener(_onPresentationChanged);
    TvdeOfferPresentation.corridaMostrada
        .removeListener(_onPresentationChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _redesenhoAgendado = false;

  /// [Cartão preso · 06/10 · corrida 3835a143] NUNCA `setState` a meio de um
  /// build.
  ///
  /// **A cicatriz.** O ecrã "Nova corrida" avisa este host no `initState`
  /// (`fullScreenRideId`), e o `initState` corre A MEIO do build do frame —
  /// depois de este host, que está mais acima na árvore, já se ter desenhado.
  /// Em modo debug isso rebenta ("setState() called during build"); na app
  /// publicada o Flutter salta o host nesse frame e deixa-o marcado como
  /// "por redesenhar" para sempre: todos os avisos seguintes do store eram
  /// ignorados. O cartão ficou congelado com o que tinha no último desenho —
  /// "Nova corrida — agora", aceite a decorrer — e o próprio relógio dele
  /// levou a contagem a "0s" por cima da corrida que o motorista já levava.
  /// O servidor e o store estavam certos (a releitura de 10 em 10 s só corre
  /// sem oferta no store, e correu o minuto todo).
  ///
  /// Regra: a meio de um frame, o redesenho fica para o fim desse frame.
  void _onPresentationChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_redesenhoAgendado) return;
    _redesenhoAgendado = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _redesenhoAgendado = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltar ao primeiro plano (tocou na notificação, fechou o Waze, voltou
    // do chat) relê as duas ofertas do servidor. Sem isto, uma oferta que
    // chegou com a app em segundo plano só aparecia se a home estivesse
    // montada por baixo — e uma oferta recusada pelo botão da notificação
    // (caminho sem UI) ficava no ecrã até expirar.
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    unawaited(context.read<TvdeDriverStore>().reloadOffers());
  }

  void _snack(String texto) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _aceitarOferta(TvdeDriverStore store, TvdeRide offer) async {
    try {
      final r = await store.acceptOffer(offer.id);
      if (!mounted) return;
      _snack(r.isQueued
          ? 'Corrida em fila — abre sozinha quando terminares esta.'
          : 'Corrida aceite.');
      if (!r.isQueued) unawaited(abrirCorridaActivaSeFechada());
    } catch (e) {
      store.clearOffer();
      if (!mounted) return;
      _snack(mensagemDeOfertaFalhada(e));
    }
  }

  Future<void> _recusarOferta(TvdeDriverStore store, TvdeRide offer) async {
    try {
      await store.rejectOffer(offer.id);
    } catch (_) {
      // A rotação do servidor segue de qualquer forma; a oferta sai do ecrã.
      store.clearOffer();
    }
  }

  Future<void> _aceitarReserva(TvdeDriverStore store, TvdeRide r) async {
    try {
      await store.acceptReservation(r.id);
      if (!mounted) return;
      _snack('Reserva aceite. Fica na tua agenda — avisamos-te perto da '
          'hora.');
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().contains('offer_no_longer_valid')
          ? 'Essa reserva já não está disponível.'
          : 'Não consegui aceitar a reserva. Tenta outra vez.');
      unawaited(store.loadAgenda());
    }
  }

  Future<void> _recusarReserva(TvdeDriverStore store, TvdeRide r) async {
    try {
      await store.rejectReservation(r.id);
    } catch (_) {
      store.clearReservationOffer();
    }
  }

  /// [É dele · 04/10 · corrida 8c7f5ca6] O prazo passou no cartão: antes do
  /// aviso "foi para outro", pergunta-se ao servidor de quem é a corrida. Se
  /// for dele (aceitou por outro caminho ou noutro aparelho), o store relê,
  /// o cartão fecha em silêncio e abre-se a corrida — nunca o aviso.
  Future<bool> _ofertaEMinha(TvdeDriverStore store, String rideId) async {
    final minha = await store.ofertaExpiradaEMinha(rideId);
    if (minha) unawaited(abrirCorridaActivaSeFechada());
    return minha;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    // [Oferta fantasma 01/10] Só se desenha uma oferta que ainda o é: não é
    // a corrida que ele já leva (activa/fila), continua à procura de
    // motorista, é para ele e ainda não lhe respondeu.
    final emMemoria = store.offeredRide;
    final offer = emMemoria != null && store.ofertaApresentavel(emMemoria)
        ? emMemoria
        : null;
    final reserva = store.reservationOffer;
    final emEcraInteiro = TvdeOfferPresentation.fullScreenRideId.value;
    final corridaActiva = TvdeOfferPresentation.corridaActivaAberta(store);
    // [Cartão preso · 06/10] A corrida aberta no ecrã da corrida nunca é
    // oferta — compara-se pelo id que esse ecrã mostra, não só pelo store.
    final mostrada = TvdeOfferPresentation.corridaMostrada.value;

    Widget? cartao;
    if (offer != null && offer.id != emEcraInteiro && offer.id != mostrada) {
      cartao = TvdeOfferOverlayCard(
        key: ValueKey<String>('oferta-sobreposta-${offer.id}'),
        offer: offer,
        current: store.activeRide,
        onAccept: () => _aceitarOferta(store, offer),
        onReject: () => _recusarOferta(store, offer),
        // Mal expira, a notificação persistente morre JÁ (era ela, ainda em
        // heads-up, que tapava a frase honesta no emulador a 21/09) — o cartão
        // fica uns segundos a dizer o que aconteceu e só depois sai do store.
        onExpired: () => unawaited(cancelTvdeRideNotification(offer.id)),
        onExpiredDismiss: store.clearOffer,
        // [É dele · 04/10] Aceite a decorrer (por qualquer caminho) → espera;
        // prazo passado → confirma primeiro que a corrida não é dele.
        aAceitar: store.aceiteEmCurso(offer.id),
        eMinha: () => _ofertaEMinha(store, offer.id),
      );
    } else if (reserva != null) {
      cartao = TvdeReservationOverlayCard(
        key: ValueKey<String>('reserva-sobreposta-${reserva.id}'),
        ride: reserva,
        onAccept: () => _aceitarReserva(store, reserva),
        onReject: () => _recusarReserva(store, reserva),
        onExpired: () => unawaited(cancelTvdeRideNotification(reserva.id)),
        onExpiredDismiss: store.clearReservationOffer,
        // [É dele · 04/10] A mesma regra da imediata, pelo dono da reserva.
        aAceitar: store.aceiteEmCurso(reserva.id),
        eMinha: () => store.ofertaExpiradaEMinha(reserva.id, reserva: true),
        // [A11] Com a corrida activa aberta a reserva vive 5 min — entra
        // como faixa de uma linha para não tapar os comandos da corrida.
        compacto: corridaActiva,
      );
    }

    // [A11 · 22/09] Com a corrida activa aberta, o cartão desce para baixo da
    // AppBar dela (barra de estado + kToolbarHeight): o menu "Cancelar
    // corrida / Passageiro não compareceu" e o topo do mapa ficam livres.
    // Nos outros ecrãs fica como a 21/09: por cima da barra de estado e da
    // AppBar do ecrã que estiver aberto — é para ser visto, não para ser
    // bonito.
    final topo = MediaQuery.paddingOf(context).top +
        8 +
        (corridaActiva ? kToolbarHeight : 0);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (cartao != null)
          Positioned(
            top: topo,
            left: 12,
            right: 12,
            child: Material(
              type: MaterialType.transparency,
              child: cartao,
            ),
          ),
      ],
    );
  }
}

/// Traduz a falha do `tvde_accept_ride` para uma frase que o motorista
/// percebe. Pública para o gancho da notificação usar a mesma.
String mensagemDeOfertaFalhada(Object e) {
  final s = e.toString();
  if (s.contains('queue_full')) {
    return 'Já tens uma corrida em fila — só podes levar uma de cada vez.';
  }
  if (s.contains('ride_conflict')) {
    return 'Não consegui aceitar: já tens outra corrida a decorrer.';
  }
  return 'Esta corrida já não está disponível.';
}

/// Abre o ecrã da corrida activa se ainda não estiver aberto.
///
/// Normalmente é a home do motorista que o abre (reage ao store). Mas a home
/// só está montada quando a pessoa está no papel de motorista; quem aceita
/// uma corrida a partir do chat, da agenda ou de outro papel precisa de
/// alguém que abra o ecrã. Espera um bocadinho pela home; se ela não o fez,
/// faz-se aqui. Nunca abre dois.
Future<void> abrirCorridaActivaSeFechada() async {
  await Future<void>.delayed(const Duration(milliseconds: 700));
  if (TvdeOfferPresentation.activeRideOpenOverride.value ??
      TvdeRideActiveScreen.estaAberto) {
    return;
  }
  final ctx = NotificationService.navigatorKey.currentContext;
  final nav = NotificationService.navigatorKey.currentState;
  if (ctx == null || nav == null || !ctx.mounted) return;
  final store = ctx.read<TvdeDriverStore>();
  final active = store.activeRide;
  if (active == null || !active.isLive) return;
  nav.push(MaterialPageRoute<void>(
      builder: (_) => const TvdeRideActiveScreen()));
}

/// Cartão compacto da oferta IMEDIATA, por cima de qualquer ecrã.
///
/// Sem estado guardado da contagem: os segundos calculam-se do prazo em CADA
/// rebuild (o ticker só obriga a redesenhar). A faixa antiga guardava
/// `_secondsLeft` e só o recalculava no `didUpdateWidget` — com a oferta já
/// morta desenhava `SizedBox.shrink()`: ecrã vazio, sem explicação.
class TvdeOfferOverlayCard extends StatefulWidget {
  const TvdeOfferOverlayCard({
    super.key,
    required this.offer,
    required this.current,
    required this.onAccept,
    required this.onReject,
    required this.onExpiredDismiss,
    this.onExpired,
    this.agora,
    this.tempoAteFechar = const Duration(seconds: 5),
    this.aAceitar = false,
    this.eMinha,
  });

  /// [É dele · 04/10] O aceite desta corrida está a caminho do servidor por
  /// OUTRO caminho que não o botão deste cartão (botão da notificação). O
  /// cartão fica à espera e nunca mostra o aviso de expirada.
  final bool aAceitar;

  /// [É dele · 04/10] Perguntada UMA vez quando o prazo passa: a corrida é
  /// deste motorista? `true` → fecha em silêncio ([onExpiredDismiss] já), sem
  /// aviso. `false`/erro → o aviso de sempre. Null (testes, uso solto) → o
  /// aviso aparece logo, como antes.
  final Future<bool> Function()? eMinha;

  final TvdeRide offer;

  /// A corrida que ele está a fazer (null = livre). Dá o texto "depois desta
  /// corrida" e a distância "onde vou largar → onde vou buscar".
  final TvdeRide? current;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  /// Chamado uma vez, uns segundos depois de o prazo passar, para o cartão
  /// sair do ecrã (o store limpa a oferta).
  final VoidCallback onExpiredDismiss;

  /// Chamado uma vez, NO MOMENTO em que o prazo passa (antes do
  /// [onExpiredDismiss]) — o host mata logo a notificação.
  final VoidCallback? onExpired;

  /// Relógio injectável (testes).
  final DateTime Function()? agora;
  final Duration tempoAteFechar;

  @override
  State<TvdeOfferOverlayCard> createState() => _TvdeOfferOverlayCardState();
}

class _TvdeOfferOverlayCardState extends State<TvdeOfferOverlayCard> {
  Timer? _ticker;
  Timer? _fecho;
  Timer? _timeoutResposta;

  /// Guarda LOCAL de resposta (PADRAO_BORA 3.13): nunca o `busy` global do
  /// store. Destrava-se sozinha ao fim de uns segundos.
  bool _respondendo = false;
  bool _expirouAvisado = false;

  // [Recusa fantasma · 25/09 · corrida 258233c3] A app recusou 14 s depois
  // de a oferta entrar, logo a seguir a uma corrida cancelada pelo cliente,
  // sem o motorista querer recusar. O registo do servidor mostra que foi o
  // botão do cartão (cliente supabase-flutter, não o botão da notificação):
  // o cartão nasce POR CIMA do ecrã em que ele estava a mexer e o toque
  // dirigido a esse ecrã caía no Recusar. Duas guardas, só no Recusar:
  //  1. no primeiro segundo depois de a oferta aparecer não faz nada;
  //  2. pede um segundo toque ("Confirmar recusa", 3 s para o dar).
  // Aceitar continua a um toque. Expirar nunca chama o recusar.
  bool _podeRecusar = false;
  bool _confirmarRecusa = false;
  Timer? _guardaAparecer;
  Timer? _janelaRecusa;

  DateTime get _now => (widget.agora ?? DateTime.now)();

  /// [Oferta fantasma 01/10] Prazo LOCAL para a oferta que chega sem
  /// `offer_expires_at`: 25 s a contar de quando o cartão a mostrou. Antes o
  /// cartão ficava congelado em "25s" para sempre, sem nunca se fechar.
  late DateTime _prazoLocal;

  @override
  void initState() {
    super.initState();
    _prazoLocal = _now.add(const Duration(seconds: 25));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _vigiarAceitePendurado();
      setState(() {});
    });
    _armarGuardaRecusa();
  }

  @override
  void didUpdateWidget(covariant TvdeOfferOverlayCard old) {
    super.didUpdateWidget(old);
    if (old.offer.id != widget.offer.id) {
      _prazoLocal = _now.add(const Duration(seconds: 25));
      _timeoutResposta?.cancel();
      _respondendo = false;
      _fecho?.cancel();
      _expirouAvisado = false;
      _perdida = false;
      _fechada = false;
      _penduradoDesde = null;
      _ultimaPergunta = null;
      _armarGuardaRecusa();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _fecho?.cancel();
    _timeoutResposta?.cancel();
    _guardaAparecer?.cancel();
    _janelaRecusa?.cancel();
    super.dispose();
  }

  void _armarGuardaRecusa() {
    _podeRecusar = false;
    _confirmarRecusa = false;
    _janelaRecusa?.cancel();
    _guardaAparecer?.cancel();
    _guardaAparecer = Timer(kTvdeRecusaGuardaAoAparecer, () {
      if (mounted) setState(() => _podeRecusar = true);
    });
  }

  int get _segundosRestantes {
    final exp = widget.offer.offerExpiresAt ?? _prazoLocal;
    final s = exp.difference(_now).inSeconds;
    return s > 0 ? s : 0;
  }

  bool get _expirada => _segundosRestantes <= 0;

  void _travar() {
    setState(() => _respondendo = true);
    _timeoutResposta?.cancel();
    _timeoutResposta = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _respondendo = false);
    });
  }

  Future<void> _tapAceitar() async {
    if (_respondendo) return;
    _travar();
    try {
      await widget.onAccept();
    } finally {
      if (mounted) setState(() => _respondendo = false);
    }
  }

  Future<void> _tapRecusar() async {
    if (_respondendo || !_podeRecusar) return;
    if (!_confirmarRecusa) {
      setState(() => _confirmarRecusa = true);
      _janelaRecusa?.cancel();
      _janelaRecusa = Timer(kTvdeRecusaJanelaConfirmar, () {
        if (mounted) setState(() => _confirmarRecusa = false);
      });
      return;
    }
    _janelaRecusa?.cancel();
    _confirmarRecusa = false;
    // [Recusar não fecha · 03/10 · corrida 540b738a] O cartão ficava no ecrã
    // à espera da rede e o motorista tocou 6 vezes. Some JÁ, com estado
    // próprio; a recusa segue em fundo (o host limpa a oferta mesmo se falhar).
    setState(() => _recusada = true);
    unawaited(widget.onReject());
  }

  /// Recusa confirmada: o cartão já não se desenha (não depende do store).
  bool _recusada = false;

  /// [É dele · 04/10] Só fica a true depois de se saber que a corrida NÃO é
  /// deste motorista — é o que deixa o aviso aparecer.
  bool _perdida = false;

  /// [Cartão preso · 06/10] O cartão já se despediu: não volta a desenhar-se,
  /// mesmo que quem o pôs no ecrã não o tire (era o host congelado).
  bool _fechada = false;

  /// [Cartão preso · 06/10] Desde quando está com o prazo a 0 E "a aceitar".
  DateTime? _penduradoDesde;
  DateTime? _ultimaPergunta;
  bool _perguntaEmCurso = false;

  bool get _aAceitar => _respondendo || widget.aAceitar;

  void _agendarFecho() {
    if (_expirouAvisado) return;
    _expirouAvisado = true;
    widget.onExpired?.call();
    final pergunta = widget.eMinha;
    if (pergunta == null) {
      _perdida = true;
      _armarFecho();
      return;
    }
    unawaited(_confirmarDono(pergunta));
  }

  void _armarFecho() {
    _fecho?.cancel();
    _fecho = Timer(widget.tempoAteFechar, _fecharJa);
  }

  /// Despede-se: avisa quem o mostrou (o store limpa a oferta) e deixa de se
  /// desenhar por conta própria.
  void _fecharJa() {
    if (!mounted || _fechada) return;
    widget.onExpiredDismiss();
    setState(() => _fechada = true);
  }

  /// [Cartão preso · 06/10 · corrida 3835a143] Prazo a 0 e "a aceitar" há
  /// [kTvdeAceitePenduradoPergunta] — o aceite já devia ter respondido.
  /// Pergunta-se ao servidor de quem é a corrida (de 4 em 4 s):
  ///  - é dele → fecha em silêncio (o store relê: a corrida entra como activa);
  ///  - ainda não é → continua à espera, porque o aceite pode estar a chegar;
  ///  - passados [kTvdeAceitePenduradoDesiste] sem ser dele → o aviso de que
  ///    foi para outro e fecha. Nunca fica preso com "0s".
  void _vigiarAceitePendurado() {
    if (_fechada || _perdida || _recusada || !_expirada || !_aAceitar) {
      _penduradoDesde = null;
      return;
    }
    final desde = _penduradoDesde ??= _now;
    if (_perguntaEmCurso ||
        _now.difference(desde) < kTvdeAceitePenduradoPergunta) {
      return;
    }
    final ultima = _ultimaPergunta;
    if (ultima != null &&
        _now.difference(ultima) < kTvdeAceitePenduradoPergunta) {
      return;
    }
    unawaited(_perguntarDonoPendurado());
  }

  Future<void> _perguntarDonoPendurado() async {
    _perguntaEmCurso = true;
    _ultimaPergunta = _now;
    final id = widget.offer.id;
    var minha = false;
    final pergunta = widget.eMinha;
    if (pergunta != null) {
      try {
        minha = await pergunta().timeout(kTvdeAceitePenduradoPergunta);
      } catch (_) {/* sem resposta: ainda não se sabe */}
    }
    _perguntaEmCurso = false;
    if (!mounted || widget.offer.id != id || _fechada || _perdida) return;
    if (minha) {
      _fecharJa();
      return;
    }
    final desde = _penduradoDesde;
    if (desde != null &&
        _now.difference(desde) >= kTvdeAceitePenduradoDesiste) {
      if (!_expirouAvisado) {
        _expirouAvisado = true;
        widget.onExpired?.call();
      }
      setState(() => _perdida = true);
      _armarFecho();
    }
  }

  /// [É dele · 04/10 · corrida 8c7f5ca6] O prazo passou. Antes de dizer "foi
  /// para outro motorista", confirma-se de quem é: se é dele, sai em silêncio.
  Future<void> _confirmarDono(Future<bool> Function() pergunta) async {
    final id = widget.offer.id;
    var minha = false;
    try {
      minha = await pergunta().timeout(const Duration(seconds: 4));
    } catch (_) {/* sem resposta: vale o aviso */}
    if (!mounted || widget.offer.id != id) return;
    if (minha) {
      _fecharJa();
      return;
    }
    setState(() => _perdida = true);
    _armarFecho();
  }

  @override
  Widget build(BuildContext context) {
    if (_recusada || _fechada) return const SizedBox.shrink();
    // [É dele · 04/10 · corrida 8c7f5ca6] Com o aceite a caminho do servidor
    // o prazo não conta: aceitou a 2 s do fim, o relógio passou antes de a
    // resposta chegar e o cartão dizia "foi para outro motorista" por cima da
    // corrida que era dele. Espera-se pela resposta, com o indicador — mas só
    // até a rede de segurança decidir ([_vigiarAceitePendurado]).
    final aAceitar = _aAceitar;
    if (_expirada && (!aAceitar || _perdida)) {
      if (!aAceitar) _agendarFecho();
      // A confirmar de quem é (ou é dele e vai fechar): nada no ecrã.
      if (!_perdida) return const SizedBox.shrink();
      return const OfertaExpiradaNotice(
        texto: 'Esta corrida já foi para outro motorista.',
      );
    }

    final offer = widget.offer;
    final current = widget.current;
    // Regra de ouro do motorista: o número GRANDE é o que ele GANHA.
    final net = (offer.netDriverEarnCents / 100).toStringAsFixed(2);
    final s = _segundosRestantes;

    String linhaRecolha;
    if (current != null) {
      final ligacaoKm = Geolocator.distanceBetween(current.destLat,
              current.destLng, offer.originLat, offer.originLng) /
          1000;
      linhaRecolha = 'Recolha a ${ligacaoKm.toStringAsFixed(1)} km de onde '
          'vais largar · ${offer.originLabel ?? 'Recolha'}';
    } else {
      linhaRecolha = 'Recolha: ${offer.originLabel ?? 'Recolha'}';
    }

    return Container(
      key: const Key('tvde_oferta_sobreposta'),
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryDeep,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 14),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(current != null ? Icons.queue : Icons.local_taxi,
                  color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  current != null
                      ? 'Nova corrida — depois desta corrida'
                      : 'Nova corrida — agora',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800),
                ),
              ),
              Text('${s}s',
                  key: const Key('tvde_oferta_contagem'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('€$net',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.0,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  'o teu ganho · ${offer.estDistanceKm.toStringAsFixed(1)} km',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // O badge de cobrança ("COBRAR EM DINHEIRO: ~€5,00") na sua própria
          // linha: ao lado do ganho comia-lhe o texto (emulador, 21/09).
          Align(
            alignment: Alignment.centerLeft,
            child: TvdePayBadge(ride: offer, dense: true),
          ),
          if (offer.isCounterRide) ...[
            const SizedBox(height: 4),
            const Align(
                alignment: Alignment.centerLeft,
                child: TvdeCounterRideBadge(dense: true)),
          ],
          const SizedBox(height: 6),
          Text(
            linhaRecolha,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '→ ${offer.destLabel ?? 'Destino'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('tvde_oferta_recusar'),
                  onPressed: aAceitar ? null : _tapRecusar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: _confirmarRecusa
                            ? Colors.white
                            : Colors.white54,
                        width: _confirmarRecusa ? 2 : 1),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                      _confirmarRecusa ? 'Confirmar recusa' : 'Recusar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: FilledButton(
                  key: const Key('tvde_oferta_aceitar'),
                  onPressed: aAceitar ? null : _tapAceitar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: aAceitar
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Aceitar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A oferta de RESERVA por cima de qualquer ecrã. Reusa o cartão já provado
/// (`TvdeReservationOfferCard`) enquanto a oferta vive; passado o prazo,
/// diz que a reserva já foi para outro motorista e fecha-se sozinha.
///
/// [A11 · 22/09] Com [compacto] a true (corrida activa aberta) começa como
/// uma faixa de UMA linha — "Reserva para aceitar · hora · ganho · contagem"
/// com "Ver" e "Recusar" — para não tapar os comandos da corrida durante os
/// 5 minutos da oferta. "Ver" abre o cartão inteiro (Aceitar reserva), que
/// se volta a minimizar. A expiração comporta-se igual nos dois modos.
class TvdeReservationOverlayCard extends StatefulWidget {
  const TvdeReservationOverlayCard({
    super.key,
    required this.ride,
    required this.onAccept,
    required this.onReject,
    required this.onExpiredDismiss,
    this.onExpired,
    this.agora,
    this.tempoAteFechar = const Duration(seconds: 5),
    this.compacto = false,
    this.aAceitar = false,
    this.eMinha,
  });

  /// [É dele · 04/10] Como no cartão da imediata: aceite a decorrer → espera;
  /// prazo passado → [eMinha] confirma primeiro que a reserva não é dele.
  final bool aAceitar;
  final Future<bool> Function()? eMinha;

  final TvdeRide ride;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onExpiredDismiss;
  final VoidCallback? onExpired;
  final DateTime Function()? agora;
  final Duration tempoAteFechar;

  /// Começa minimizada (faixa de uma linha) em vez do cartão inteiro.
  final bool compacto;

  @override
  State<TvdeReservationOverlayCard> createState() =>
      _TvdeReservationOverlayCardState();
}

class _TvdeReservationOverlayCardState
    extends State<TvdeReservationOverlayCard> {
  Timer? _ticker;
  Timer? _fecho;
  bool _expirouAvisado = false;

  /// [A11] Só conta em modo compacto: o motorista carregou em "Ver".
  bool _expandido = false;

  /// Guarda LOCAL do "Recusar" da faixa compacta (PADRAO_BORA 3.13): nunca o
  /// `busy` global do store. Destrava-se sozinha ao fim de uns segundos —
  /// `onReject` é fire-and-forget, não há Future para esperar.
  bool _recusando = false;
  Timer? _timeoutRecusa;

  DateTime get _now => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TvdeReservationOverlayCard old) {
    super.didUpdateWidget(old);
    if (old.ride.id != widget.ride.id) {
      _fecho?.cancel();
      _expirouAvisado = false;
      _perdida = false;
      _expandido = false;
      _timeoutRecusa?.cancel();
      _recusando = false;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _fecho?.cancel();
    _timeoutRecusa?.cancel();
    super.dispose();
  }

  bool get _expirada {
    final fim = widget.ride.reservationOfferExpiresAt;
    return fim != null && !fim.isAfter(_now);
  }

  /// Segundos que faltam para a oferta expirar (0 se já passou).
  int get _segundosRestantes {
    final fim = widget.ride.reservationOfferExpiresAt;
    if (fim == null) return 0;
    final s = fim.difference(_now).inSeconds;
    return s > 0 ? s : 0;
  }

  void _recusarCompacto() {
    if (_recusando) return;
    setState(() => _recusando = true);
    _timeoutRecusa?.cancel();
    _timeoutRecusa = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _recusando = false);
    });
    widget.onReject();
  }

  /// [É dele · 04/10] Só a true depois de se saber que a reserva NÃO é dele.
  bool _perdida = false;

  void _armarFecho() {
    _fecho = Timer(widget.tempoAteFechar, () {
      if (mounted) widget.onExpiredDismiss();
    });
  }

  /// [É dele · 04/10] Prazo passado: confirma o dono antes do aviso. Se a
  /// reserva é dele (aceitou por outro caminho), sai em silêncio.
  Future<void> _confirmarDono(Future<bool> Function() pergunta) async {
    final id = widget.ride.id;
    var minha = false;
    try {
      minha = await pergunta().timeout(const Duration(seconds: 4));
    } catch (_) {/* sem resposta: vale o aviso */}
    if (!mounted || widget.ride.id != id) return;
    if (minha) {
      widget.onExpiredDismiss();
      return;
    }
    setState(() => _perdida = true);
    _armarFecho();
  }

  @override
  Widget build(BuildContext context) {
    if (_expirada && !widget.aAceitar) {
      if (!_expirouAvisado) {
        _expirouAvisado = true;
        widget.onExpired?.call();
        final pergunta = widget.eMinha;
        if (pergunta == null) {
          _perdida = true;
          _armarFecho();
        } else {
          unawaited(_confirmarDono(pergunta));
        }
      }
      // A confirmar de quem é (ou é dele e vai fechar): nada no ecrã.
      if (!_perdida) return const SizedBox.shrink();
      return const OfertaExpiradaNotice(
        texto: 'Esta reserva já foi para outro motorista.',
      );
    }
    if (widget.compacto && !_expandido) {
      return _ReservaCompacta(
        ride: widget.ride,
        segundosRestantes: _segundosRestantes,
        recusando: _recusando,
        onVer: () => setState(() => _expandido = true),
        onRecusar: _recusarCompacto,
      );
    }
    return TvdeReservationOfferCard(
      key: const Key('tvde_reserva_sobreposta'),
      ride: widget.ride,
      onAccept: widget.onAccept,
      onReject: widget.onReject,
      onMinimize:
          widget.compacto ? () => setState(() => _expandido = false) : null,
    );
  }
}

/// [A11 · 22/09] A reserva em UMA faixa (≈56 px), para não tapar a corrida
/// activa: ícone · "Reserva para aceitar" / "hora · ganho · contagem" ·
/// "Ver" · "Recusar". A contagem vem do prazo em cada rebuild, como no
/// cartão inteiro; o ganho é o do MOTORISTA (regra de ouro).
class _ReservaCompacta extends StatelessWidget {
  const _ReservaCompacta({
    required this.ride,
    required this.segundosRestantes,
    required this.recusando,
    required this.onVer,
    required this.onRecusar,
  });

  final TvdeRide ride;
  final int segundosRestantes;
  final bool recusando;
  final VoidCallback onVer;
  final VoidCallback onRecusar;

  @override
  Widget build(BuildContext context) {
    final d = ride.scheduledAt?.toLocal();
    final hora = d == null
        ? 'hora a confirmar'
        : '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
    final ganho = ((ride.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    final mm = (segundosRestantes ~/ 60).toString().padLeft(2, '0');
    final ss = (segundosRestantes % 60).toString().padLeft(2, '0');

    return Container(
      key: const Key('tvde_reserva_compacta'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary, width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reserva para aceitar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 1),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$hora · €$ganho · '),
                    TextSpan(
                      text: '$mm:$ss',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                  key: const Key('tvde_reserva_compacta_detalhe'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            key: const Key('tvde_reserva_ver'),
            onPressed: onVer,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Ver'),
          ),
          const SizedBox(width: 2),
          TextButton(
            key: const Key('tvde_reserva_recusar_compacto'),
            onPressed: recusando ? null : onRecusar,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
  }
}

/// O aviso honesto de oferta expirada. Fica uns segundos e sai.
class OfertaExpiradaNotice extends StatelessWidget {
  const OfertaExpiradaNotice({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('tvde_oferta_expirada'),
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.textSubtle.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_off_outlined, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
