import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';
import '../models/order_service_type.dart';
import 'definicoes_publicas.dart';
import 'fatura_nif_service.dart' show ChamadaRpc;

/// O que o estafeta faz se faltar um produto (adendo 5, item 7, 29/10/2026).
///
/// Na Uber Eats, na Glovo e na iFood isto chama-se "replacement preference":
/// o cliente escolhe ANTES de pagar. Aqui são três opções, uma por pedido.
/// O código (`codigo`) é o que fica em `orders.substitution_preference`.
enum SubstituicaoEscolha {
  /// Trocar por um produto parecido.
  trocar('trocar'),

  /// Tirar do pedido (não se paga). O valor volta a quem pagou.
  tirarDevolver('tirar_devolver'),

  /// O estafeta fala com o cliente no chat, com foto, antes de decidir.
  ligar('ligar');

  const SubstituicaoEscolha(this.codigo);

  /// Valor guardado no servidor (`trocar`, `tirar_devolver`, `ligar`).
  final String codigo;

  /// `trocar` → [trocar]. Código desconhecido ou vazio devolve `null`.
  static SubstituicaoEscolha? deCodigo(Object? codigo) {
    final c = codigo?.toString().replaceAll('"', '').trim();
    if (c == null || c.isEmpty) return null;
    for (final e in SubstituicaoEscolha.values) {
      if (e.codigo == c) return e;
    }
    return null;
  }

  /// Título da opção no checkout do cliente (PT-PT).
  String get titulo {
    switch (this) {
      case SubstituicaoEscolha.trocar:
        return 'Trocar por um parecido'.tr;
      case SubstituicaoEscolha.tirarDevolver:
        return 'Tirar e devolver o valor'.tr;
      case SubstituicaoEscolha.ligar:
        return 'Falar comigo no chat'.tr;
    }
  }

  /// A frase de baixo do título, no checkout do cliente.
  String get explicacao {
    switch (this) {
      case SubstituicaoEscolha.trocar:
        return 'O estafeta escolhe o produto mais parecido.'.tr;
      case SubstituicaoEscolha.tirarDevolver:
        return 'O produto sai do pedido e não pagas por ele.'.tr;
      case SubstituicaoEscolha.ligar:
        return 'O estafeta escreve-te no chat, com foto, antes de decidir.'.tr;
    }
  }

  /// A linha que o estafeta vê no topo da lista de compras (PT-PT).
  ///
  /// Cada frase é UM só literal: a varredura do `l10n_cobertura_test` lê o
  /// literal que antecede o `.tr`, e literais colados dariam chaves diferentes.
  String get fraseEstafeta {
    switch (this) {
      case SubstituicaoEscolha.trocar:
        return 'Se faltar um produto, o cliente quer: trocar por um parecido.'
            .tr;
      case SubstituicaoEscolha.tirarDevolver:
        return 'Se faltar um produto, o cliente quer: tirar do pedido (marca "não há").'
            .tr;
      case SubstituicaoEscolha.ligar:
        return 'Se faltar um produto, o cliente quer: falar contigo no chat, com foto.'
            .tr;
    }
  }

  /// O texto do painel admin (PT-BR).
  String get textoAdmin {
    switch (this) {
      case SubstituicaoEscolha.trocar:
        return 'Trocar por um parecido';
      case SubstituicaoEscolha.tirarDevolver:
        return 'Tirar do pedido e devolver o valor';
      case SubstituicaoEscolha.ligar:
        return 'Falar com o cliente no chat (com foto)';
    }
  }
}

/// A pergunta aparece neste pedido? Só em mercados que não são parceiros
/// (compra feita pelo estafeta, com talão) e em Favores com compra.
bool substituicaoAplica({
  required OrderServiceType serviceType,
  required bool lojaParceira,
  required bool favorComLista,
}) {
  switch (serviceType) {
    case OrderServiceType.storeShopping:
      return !lojaParceira;
    case OrderServiceType.errand:
      return favorComLista;
    case OrderServiceType.restaurant:
    case OrderServiceType.carryGroceries:
    case OrderServiceType.sendPackage:
    case OrderServiceType.takeaway:
      return false;
  }
}

Future<dynamic> _rpcSupabase(String funcao, Map<String, dynamic> parametros) =>
    Supabase.instance.client.rpc(funcao, params: parametros);

Future<bool> _interruptorSupabase() async {
  final lido = await lerDefinicoesPublicas(
      const <String>[SubstituicaoService.chaveInterruptor]);
  final v = lido[SubstituicaoService.chaveInterruptor];
  if (v is bool) return v;
  if (v is String) return v.replaceAll('"', '').trim().toLowerCase() == 'true';
  return false;
}

