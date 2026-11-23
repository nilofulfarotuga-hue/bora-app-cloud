import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/small_order_fee.dart';

/// EMBALAGEM DA LOJA (23/11/2026, AUTORIZO do Danilo 10:44).
///
/// Numa loja com `restaurants.embalagem_cents` (Boom! Burger), o `bag_fee` do
/// pedido não é o saco de 0,30 €: é a "Embalagem", que vai 100 % para a loja.
/// O pedido não guarda o nome da linha; quem decide é o servidor
/// (`e_embalagem_da_loja(restaurant_id, bag_fee)`, a mesma função do recibo,
/// do extrato e do acerto). Aqui pergunta-se uma vez por loja e valor e
/// guarda-se em memória. Sem resposta (offline, erro) fica "Saco", que é o
/// que as outras lojas mostram — nunca se inventa a embalagem.
class EmbalagemDaLoja {
  EmbalagemDaLoja._();

  static final Map<String, bool> _respostas = {};
  static final Map<String, Future<bool>> _emCurso = {};

  static String _chave(String restaurantId, double bagFee) =>
      '$restaurantId|${(bagFee * 100).round()}';

  /// Já se sabe a resposta? `null` = ainda não.
  static bool? conhecida(String? restaurantId, double bagFee) {
    if (restaurantId == null || bagFee <= 0) return false;
    final r = _respostas[_chave(restaurantId, bagFee)];
    if (r != null) return r;
    // A loja já foi lida no carrinho: o espelho do servidor responde.
    if (SmallOrderFeeService.ehEmbalagemDaLoja(restaurantId, bagFee)) {
      return true;
    }
    return null;
  }

  /// Pergunta ao servidor (uma vez por loja e valor).
  static Future<bool> verificar(String? restaurantId, double bagFee) {
    final ja = conhecida(restaurantId, bagFee);
    if (ja != null) return Future.value(ja);
    final chave = _chave(restaurantId!, bagFee);
    return _emCurso[chave] ??= () async {
      // Deixa o pedido ficar registado como "a caminho" antes de poder falhar
      // (senão o `finally` corria antes e a marca ficava presa).
      await null;
      try {
        final r = await Supabase.instance.client.rpc('e_embalagem_da_loja',
            params: {'p_restaurant_id': restaurantId, 'p_bag_fee': bagFee});
        final sim = r == true;
        _respostas[chave] = sim;
        return sim;
      } catch (e) {
        debugPrint('[EmbalagemDaLoja] falhou a perguntar ao servidor: $e');
        return false;
      } finally {
        _emCurso.remove(chave);
      }
    }();
  }

  /// Só para testes: fixa a resposta para esta loja e valor.
  @visibleForTesting
  static void definirParaTeste(String restaurantId, double bagFee, bool sim) {
    _respostas[_chave(restaurantId, bagFee)] = sim;
  }

  @visibleForTesting
  static void limparParaTeste() {
    _respostas.clear();
    _emCurso.clear();
  }
}

/// Constrói a linha do saco com o nome certo: `embalagem == true` quando o
/// `bag_fee` deste pedido é a embalagem da loja.
class SacoOuEmbalagem extends StatelessWidget {
  const SacoOuEmbalagem({
    super.key,
    required this.restaurantId,
    required this.bagFee,
    required this.builder,
  });

  final String? restaurantId;
  final double bagFee;
  final Widget Function(BuildContext context, bool embalagem) builder;

  @override
  Widget build(BuildContext context) {
    final ja = EmbalagemDaLoja.conhecida(restaurantId, bagFee);
    if (ja != null) return builder(context, ja);
    return FutureBuilder<bool>(
      future: EmbalagemDaLoja.verificar(restaurantId, bagFee),
      builder: (context, snap) => builder(context, snap.data ?? false),
    );
  }
}
