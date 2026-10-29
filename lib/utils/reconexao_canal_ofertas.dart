/// Regra de reconexão do canal realtime `driver-offer:{driverId}` do estafeta.
///
/// Cicatriz (auditoria no emulador, 29/10/2026): o reconnect da CAMADA 4 chamava
/// `removeChannel` ao canal antigo; esse fecho disparava o estado `closed` no
/// callback de subscribe, que voltava a agendar um reconnect, que voltava a
/// fechar… um ciclo de 3 em 3 s enquanto o estafeta estava Online.
///
/// Regra: só se reagenda quando a falha vem do canal ATUAL e o fecho NÃO foi
/// pedido por nós. Esta classe é pura (sem Supabase) para o ciclo ser provado
/// em teste de unidade.
class ReconexaoCanalOfertas {
  bool _fechoPedidoPorMim = false;
  Object? _canalAtual;

  /// Quantas vezes se decidiu reagendar (só para prova/diagnóstico).
  int reagendamentos = 0;

  /// Quantos estados de falha foram ignorados por serem de um fecho nosso ou
  /// de um canal que já não é o atual (só para prova/diagnóstico).
  int ignorados = 0;

  bool get fechoPedidoPorMim => _fechoPedidoPorMim;

  /// Chamar logo depois de `subscribe`: este passa a ser o canal atual.
  void canalLigado(Object canal) {
    _canalAtual = canal;
  }

  /// Chamar ANTES de `removeChannel`/`unsubscribe` pedidos por nós.
  void vouFechar() {
    _fechoPedidoPorMim = true;
  }

  /// Chamar DEPOIS de o fecho pedido por nós terminar (mesmo com erro).
  void fechoConcluido() {
    _fechoPedidoPorMim = false;
    _canalAtual = null;
  }

  /// Decide se um estado de falha (`closed`, `channelError`, `timedOut`) do
  /// [canal] deve agendar uma reconexão. Devolve `false` para estados que não
  /// são de falha, para fechos pedidos por nós e para canais que já não são o
  /// atual (callbacks atrasados do canal antigo).
  bool deveReagendar({required Object canal, required bool estadoDeFalha}) {
    if (!estadoDeFalha) return false;
    if (_fechoPedidoPorMim || !identical(canal, _canalAtual)) {
      ignorados++;
      return false;
    }
    reagendamentos++;
    return true;
  }
}
