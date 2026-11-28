// CONVITE NAS CATEGORIAS (missão home-categorias-convite-2026-11-27).
//
// Pedido do Danilo (26/11/2026): "efeitozinhos nas categorias, tipo pedindo
// para clicar". Decidido pela Claude.ai (regras do Emil Kowalski, as mesmas do
// site novo): uma onda curta e RARA, sem som.
//
//   · 2,5 s depois de a home aparecer, se ninguém tocou nem deslizou, cada
//     mosaico faz escala 1 → 1,05 → 1 em 460 ms (Cubic 0.77, 0, 0.175, 1).
//     Atraso por mosaico = coluna × 45 ms + linha × 70 ms.
//   · Só UMA repetição, 7 s depois. E acabou nessa visita.
//   · Pára de vez no primeiro toque em qualquer sítio, no primeiro deslizar
//     ou quando a app vai para segundo plano. Não volta a correr no mesmo
//     arranque da app (fica em memória que já correu).
//   · Nunca corre com "reduzir animações"/navegação acessível ligados nem com
//     home_convite_categorias = false no painel.
//
// Desempenho: UM só AnimationController para a grelha inteira; cada mosaico
// lê um Interval dele dentro de um Transform.scale com RepaintBoundary. A
// grelha não se reconstrói durante a onda (só o Transform de cada mosaico).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../services/assistant_service.dart';

/// Envolve a grelha de categorias e dá o relógio da onda aos mosaicos.
class ConviteCategorias extends StatefulWidget {
  const ConviteCategorias({
    super.key,
    required this.colunas,
    required this.total,
    required this.child,
    this.ligado,
  });

  /// Colunas da grelha (4 na home).
  final int colunas;

  /// Número de células da grelha (conta o mosaico do Amigo, que ocupa a
  /// primeira célula mas não entra na onda).
  final int total;

  final Widget child;

  /// Interruptor do painel. Por defeito `AssistantFlags.conviteCategorias`
  /// (platform_settings.home_convite_categorias); trocável nos testes.
  final ValueListenable<bool>? ligado;

  static const Duration esperaInicial = Duration(milliseconds: 2500);
  static const Duration intervaloRepeticao = Duration(seconds: 7);
  static const Duration duracaoMosaico = Duration(milliseconds: 460);
  static const int atrasoColunaMs = 45;
  static const int atrasoLinhaMs = 70;
  static const double escalaMaxima = 1.05;
  static const Curve curva = Cubic(0.77, 0, 0.175, 1);

  /// Já correu (ou foi cancelada) neste arranque da app.
  static bool _jaCorreu = false;

  /// Só para testes: esquece que já correu.
  @visibleForTesting
  static void reporParaTestes() => _jaCorreu = false;

  @override
  State<ConviteCategorias> createState() => _ConviteCategoriasState();
}