/// SUBSTITUIÇÃO ESCOLHIDA ANTES DE PAGAR — o lado do cliente.
///
/// * O interruptor `platform_settings.substitution_choice_enabled` nasce
///   DESLIGADO. Se a leitura falhar, vale desligado (nada muda).
/// * A escolha NUNCA trava nem atrasa o pedido: só se chama o servidor depois
///   de o pedido ter id real (`create_order` não guarda este campo), em segundo
///   plano, com 3 tentativas. Se falhar, o pedido segue sem escolha e o
///   estafeta pergunta pelo chat, como hoje.
/// * Funções do servidor (`SECURITY DEFINER`, só `authenticated`):
///   `client_set_substitution_preference(p_order_id, p_pref)` e
///   `client_get_substitution_preference()` (a última escolha do cliente).
class SubstituicaoService {
  SubstituicaoService({
    ChamadaRpc? rpc,
    Future<bool> Function()? lerInterruptor,
    this.espera = const Duration(milliseconds: 700),
    this.tentativas = 3,
  })  : _rpc = rpc ?? _rpcSupabase,
        _lerInterruptor = lerInterruptor ?? _interruptorSupabase;

  /// A instância da app.
  static final SubstituicaoService instance = SubstituicaoService();

  /// A chave em `platform_settings` (boolean, desligada por defeito).
  static const String chaveInterruptor = 'substitution_choice_enabled';

  final ChamadaRpc _rpc;
  final Future<bool> Function() _lerInterruptor;
  final Duration espera;
  final int tentativas;

  bool? _ligada;
  DateTime? _lidaEm;

  /// O interruptor está ligado? Cache de 2 minutos. Nunca lança; sem resposta
  /// vale desligado.
  Future<bool> ligada() async {
    final lidaEm = _lidaEm;
    if (_ligada != null &&
        lidaEm != null &&
        DateTime.now().difference(lidaEm).inMinutes < 2) {
      return _ligada!;
    }
    try {
      _ligada = await _lerInterruptor();
      _lidaEm = DateTime.now();
    } catch (e) {
      debugPrint('[Substituicao] interruptor não lido: $e');
      return false;
    }
    return _ligada!;
  }

  /// A última escolha deste cliente (pré-marca o seletor), ou `null`.
  /// Nunca lança.
  Future<SubstituicaoEscolha?> escolhaGuardada() async {
    try {
      return SubstituicaoEscolha.deCodigo(
          await _rpc('client_get_substitution_preference', const {}));
    } catch (e) {
      debugPrint('[Substituicao] escolha guardada não lida: $e');
      return null;
    }
  }

  // ── A escolha que está no ecrã de pagamento ──────────────────────────────

  SubstituicaoEscolha? _pendente;
  Object? _dono;

  /// A escolha do ecrã de pagamento que ainda não foi para um pedido.
  SubstituicaoEscolha? get pendente => _pendente;

  /// O seletor [dono] regista a escolha atual (`null` = sem escolha).
  void definirPendente(Object dono, SubstituicaoEscolha? escolha) {
    _dono = dono;
    _pendente = escolha;
  }

  /// O seletor [dono] saiu do ecrã: só limpa se a escolha ainda for dele.
  void largarPendente(Object dono) {
    if (!identical(_dono, dono)) return;
    _dono = null;
    _pendente = null;
  }

  /// Chamar logo que o pedido tem id real. Leva a escolha pendente (uma vez),
  /// não espera e nunca lança. Sem escolha pendente não faz nada.
  void gravarPendenteEmSegundoPlano(String? orderId) {
    final escolha = _pendente;
    if (orderId == null || escolha == null) return;
    _pendente = null;
    unawaited(gravar(orderId, escolha));
  }

  /// Guarda a escolha no pedido (3 tentativas). `true` = ficou guardada.
  /// Nunca lança.
  Future<bool> gravar(String orderId, SubstituicaoEscolha escolha) async {
    for (var i = 1; i <= tentativas; i++) {
      try {
        await _rpc('client_set_substitution_preference', {
          'p_order_id': orderId,
          'p_pref': escolha.codigo,
        });
        return true;
      } catch (e) {
        debugPrint('[Substituicao] tentativa $i/$tentativas falhou: $e');
        if (_recusadoDeVez(e)) return false;
        if (i < tentativas) await Future<void>.delayed(espera * i);
      }
    }
    return false;
  }

  /// O servidor disse "não" (pedido já saiu, interruptor desligado…): repetir
  /// não adianta.
  static bool _recusadoDeVez(Object e) {
    final t = e.toString();
    return t.contains('ORDER_ALREADY_PICKED_UP') ||
        t.contains('SUBSTITUICAO_DESLIGADA') ||
        t.contains('SUBSTITUICAO_NAO_APLICA') ||
        t.contains('NOT_ORDER_OWNER') ||
        t.contains('ORDER_NOT_FOUND') ||
        t.contains('SUBSTITUICAO_INVALIDA');
  }
}
