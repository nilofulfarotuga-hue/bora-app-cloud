import 'dart:async';

/// [16/11/2026 servidor-nao-travar] Religação do tempo real com espera
/// crescente e uma de cada vez.
///
/// O canal geral dos pedidos (OrderStore) religava-se 5 s depois de CADA erro
/// e sem fechar o canal que tinha falhado. Com o servidor carregado o tempo
/// real devolvia "Too many channels" → mais erros → mais canais → cada canal
/// relia a lista de pedidos ao religar. Na app da Isabel isso chegou a 13 904
/// leituras em 10 min e travou o servidor inteiro.
///
/// Regras: só há uma religação agendada de cada vez (erros seguidos juntam-se
/// à que já está marcada) e cada falha seguida dobra a espera (5, 10, 20, 40,
/// 60 s no máximo). Volta aos 5 s assim que chegam dados ([correuBem]).
class ReligarComEspera {
  ReligarComEspera({
    this.inicial = const Duration(seconds: 5),
    this.maximo = const Duration(seconds: 60),
  });

  final Duration inicial;
  final Duration maximo;

  Timer? _timer;
  int _falhas = 0;

  bool get agendada => _timer?.isActive ?? false;
  int get falhasSeguidas => _falhas;

  Duration get proximaEspera {
    final passos = _falhas > 10 ? 10 : _falhas;
    final ms = inicial.inMilliseconds * (1 << passos);
    return ms >= maximo.inMilliseconds ? maximo : Duration(milliseconds: ms);
  }

  /// Marca a religação. Devolve `false` (e não marca nada) se já houver uma
  /// marcada — vários erros do mesmo canal dão uma só religação.
  bool agendar(void Function() religar) {
    if (agendada) return false;
    final espera = proximaEspera;
    _falhas++;
    _timer = Timer(espera, () {
      _timer = null;
      religar();
    });
    return true;
  }

  /// Chegaram dados: a próxima falha volta a esperar só [inicial].
  void correuBem() => _falhas = 0;

  /// Desmarca a religação pendente (logout, troca para os canais do
  /// estafeta, dispose).
  void cancelar() {
    _timer?.cancel();
    _timer = null;
  }
}