class _ConviteCategoriasState extends State<ConviteCategorias>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _relogio;
  final List<Timer> _temporizadores = [];
  bool _parado = false;
  bool _rotaGlobal = false;
  ScrollPosition? _posicao;
  bool _semMovimento = false;

  @override
  void initState() {
    super.initState();
    _relogio = AnimationController(vsync: this, duration: _duracaoTotal);
    if (ConviteCategorias._jaCorreu) {
      _parado = true;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_aoPonteiro);
    _rotaGlobal = true;
    _temporizadores
      ..add(Timer(ConviteCategorias.esperaInicial, _onda))
      ..add(Timer(
          ConviteCategorias.esperaInicial +
              ConviteCategorias.intervaloRepeticao,
          _onda));
  }

  Duration get _duracaoTotal {
    final linhas = (widget.total / widget.colunas).ceil();
    final maxColuna = (widget.total < widget.colunas ? widget.total : widget.colunas) - 1;
    final ms = (maxColuna < 0 ? 0 : maxColuna) * ConviteCategorias.atrasoColunaMs +
        (linhas - 1 < 0 ? 0 : linhas - 1) * ConviteCategorias.atrasoLinhaMs +
        ConviteCategorias.duracaoMosaico.inMilliseconds;
    return Duration(milliseconds: ms);
  }

  @override
  void didUpdateWidget(covariant ConviteCategorias old) {
    super.didUpdateWidget(old);
    if (old.total != widget.total || old.colunas != widget.colunas) {
      _relogio.duration = _duracaoTotal;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // O deslizar da lista da home (a grelha vive dentro dela).
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _posicao) {
      _posicao?.removeListener(_aoDeslizar);
      _posicao = _parado ? null : p;
      _posicao?.addListener(_aoDeslizar);
    }
  }

  void _onda() {
    if (_parado || !mounted) return;
    ConviteCategorias._jaCorreu = true;
    final ligado = (widget.ligado ?? AssistantFlags.conviteCategorias).value;
    if (!ligado || _semMovimento) {
      _parar();
      return;
    }
    _relogio.forward(from: 0);
  }

  void _aoPonteiro(PointerEvent e) {
    if (e is PointerDownEvent ||
        e is PointerScrollEvent ||
        e is PointerPanZoomStartEvent) {
      _parar();
    }
  }

  void _aoDeslizar() => _parar();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _parar();
  }

  void _parar() {
    if (_parado) return;
    _parado = true;
    ConviteCategorias._jaCorreu = true;
    for (final t in _temporizadores) {
      t.cancel();
    }
    _temporizadores.clear();
    if (_relogio.isAnimating || _relogio.value != 0) {
      _relogio
        ..stop()
        ..value = 0;
    }
    _desligarOuvintes();
  }

  void _desligarOuvintes() {
    if (_rotaGlobal) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_aoPonteiro);
      _rotaGlobal = false;
    }
    _posicao?.removeListener(_aoDeslizar);
    _posicao = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    for (final t in _temporizadores) {
      t.cancel();
    }
    _desligarOuvintes();
    _relogio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lido no build (fica a depender do MediaQuery) e usado quando a onda
    // chegar: "reduzir animações" ou leitor de ecrã = sem onda.
    _semMovimento = MediaQuery.maybeDisableAnimationsOf(context) == true ||
        MediaQuery.maybeAccessibleNavigationOf(context) == true;
    return _ConviteEscopo(
      relogio: _relogio,
      colunas: widget.colunas,
      duracaoTotalMs: _duracaoTotal.inMilliseconds,
      child: widget.child,
    );
  }
}

class _ConviteEscopo extends InheritedWidget {
  const _ConviteEscopo({
    required this.relogio,
    required this.colunas,
    required this.duracaoTotalMs,
    required super.child,
  });

  final AnimationController relogio;
  final int colunas;
  final int duracaoTotalMs;

  @override
  bool updateShouldNotify(_ConviteEscopo old) =>
      old.relogio != relogio ||
      old.colunas != colunas ||
      old.duracaoTotalMs != duracaoTotalMs;
}

/// Um mosaico da grelha que entra na onda. `indice` é a posição na grelha
/// (0 = primeira célula), de onde saem a coluna e a linha.
class ConviteMosaico extends StatelessWidget {
  const ConviteMosaico({super.key, required this.indice, required this.child});

  final int indice;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final escopo = context.dependOnInheritedWidgetOfExactType<_ConviteEscopo>();
    if (escopo == null) return child;
    final coluna = indice % escopo.colunas;
    final linha = indice ~/ escopo.colunas;
    final atraso = coluna * ConviteCategorias.atrasoColunaMs +
        linha * ConviteCategorias.atrasoLinhaMs;
    final total = escopo.duracaoTotalMs.toDouble();
    final inicio = (atraso / total).clamp(0.0, 1.0);
    final fim = ((atraso + ConviteCategorias.duracaoMosaico.inMilliseconds) / total)
        .clamp(inicio, 1.0);
    final escala = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: ConviteCategorias.escalaMaxima)
            .chain(CurveTween(curve: ConviteCategorias.curva)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: ConviteCategorias.escalaMaxima, end: 1.0)
            .chain(CurveTween(curve: ConviteCategorias.curva)),
        weight: 50,
      ),
    ]).chain(CurveTween(curve: Interval(inicio, fim)));
    // drive() e não CurvedAnimation: esta acrescenta um ouvinte de estado ao
    // relógio que só sai com dispose() — criada no build, ia-se acumulando.
    final escalaAnimada = escopo.relogio.drive(escala);
    return ScaleTransition(
      key: ValueKey('convite-mosaico-$indice'),
      scale: escalaAnimada,
      child: RepaintBoundary(child: child),
    );
  }
}
