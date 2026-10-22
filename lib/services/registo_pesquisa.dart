import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client_personalization_service.dart';

/// Regista o que o cliente procurou para o painel admin "KPIs de pesquisa"
/// (RPC `client_log_search` → `client_search_history` → `admin_search_kpi`).
///
/// B2 (fechar-pendencias-2026-10-20): a 20/10 a tabela tinha 1 linha — só a
/// lupa única registava, e só quando o cliente tocava num resultado. As
/// pesquisas que não deram nada (as que mais interessam ao painel) e as dos
/// outros ecrãs (restaurantes, lojas, menu, produtos da loja) nunca chegavam.
///
/// Regras:
/// * nunca bloqueia a pesquisa: o envio é `unawaited` e qualquer erro (sem
///   rede, sem sessão → `auth_required`) é engolido aqui;
/// * não regista cada letra: espera [espera] sem o cliente escrever, ou
///   [registarJa] quando ele escolhe um resultado / carrega em pesquisar;
/// * não repete o mesmo texto seguido; ignora menos de 2 letras;
/// * ao sair do ecrã, [dispose] envia o que ficou por enviar.
class RegistoPesquisa {
  RegistoPesquisa({
    this.espera = const Duration(milliseconds: 2500),
    Future<void> Function(String texto)? enviar,
  }) : _enviar = enviar;

  final Duration espera;
  final Future<void> Function(String texto)? _enviar;

  Timer? _timer;
  String? _pendente;
  String? _ultimo;

  /// O cliente escreveu: agenda o registo para depois de [espera] parado.
  void aoEscrever(String texto) {
    _timer?.cancel();
    final t = texto.trim();
    if (t.length < 2) {
      _pendente = null;
      return;
    }
    _pendente = t;
    _timer = Timer(espera, () => registarJa(t));
  }

  /// Regista já (resultado escolhido, tecla "pesquisar", saída do ecrã).
  void registarJa(String texto) {
    _timer?.cancel();
    _pendente = null;
    final t = texto.trim();
    if (t.length < 2) return;
    final chave = t.toLowerCase();
    if (chave == _ultimo) return;
    _ultimo = chave;
    unawaited(_enviarSeguro(t));
  }

  Future<void> _enviarSeguro(String t) async {
    try {
      final enviar = _enviar ?? ClientPersonalizationService.instance.logSearch;
      await enviar(t);
    } catch (e) {
      debugPrint('[RegistoPesquisa] não registou "$t": $e');
    }
  }

  /// Fecho do ecrã: o que estava à espera vai agora.
  void dispose() {
    _timer?.cancel();
    final p = _pendente;
    _pendente = null;
    if (p != null) registarJa(p);
  }
}
