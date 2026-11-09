// PESQUISA QUE APRENDE (09/11/2026, missão m11 — adendo 2, parte A).
//
// Ordem do Danilo: "os clientes estão a reclamar muito que não acham os
// produtos". Duas coisas:
//  1. cada pesquisa sem nenhum produto fica registada (RPC
//     `pesquisa_registar_sem_resultado`) — o painel "Pesquisas sem resultado"
//     mostra os termos mais procurados por loja;
//  2. se, a seguir, o cliente põe um produto no carrinho daquela loja, a
//     escolha fica guardada (RPC `pesquisa_aprender_escolha`). Três pessoas
//     diferentes com a mesma escolha → o servidor cria o sinónimo sozinho.
//
// Nunca bloqueia nada: tudo vai em segundo plano e qualquer erro (sem rede,
// servidor ainda sem a migração) é engolido.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PesquisaRpc = Future<void> Function(String funcao, Map<String, dynamic> params);

class PesquisaAprendizagem {
  PesquisaAprendizagem({
    PesquisaRpc? rpc,
    DateTime Function()? agora,
    this.espera = const Duration(milliseconds: 2500),
    this.janela = const Duration(minutes: 15),
  })  : _rpc = rpc,
        _agora = agora ?? DateTime.now;

  static final PesquisaAprendizagem instance = PesquisaAprendizagem();

  /// Quanto tempo o cliente fica parado no "sem resultado" até contar.
  final Duration espera;

  /// Depois de uma pesquisa sem resultado, quanto tempo um produto posto no
  /// carrinho ainda conta como "o que ele procurava".
  final Duration janela;

  final PesquisaRpc? _rpc;
  final DateTime Function() _agora;

  Timer? _timer;
  ({String termo, String? loja, String origem})? _pendente;
  final Set<String> _enviados = {};

  ({String termo, String? loja, DateTime quando})? _ultima;
  Set<String>? _carrinho;

  /// A última pesquisa sem resultado ainda "viva" (para testes e para o ecrã).
  String? get ultimoTermoSemResultado => _ultima?.termo;

  /// A pesquisa deu 0 produtos: guarda para aprender e agenda o registo.
  void semResultado(String termo, {String? restaurantId, String origem = 'loja'}) {
    final t = termo.trim();
    if (t.length < 3) return;
    _ultima = (termo: t, loja: restaurantId, quando: _agora());
    _timer?.cancel();
    _pendente = (termo: t, loja: restaurantId, origem: origem);
    _timer = Timer(espera, _enviarPendente);
  }

  /// A pesquisa voltou a dar produtos (ou o texto mudou): não regista.
  void comResultado() {
    _timer?.cancel();
    _pendente = null;
  }

  /// O cliente saiu do ecrã: o que estava parado vai agora.
  void sairDoEcra() {
    _timer?.cancel();
    if (_pendente != null) _enviarPendente();
  }

  void _enviarPendente() {
    final p = _pendente;
    _pendente = null;
    if (p == null) return;
    final chave = '${p.loja ?? '-'}|${p.termo.toLowerCase()}';
    if (!_enviados.add(chave)) return;
    unawaited(_chamar('pesquisa_registar_sem_resultado', {
      'p_termo': p.termo,
      'p_restaurant_id': p.loja,
      'p_origem': p.origem,
    }));
  }

  /// O carrinho mudou. [loja] é a loja do carrinho (um carrinho = uma loja).
  /// Devolve o id do produto aprendido (ou null) — útil nos testes.
  String? carrinhoMudou(Iterable<String> produtos, String? loja) {
    final agora = produtos.toSet();
    final antes = _carrinho;
    _carrinho = agora;
    if (antes == null) return null; // primeira leitura: nada é "novo"
    final novos = agora.difference(antes);
    final u = _ultima;
    if (novos.isEmpty || u == null || loja == null) return null;
    if (_agora().difference(u.quando) > janela) {
      _ultima = null;
      return null;
    }
    // pesquisa dentro de uma loja: só conta um produto dessa loja;
    // pesquisa na lupa da home (loja nula): conta a loja onde ele comprou.
    if (u.loja != null && u.loja != loja) return null;
    final produto = novos.first;
    _ultima = null;
    unawaited(_chamar('pesquisa_aprender_escolha', {
      'p_termo': u.termo,
      'p_restaurant_id': loja,
      'p_product_id': produto,
    }));
    return produto;
  }

  Future<void> _chamar(String funcao, Map<String, dynamic> params) async {
    try {
      final f = _rpc;
      if (f != null) {
        await f(funcao, params);
      } else {
        await Supabase.instance.client.rpc(funcao, params: params);
      }
    } catch (e) {
      debugPrint('[PesquisaAprendizagem] $funcao falhou: $e');
    }
  }

  @visibleForTesting
  void limpar() {
    _timer?.cancel();
    _pendente = null;
    _enviados.clear();
    _ultima = null;
    _carrinho = null;
  }
}
