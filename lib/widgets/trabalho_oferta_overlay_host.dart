import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../services/incoming_job_alert.dart';
import '../services/notification_service.dart';
import '../services/oferta_trabalho_aviso.dart';
import '../services/roles_service.dart';
import '../services/sound_service.dart';
import '../stores/cleaner_store.dart';
import '../stores/washer_store.dart';
import '../utils/hora_lisboa.dart';

/// [09/10/2026 · Mayra] A oferta de LIMPEZA e de LAVAGEM por cima de qualquer
/// ecrã — igual à do estafeta/TVDE (que não se mexe; só se copia o padrão).
///
/// **A cicatriz.** A 09/10 a Mayra (só faz limpeza) aceitou uma limpeza, mas
/// ficou no ecrã do estafeta e o aviso não tocou a sério: a oferta só existia
/// num cartão dentro do ecrã da limpeza, sem som, e o realtime só ligava
/// depois de esse ecrã ser aberto.
///
/// **Como passou a ser.** Este widget envolve o `Navigator` inteiro (vive no
/// `MaterialApp.builder`, ver `main.dart`):
///  - mal há sessão, carrega o perfil de limpeza e de lavagem (o realtime de
///    ofertas liga-se para quem tem o papel aprovado); ao sair, esquece tudo;
///  - com uma oferta viva desenha-a em ECRÃ INTEIRO, com o ganho em grande, a
///    hora (de Lisboa), a contagem do prazo e Aceitar/Recusar;
///  - com a app à frente toca o som em ciclo até responder (a notificação
///    insistente fica para quando a app está em segundo plano);
///  - quando uma oferta deixa de estar viva (aceite noutro sítio, passada a
///    outra pessoa, expirada) cala o aviso dela.
class TrabalhoOfertaOverlayHost extends StatefulWidget {
  const TrabalhoOfertaOverlayHost({
    super.key,
    required this.child,
    this.ligarSessao = true,
    this.agora,
    this.tocarSom,
    this.pararSom,
    this.debugEstafetaOcupado = false,
  });

  final Widget child;

  /// SÓ PARA TESTES: finge que a pessoa está a trabalhar como estafeta
  /// (em produção pergunta-se ao servidor, `my_trabalho_pendente`).
  @visibleForTesting
  final bool debugEstafetaOcupado;

  /// Ouvir a sessão do Supabase para carregar/esquecer os stores. Só os
  /// testes desligam (não há Supabase inicializado).
  final bool ligarSessao;

  /// Relógio injectável (testes).
  final DateTime Function()? agora;

  /// Som injectável (testes). Por omissão usa o [SoundService].
  final Future<void> Function()? tocarSom;
  final Future<void> Function()? pararSom;

  @override
  State<TrabalhoOfertaOverlayHost> createState() =>
      _TrabalhoOfertaOverlayHostState();
}

/// O que o cartão está a mostrar: uma oferta de limpeza ou de lavagem.
class OfertaDeTrabalhoVista {
  const OfertaDeTrabalhoVista({
    required this.categoria,
    required this.bookingId,
    required this.ganhoCents,
    required this.marcadaPara,
    required this.morada,
    required this.expiraEm,
  });

  final String categoria; // 'limpeza' | 'lavagem'
  final String bookingId;
  final int ganhoCents;
  final DateTime marcadaPara;
  final String morada;
  final DateTime? expiraEm;
}

/// A primeira oferta viva para mostrar (a limpeza primeiro), sem as que já
/// foram respondidas neste aparelho. Função pura → testável.
OfertaDeTrabalhoVista? ofertaDeTrabalhoParaMostrar({
  required CleanerStore limpeza,
  required WasherStore lavagem,
  required Set<String> respondidas,
  required DateTime agora,
}) {
  for (final b in limpeza.ofertasVivas(agora: agora)) {
    if (respondidas.contains(b.id)) continue;
    return OfertaDeTrabalhoVista(
      categoria: 'limpeza',
      bookingId: b.id,
      ganhoCents: b.cleanerEarningsCents,
      marcadaPara: b.scheduledAt,
      morada: b.addressCity,
      expiraEm: b.offerExpiresAt,
    );
  }
  for (final b in lavagem.ofertasVivas(agora: agora)) {
    if (respondidas.contains(b.id)) continue;
    return OfertaDeTrabalhoVista(
      categoria: 'lavagem',
      bookingId: b.id,
      ganhoCents: b.washerEarningsCents,
      marcadaPara: b.scheduledAt,
      morada: b.addressLine,
      expiraEm: b.offerExpiresAt,
    );
  }
  return null;
}

