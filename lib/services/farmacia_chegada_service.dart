// Produto que só chega mais tarde à farmácia (missão farmacias-loja-2026-11-14, bloco 3).
// Fala só com a tabela `pedido_chegada_tardia` (leitura, pela RLS) e com as RPCs
// farmacia_chegada_marcar / farmacia_chegada_responder / farmacia_chegada_anular.
// O dinheiro não passa por aqui: "tirar" usa a edição de pedido que já existe e
// "cancelar" usa o cancelamento sem custo que já existe (gatilho do servidor).
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/farmacia_chegada.dart';

/// Tipo do aviso ao cliente (notify-client) — o toque abre o pedido.
const String kTipoFarmaciaChegada = 'farmacia_chegada';

/// Erro com a mensagem já em português para mostrar.
class FarmaciaChegadaErro implements Exception {
  FarmaciaChegadaErro(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}

class FarmaciaChegadaService {
  FarmaciaChegadaService._();
  static final FarmaciaChegadaService instance = FarmaciaChegadaService._();

  static const String tabela = 'pedido_chegada_tardia';

  SupabaseClient get _sb => Supabase.instance.client;

  /// A mensagem do servidor vem como "CODIGO: texto legível". Mostra-se só o texto.
  static String mensagemDe(Object e) {
    var m = e is PostgrestException ? e.message : e.toString();
    final i = m.indexOf(':');
    if (i > 0 && i < 40 && m.substring(0, i).toUpperCase() == m.substring(0, i)) {
      m = m.substring(i + 1).trim();
    }
    if (m.isEmpty) return 'Não foi possível concluir. Tente outra vez.';
    return m;
  }

  Future<Map<String, dynamic>> _rpc(String nome, Map<String, dynamic> params) async {
    try {
      final r = await _sb.rpc(nome, params: params);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    } catch (e) {
      throw FarmaciaChegadaErro(mensagemDe(e));
    }
  }

  /// As horas marcadas de um pedido, em tempo real (cliente do pedido ou dono da loja).
  Stream<List<FarmaciaChegada>> doPedido(String orderId) {
    return _sb
        .from(tabela)
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .map((linhas) => linhas.map(FarmaciaChegada.fromMap).toList());
  }

  /// Farmácia: "chega às [chegaAs]". [linhaIdx] null = o pedido todo. Se o pedido ainda
  /// não estava aceite, o servidor aceita-o pelo caminho de sempre.
  Future<void> marcar({
    required String orderId,
    required DateTime chegaAs,
    int? linhaIdx,
  }) =>
      _rpc('farmacia_chegada_marcar', {
        'p_order_id': orderId,
        'p_chega_as': chegaAs.toUtc().toIso8601String(),
        'p_linha_idx': linhaIdx,
      });

  /// Cliente: esperar, tirar o produto ou cancelar sem custo.
  Future<void> responder(String id, EscolhaChegada escolha) =>
      _rpc('farmacia_chegada_responder', {'p_id': id, 'p_escolha': escolha.db});

  /// Farmácia: anular a hora marcada (o pedido volta ao horário de antes).
  Future<void> anular(String id) => _rpc('farmacia_chegada_anular', {'p_id': id});
}
