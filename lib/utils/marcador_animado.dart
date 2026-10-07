/// [Rastreio em tempo real · 07/10/2026] Um marcador que desliza — o relógio
/// à volta do [InterpoladorDePosicao]. Só `dart:async`, sem Flutter, para ser
/// testável e igual nos quatro mapas (carro no cliente TVDE, estafeta no
/// rastreio da entrega, pontinho azul do cliente nos dois mapas do condutor).
library;

import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'rastreio_interpolacao.dart';

class MarcadorAnimado {
  MarcadorAnimado({InterpoladorDePosicao? interpolador, this.onFrame})
      : interp = interpolador ?? InterpoladorDePosicao();

  final InterpoladorDePosicao interp;

  /// Chamado em cada fotograma (e ao assentar). O ecrã repinta aqui.
  void Function()? onFrame;

  /// Onde desenhar agora.
  LatLng? posicao;

  /// Para onde apontar agora (graus, 0 = norte). `null` = sem rumo ainda.
  double? rumo;

  /// Hora (do servidor) da última amostra aceite.
  DateTime? ultimaAmostraEm;

  /// Hora LOCAL em que a última amostra foi aceite — serve para expirar.
  DateTime? recebidaEm;

  Timer? _timer;

  /// Dá uma amostra ao marcador. `false` = ignorada (velha ou repetida).
  bool aceitar(
    AmostraPosicao amostra, {
    List<LatLng> rota = const [],
    int? intervaloEsperadoMs,
    bool animar = true,
  }) {
    final plano = interp.aceitar(
      amostra,
      rota: rota,
      intervaloEsperadoMs: intervaloEsperadoMs,
      animar: animar,
    );
    if (plano == null) return false;
    ultimaAmostraEm = amostra.em;
    recebidaEm = DateTime.now();
    _timer?.cancel();
    _timer = null;
    if (plano.imediato) {
      posicao = plano.pontos.last;
      rumo = plano.rumo ?? rumo;
      onFrame?.call();
      return true;
    }
    final n = plano.pontos.length;
    final periodoMs = (plano.duracao.inMilliseconds / n).round().clamp(30, 250);
    var i = 0;
    _timer = Timer.periodic(Duration(milliseconds: periodoMs), (t) {
      if (i >= n) {
        t.cancel();
        return;
      }
      posicao = plano.pontos[i];
      rumo = plano.rumoPorPasso[i] ?? rumo;
      interp.mostrar(posicao!);
      i++;
      if (i >= n) t.cancel();
      onFrame?.call();
    });
    return true;
  }

  /// Pára o deslizar onde está (sinal velho: um carro a deslizar com o GPS
  /// morto é uma mentira em movimento). A posição fica.
  void pararAnimacao() {
    _timer?.cancel();
    _timer = null;
  }

  /// Sem amostra nova há mais do que [validade].
  bool expirado(Duration validade) {
    final r = recebidaEm;
    return r == null || DateTime.now().difference(r) > validade;
  }

  /// Esquece a posição (outro condutor, linha apagada).
  void limpar() {
    _timer?.cancel();
    _timer = null;
    posicao = null;
    rumo = null;
    ultimaAmostraEm = null;
    recebidaEm = null;
    interp.limpar();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    onFrame = null;
  }
}