class _TrabalhoOfertaOverlayHostState extends State<TrabalhoOfertaOverlayHost>
    with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;
  String? _uidCarregado;
  Timer? _ticker;
  int _segundosDesdeReleitura = 0;
  SoundService? _soundService;
  bool _somATocar = false;

  /// Ofertas respondidas aqui (o cartão sai JÁ, sem esperar pela rede).
  final Set<String> _respondidas = <String>{};

  /// Ofertas que já se mostraram — para calar o aviso quando deixam de viver.
  final Set<String> _mostradas = <String>{};

  /// [Revisão 09/10] Por oferta: a pessoa está a trabalhar como estafeta
  /// (ligada, com entrega em curso)? Aí a oferta entra COMPACTA e sem som em
  /// ciclo — nunca tapa o cartão da oferta de entrega nem o mapa da entrega.
  final Map<String, bool> _estafetaOcupado = <String, bool>{};

  DateTime get _now => (widget.agora ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.ligarSessao) _ligarSessao();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _ticker?.cancel();
    unawaited(_pararSom());
    _soundService?.dispose();
    super.dispose();
  }

  void _ligarSessao() {
    try {
      final auth = Supabase.instance.client.auth;
      _authSub = auth.onAuthStateChange.listen((estado) {
        final uid = estado.session?.user.id;
        if (uid == null) {
          _esquecer();
        } else if (uid != _uidCarregado) {
          _carregar(uid);
        }
      });
      final uid = auth.currentUser?.id;
      if (uid != null) _carregar(uid);
    } catch (e) {
      debugPrint('[BORA-TRABALHO] sem sessão para ouvir: $e');
    }
  }

  /// Liga os stores logo a seguir ao login: o realtime das ofertas passa a
  /// existir sem a pessoa ter de abrir o ecrã da limpeza/lavagem.
  void _carregar(String uid) {
    _uidCarregado = uid;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<CleanerStore>().loadProfile());
      unawaited(context.read<WasherStore>().loadProfile());
    });
  }

  void _esquecer() {
    if (_uidCarregado == null) return;
    _uidCarregado = null;
    // Cala JÁ o que estava a tocar desta conta, antes de esquecer.
    for (final id in _mostradas) {
      unawaited(IncomingJobAlert.dismiss(id));
    }
    unawaited(_pararSom());
    _respondidas.clear();
    _mostradas.clear();
    _estafetaOcupado.clear();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CleanerStore>().reset();
      context.read<WasherStore>().reset();
    });
  }

  /// Relê as ofertas dos dois papéis (barato: só quem tem perfil).
  void _reler() {
    if (!mounted) return;
    final limpeza = context.read<CleanerStore>();
    final lavagem = context.read<WasherStore>();
    // Perfil por carregar (ex.: o arranque falhou sem rede): carrega-o — o
    // loadProfile já lê as ofertas de quem está aprovado.
    if (limpeza.profile == null) {
      if (_uidCarregado != null) {
        unawaited(limpeza.loadProfile());
      }
    } else if (limpeza.profile!.isApproved) {
      unawaited(limpeza.loadWork());
    }
    if (lavagem.profile == null) {
      if (_uidCarregado != null) {
        unawaited(lavagem.loadProfile());
      }
    } else if (lavagem.isApproved) {
      unawaited(lavagem.loadOffers());
    }
  }

  /// Pergunta UMA vez por oferta se a pessoa está a trabalhar como estafeta.
  void _verSeEstafetaOcupado(String bookingId) {
    if (_estafetaOcupado.containsKey(bookingId) || !widget.ligarSessao) return;
    _estafetaOcupado[bookingId] = false;
    unawaited(RolesService.myTrabalhoPendente().then((p) {
      if (!mounted || !p.estafeta) return;
      setState(() => _estafetaOcupado[bookingId] = true);
    }));
  }

  /// Chamado pelo gancho global quando chega um push de oferta com a app aberta.
  void releituraPedida() => _reler();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reler();
    } else {
      // Em segundo plano quem toca é a notificação (o isolate de fundo).
      unawaited(_pararSom());
    }
  }

  Future<void> _tocarSom() async {
    if (_somATocar) return;
    _somATocar = true;
    try {
      if (widget.tocarSom != null) {
        await widget.tocarSom!();
      } else {
        _soundService ??= SoundService();
        await _soundService!.playLoop();
      }
    } catch (e) {
      debugPrint('[BORA-TRABALHO] som não tocou: $e');
    }
  }

  Future<void> _pararSom() async {
    if (!_somATocar) return;
    _somATocar = false;
    try {
      if (widget.pararSom != null) {
        await widget.pararSom!();
      } else {
        await _soundService?.stop();
      }
    } catch (_) {}
  }

  void _armarRelogio(bool comOferta) {
    if (comOferta && _ticker == null) {
      _segundosDesdeReleitura = 0;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // De 20 em 20 s relê: a oferta pode ter passado a outra pessoa sem
        // nenhum evento chegar a este telemóvel.
        if (++_segundosDesdeReleitura >= 20) {
          _segundosDesdeReleitura = 0;
          _reler();
        }
        setState(() {});
      });
    } else if (!comOferta && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _calarOfertasMortas(String? viva) {
    final mortas = _mostradas.where((id) => id != viva).toList();
    for (final id in mortas) {
      _mostradas.remove(id);
      unawaited(IncomingJobAlert.dismiss(id));
    }
  }

  void _snack(String texto, {SnackBarAction? accao}) {
    final ctx = NotificationService.navigatorKey.currentContext ?? context;
    ScaffoldMessenger.maybeOf(ctx)
        ?.showSnackBar(SnackBar(content: Text(texto), action: accao));
  }

  Future<void> _aceitar(OfertaDeTrabalhoVista o) async {
    final limpeza = o.categoria == 'limpeza';
    try {
      if (limpeza) {
        await context.read<CleanerStore>().acceptBooking(o.bookingId);
      } else {
        final ok = await context.read<WasherStore>().accept(o.bookingId);
        if (!ok) throw StateError('washer_accept_falhou');
      }
      if (!mounted) return;
      setState(() => _respondidas.add(o.bookingId));
      _snack(
        limpeza
            ? 'Limpeza aceite — está na tua agenda.'
            : 'Lavagem aceite — está nos teus trabalhos.',
        accao: SnackBarAction(
          label: 'Ver',
          onPressed: () =>
              NotificationService.abrirTrabalho?.call(o.categoria, o.bookingId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // [Revisão 09/10] Falha de REDE: a oferta continua viva — o cartão fica
      // para tentar outra vez. Só sai quando o servidor diz que já não há.
      if (falhaDeRede(e)) {
        _snack('Sem rede — não consegui aceitar. Tenta outra vez.');
        return;
      }
      setState(() => _respondidas.add(o.bookingId));
      _reler();
      _snack(limpeza
          ? 'Esta limpeza já não está disponível.'
          : 'Esta lavagem já não está disponível.');
    }
  }

  Future<void> _recusar(OfertaDeTrabalhoVista o) async {
    // Sai do ecrã JÁ; a recusa segue em fundo (o servidor passa à seguinte).
    setState(() => _respondidas.add(o.bookingId));
    try {
      if (o.categoria == 'limpeza') {
        await context.read<CleanerStore>().rejectBooking(o.bookingId);
      } else {
        await context.read<WasherStore>().reject(o.bookingId);
      }
    } catch (e) {
      debugPrint('[BORA-TRABALHO] recusa falhou (o prazo trata dela): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final limpeza = context.watch<CleanerStore>();
    final lavagem = context.watch<WasherStore>();
    final oferta = ofertaDeTrabalhoParaMostrar(
      limpeza: limpeza,
      lavagem: lavagem,
      respondidas: _respondidas,
      agora: _now,
    );
    // Efeitos (som, relógio, calar avisos) só no fim do frame — nunca setState
    // a meio de um build (cicatriz de 06/10 no cartão TVDE).
    final compacto = oferta != null &&
        (widget.debugEstafetaOcupado ||
            (_estafetaOcupado[oferta.bookingId] ?? false));
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _calarOfertasMortas(oferta?.bookingId);
      if (oferta != null) {
        _mostradas.add(oferta.bookingId);
        _verSeEstafetaOcupado(oferta.bookingId);
      }
      _armarRelogio(oferta != null);
      final aFrente = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      // A trabalhar como estafeta: sem som em ciclo (o som é da oferta de
      // entrega; na web o leitor é partilhado).
      if (oferta != null && aFrente && !compacto) {
        unawaited(_tocarSom());
      } else {
        unawaited(_pararSom());
      }
    });

    final cartao = oferta == null
        ? null
        : TrabalhoOfertaCartao(
            key: ValueKey<String>('trabalho-oferta-${oferta.bookingId}'),
            oferta: oferta,
            agora: _now,
            compacto: compacto,
            onAceitar: () => _aceitar(oferta),
            onRecusar: () => _recusar(oferta),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (cartao != null && !compacto) Positioned.fill(child: cartao),
        // Estafeta a trabalhar: faixa no FUNDO do ecrã, para não tapar o
        // cartão da oferta de entrega (no topo) nem os comandos do mapa.
        if (cartao != null && compacto)
          Positioned(
            left: 12,
            right: 12,
            bottom: MediaQuery.paddingOf(context).bottom + 12,
            child: cartao,
          ),
      ],
    );
  }
}

/// O ecrã inteiro da oferta. Regra de ouro do prestador: o número GRANDE é o
/// que a pessoa GANHA.
class TrabalhoOfertaCartao extends StatefulWidget {
  const TrabalhoOfertaCartao({
    super.key,
    required this.oferta,
    required this.agora,
    required this.onAceitar,
    required this.onRecusar,
    this.compacto = false,
  });

  final OfertaDeTrabalhoVista oferta;
  final DateTime agora;

  /// [Revisão 09/10] A pessoa está a trabalhar como estafeta: faixa compacta
  /// (sem fundo escuro) para não tapar a oferta de entrega nem o mapa.
  final bool compacto;
  final Future<void> Function() onAceitar;
  final Future<void> Function() onRecusar;

  @override
  State<TrabalhoOfertaCartao> createState() => _TrabalhoOfertaCartaoState();
}

class _TrabalhoOfertaCartaoState extends State<TrabalhoOfertaCartao> {
  // Guardas do Recusar, iguais às da oferta TVDE ([Recusa fantasma · 25/09]):
  // no primeiro segundo não recusa (o toque era para o ecrã de baixo) e pede
  // um segundo toque dentro de 3 s.
  bool _podeRecusar = false;
  bool _confirmarRecusa = false;
  bool _aAceitar = false;
  Timer? _guarda;
  Timer? _janela;
  Timer? _destrava;

  @override
  void initState() {
    super.initState();
    _guarda = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _podeRecusar = true);
    });
  }

  @override
  void dispose() {
    _guarda?.cancel();
    _janela?.cancel();
    _destrava?.cancel();
    super.dispose();
  }

  Future<void> _tapAceitar() async {
    if (_aAceitar) return;
    setState(() => _aAceitar = true);
    _destrava?.cancel();
    _destrava = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _aAceitar = false);
    });
    try {
      await widget.onAceitar();
    } finally {
      if (mounted) setState(() => _aAceitar = false);
    }
  }

  void _tapRecusar() {
    if (_aAceitar || !_podeRecusar) return;
    if (!_confirmarRecusa) {
      setState(() => _confirmarRecusa = true);
      _janela?.cancel();
      _janela = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirmarRecusa = false);
      });
      return;
    }
    _janela?.cancel();
    unawaited(widget.onRecusar());
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.oferta;
    final limpeza = o.categoria == 'limpeza';
    final ganho = (o.ganhoCents / 100).toStringAsFixed(2).replaceAll('.', ',');
    final quando = dataHoraLisboa(o.marcadaPara.toUtc().toIso8601String());
    final resto = o.expiraEm?.difference(widget.agora);
    String? contagem;
    if (resto != null) {
      final s = resto.inSeconds < 0 ? 0 : resto.inSeconds;
      final mm = (s ~/ 60).toString().padLeft(2, '0');
      final ss = (s % 60).toString().padLeft(2, '0');
      contagem = '$mm:$ss';
    }

    if (widget.compacto) {
      return Material(
        key: const Key('trabalho_oferta_compacta'),
        color: AppColors.primaryDeep,
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Icon(
                  limpeza
                      ? Icons.cleaning_services_rounded
                      : Icons.local_car_wash_rounded,
                  color: Colors.white,
                  size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${limpeza ? 'Nova limpeza' : 'Nova lavagem'} · €$ganho',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      [quando, if (contagem != null) contagem].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('trabalho_oferta_recusar'),
                onPressed: _aAceitar ? null : _tapRecusar,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: Text(_confirmarRecusa ? 'Confirmar' : 'Recusar'),
              ),
              FilledButton(
                key: const Key('trabalho_oferta_aceitar'),
                onPressed: _aAceitar ? null : _tapAceitar,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: const Text('Aceitar'),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      key: const Key('trabalho_oferta_cartao'),
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryDeep,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 18),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                            limpeza
                                ? Icons.cleaning_services_rounded
                                : Icons.local_car_wash_rounded,
                            color: Colors.white,
                            size: 26),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            limpeza ? 'Nova limpeza' : 'Nova lavagem',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (contagem != null)
                          Text(contagem,
                              key: const Key('trabalho_oferta_contagem'),
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('€$ganho',
                        key: const Key('trabalho_oferta_ganho'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            height: 1.0,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    const Text('o teu ganho',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 14),
                    Row(children: [
                      const Icon(Icons.event, color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(quando,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15.5)),
                      ),
                    ]),
                    if (o.morada.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.place_outlined,
                            color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(o.morada,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15.5)),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('trabalho_oferta_recusar'),
                            onPressed: _aAceitar ? null : _tapRecusar,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 52),
                              side: BorderSide(
                                  color: _confirmarRecusa
                                      ? Colors.white
                                      : Colors.white54,
                                  width: _confirmarRecusa ? 2 : 1),
                            ),
                            child: Text(
                                _confirmarRecusa ? 'Confirmar recusa' : 'Recusar',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            key: const Key('trabalho_oferta_aceitar'),
                            onPressed: _aAceitar ? null : _tapAceitar,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              minimumSize: const Size(0, 52),
                            ),
                            child: _aAceitar
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Aceitar',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chave global para o `main.dart` pedir uma releitura (push com a app aberta).
final GlobalKey<State<TrabalhoOfertaOverlayHost>> trabalhoOfertaHostKey =
    GlobalKey<State<TrabalhoOfertaOverlayHost>>();

/// Pede ao anfitrião que releia as ofertas (gancho do push com a app aberta).
void releituraDasOfertasDeTrabalho() {
  final s = trabalhoOfertaHostKey.currentState;
  if (s is _TrabalhoOfertaOverlayHostState) s.releituraPedida();
}

/// A falha foi de rede (sem resposta do servidor) e não uma recusa dele?
bool falhaDeRede(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection closed') ||
      s.contains('Network is unreachable');
}

/// Aceitar/Recusar carregado na notificação (gancho global do main.dart).
///
/// [Revisão 09/10 · caso Mayra] Com a app FECHADA o gancho corre antes de
/// haver navegador e sessão: cala-se o aviso JÁ e espera-se por eles (o mesmo
/// padrão do Aceitar da oferta TVDE). Se mesmo assim não houver, não se marca
/// nada como respondido — a repetição do minuto seguinte volta a tocar.
Future<void> responderOfertaDeTrabalhoGlobal(
    String categoria, String bookingId, String accao) async {
  if (bookingId.isEmpty) return;
  await IncomingJobAlert.dismiss(bookingId);
  BuildContext? ctx;
  for (var tentativa = 0; tentativa < 10; tentativa++) {
    final c = NotificationService.navigatorKey.currentContext;
    String? uid;
    try {
      uid = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}
    if (c != null && c.mounted && uid != null) {
      ctx = c;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  if (ctx == null || !ctx.mounted) {
    debugPrint('[BORA-TRABALHO] $accao sem navegador/sessão — fica para a '
        'próxima repetição do toque');
    return;
  }
  final limpeza = categoria == 'limpeza';
  final cleaner = ctx.read<CleanerStore>();
  final washer = ctx.read<WasherStore>();
  try {
    if (accao == kTrabalhoRecusarAction) {
      if (limpeza) {
        await cleaner.rejectBooking(bookingId);
      } else {
        await washer.reject(bookingId);
      }
      return;
    }
    // Aceitar: o store pode ainda não ter o perfil (arranque a frio).
    if (limpeza) {
      if (cleaner.profile == null) await cleaner.loadProfile();
      await cleaner.acceptBooking(bookingId);
    } else {
      if (washer.profile == null) await washer.loadProfile();
      final ok = await washer.accept(bookingId);
      if (!ok) throw StateError('washer_accept_falhou');
    }
    NotificationService.abrirTrabalho?.call(categoria, bookingId);
  } catch (e) {
    debugPrint('[BORA-TRABALHO] acção $accao falhou: $e');
    final c2 = NotificationService.navigatorKey.currentContext;
    if (c2 != null && c2.mounted) {
      ScaffoldMessenger.maybeOf(c2)?.showSnackBar(SnackBar(
          content: Text(falhaDeRede(e)
              ? 'Sem rede — não consegui responder. Tenta outra vez.'
              : limpeza
                  ? 'Esta limpeza já não está disponível.'
                  : 'Esta lavagem já não está disponível.')));
    }
  }
}
