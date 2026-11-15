import 'dart:async';

/// Junta chamadas repetidas a um carregamento da rede.
///
/// Missão fechar-app-15-11 (Bloco 2). O estafeta pedia a lista de pedidos em
/// rajada (aviso de pedido, voltar à app e abrir o ecrã chegam no mesmo
/// segundo) e cada pedido trazia a lista inteira. Aqui garante-se que:
///
///  * só há UM carregamento a correr de cada vez;
///  * quem chamar enquanto esse corre fica à espera de UM único carregamento
///    seguinte (todas as chamadas dessa janela recebem o mesmo `Future`), para
///    não perder uma mudança que chegou a meio do primeiro;
///  * com [intervalo] maior que zero, dois carregamentos nunca começam com
///    menos desse tempo entre o fim de um e o princípio do outro.
///
/// Não guarda dados: só decide QUANDO a operação corre.
class CarregamentoUnico {
  CarregamentoUnico({DateTime Function()? agora})
      : _agora = agora ?? DateTime.now;

  final DateTime Function() _agora;

  Future<void>? _emVoo;
  Future<void>? _aEspera;
  DateTime? _ultimoFim;

  /// Há um carregamento a correr neste momento.
  bool get emVoo => _emVoo != null;

  /// Há um carregamento marcado para depois do que está a correr.
  bool get aEspera => _aEspera != null;

  /// Corre [operacao] respeitando as regras da classe. O `Future` devolvido
  /// só completa depois de um carregamento que COMEÇOU a seguir a esta
  /// chamada (ou do que já estava marcado para isso), por isso quem faz
  /// `await` vê sempre dados pedidos depois de ter chamado.
  ///
  /// Erros de [operacao] são engolidos aqui de propósito: quem carrega trata
  /// do próprio erro (regista e mantém a lista antiga) e um erro não pode
  /// deixar o próximo carregamento preso.
  Future<void> correr(
    Future<void> Function() operacao, {
    Duration intervalo = Duration.zero,
  }) {
    final jaAEspera = _aEspera;
    if (jaAEspera != null) return jaAEspera;

    final emVoo = _emVoo;
    if (emVoo == null && _faltaEsperar(intervalo) <= Duration.zero) {
      return _arrancar(operacao);
    }

    // [15/11/2026, revisão] O `Future` devolvido nasce de um `Completer` e fica
    // guardado ANTES de o trabalho começar. Antes era um `late final` lido
    // dentro da própria função: se não houvesse nenhuma espera pelo caminho
    // (o intervalo acabava entre as duas contas), a leitura rebentava, o
    // `Future` ficava falhado em `_aEspera` e nenhum carregamento voltava a
    // correr até reiniciar a app.
    final fim = Completer<void>();
    final marcado = fim.future;
    _aEspera = marcado;
    unawaited(() async {
      try {
        if (emVoo != null) {
          await emVoo;
        }
        final falta = _faltaEsperar(intervalo);
        if (falta > Duration.zero) {
          await Future<void>.delayed(falta);
        }
        if (identical(_aEspera, marcado)) _aEspera = null;
        await _arrancar(operacao);
      } finally {
        // Aconteça o que acontecer, quem espera é solto e a vaga fica livre.
        if (identical(_aEspera, marcado)) _aEspera = null;
        fim.complete();
      }
    }());
    return marcado;
  }

  Duration _faltaEsperar(Duration intervalo) {
    final fim = _ultimoFim;
    if (fim == null || intervalo <= Duration.zero) return Duration.zero;
    final passou = _agora().difference(fim);
    return passou >= intervalo ? Duration.zero : intervalo - passou;
  }

  Future<void> _arrancar(Future<void> Function() operacao) {
    // Mesmo cuidado que em [correr]: o `Future` existe e está guardado antes de
    // a operação começar, para um erro lançado logo à entrada (sem nenhuma
    // espera) não deixar `_emVoo` preso num `Future` falhado.
    final fim = Completer<void>();
    final corrida = fim.future;
    _emVoo = corrida;
    unawaited(() async {
      try {
        await operacao();
      } catch (_) {
        // ver a nota em [correr]
      } finally {
        _ultimoFim = _agora();
        if (identical(_emVoo, corrida)) _emVoo = null;
        fim.complete();
      }
    }());
    return corrida;
  }
}

/// Estados em que um pedido já acabou (não é trabalho em curso do estafeta).
const List<String> estadosFinaisDoPedido = <String>[
  'delivered',
  'cancelled',
  'rejected',
];

/// Tamanho de cada página do histórico de entregas do estafeta.
const int tamanhoPaginaHistoricoEstafeta = 20;

/// Intervalo mínimo entre dois carregamentos de pedidos do estafeta.
const Duration esperaEntreCarregamentosEstafeta = Duration(seconds: 2);

/// Filtro `or` do PostgREST para os pedidos que são do estafeta [uid]:
/// os que lhe estão atribuídos e os que lhe estão a ser oferecidos.
///
/// O `user_id` manda (CLAUDE.md §5): `assigned_driver_id` e
/// `current_driver_offer_id` guardam o `user_id` em texto.
String filtroPedidosDoEstafeta(String uid) =>
    'assigned_driver_id.eq.$uid,current_driver_offer_id.eq.$uid';

/// Lista `(a,b,c)` para o `not.in` do PostgREST.
String listaEstadosFinaisPostgrest() => '(${estadosFinaisDoPedido.join(',')})';

/// Intervalo `[de, ate]` (inclusive, como o `range` do PostgREST) da página
/// [pagina] do histórico (a primeira é a 0).
({int de, int ate}) intervaloDaPaginaHistorico(int pagina) {
  final p = pagina < 0 ? 0 : pagina;
  final de = p * tamanhoPaginaHistoricoEstafeta;
  return (de: de, ate: de + tamanhoPaginaHistoricoEstafeta - 1);
}
