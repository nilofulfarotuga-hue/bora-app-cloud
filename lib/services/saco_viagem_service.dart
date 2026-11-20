// Saco para viagem — restaurante NÃO-parceiro (20/11/2026).
//
// Pedido do Danilo: no McDonald's, Burger King e KFC o estafeta compra ao
// balcão e o cliente nunca pede o saco; o estafeta esquecia-se de pedir o saco
// para viagem e pagava-o do bolso. Agora a lista de compras mostra no topo
// "SACO PARA VIAGEM — pede 1 saco ao balcão" e o "Confirmar compra" fica
// bloqueado ("Falta marcar o saco") até ele carregar em "Comprei o saco".
//
// A marca fica:
//   1. no telemóvel (SharedPreferences), na hora do toque, e
//   2. no servidor (`estafeta_saco_viagem`, mesma tabela da compra guardada,
//      `order_purchase_drafts`), para não se perder se outro pedido trocar o
//      ecrã. O servidor recusa fechar a compra sem ela
//      (trg_exige_saco_viagem_ao_fechar_compra → SACO_VIAGEM_POR_MARCAR).
//
// NÃO mexe em dinheiro: o cliente já paga o saco (0,30 €) no checkout e o
// reembolso ao estafeta é o valor do talão, que inclui o saco do balcão.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order_model.dart';

/// O pedido pede saco para viagem: restaurante não-parceiro com saco.
bool precisaSacoViagem(OrderModel o) =>
    o.serviceType == OrderServiceType.restaurant &&
    !o.isPartnerStore &&
    o.bagCount > 0;

/// Texto da linha grande do topo: "pede 1 saco ao balcão".
String textoPedirSaco(int sacos) {
  final n = sacos < 1 ? 1 : sacos;
  return 'Pede $n ${n == 1 ? 'saco' : 'sacos'} ao balcão';
}

/// Resposta do servidor (null = sem rede ou função por publicar).
@immutable
class EstadoSacoServidor {
  const EstadoSacoServidor({
    required this.obrigatorio,
    required this.marcado,
    this.marcadoEm,
    this.servidorSemFuncao = false,
  });

  final bool obrigatorio;
  final bool marcado;
  final DateTime? marcadoEm;

  /// A função ainda não está publicada no servidor (app nova antes da
  /// migração): o servidor também não exige o saco, por isso a app não
  /// pode prender o estafeta — vale a marca do telemóvel.
  final bool servidorSemFuncao;

  static EstadoSacoServidor? deResposta(Object? res) {
    if (res is! Map || res['ok'] != true) return null;
    return EstadoSacoServidor(
      obrigatorio: res['obrigatorio'] == true,
      marcado: res['marcado'] == true,
      marcadoEm: DateTime.tryParse('${res['marcado_em'] ?? ''}'),
    );
  }
}

class SacoViagemService {
  SacoViagemService._();

  static const String rpc = 'estafeta_saco_viagem';
  static const String _prefixo = 'bora.saco_viagem.v1.';
  static const Duration _limiteRede = Duration(seconds: 8);

  /// Só para testes: troca a chamada ao servidor.
  @visibleForTesting
  static Future<Object?> Function(Map<String, dynamic> params)? rpcParaTeste;

  /// O que este telemóvel sabe (true = marcado; null = nunca tocou).
  static Future<bool?> lerLocal(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_prefixo$orderId');
    } catch (_) {
      return null;
    }
  }

  static Future<void> gravarLocal(String orderId, bool marcado) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_prefixo$orderId', marcado);
    } catch (e) {
      debugPrint('[SacoViagem] gravar no telemóvel $orderId: $e');
    }
  }

  static Future<void> esquecerLocal(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefixo$orderId');
    } catch (_) {}
  }

  /// [comprado] null = só regista que a app pediu o saco (ao abrir a lista);
  /// true = "Comprei o saco"; false = desfazer. Nunca lança.
  static Future<EstadoSacoServidor?> enviar(String orderId, {bool? comprado}) async {
    final params = <String, dynamic>{
      'p_order_id': orderId,
      'p_comprado': comprado,
    };
    try {
      final fn = rpcParaTeste;
      final res = fn != null
          ? await fn(params)
          : await Supabase.instance.client
              .rpc(rpc, params: params)
              .timeout(_limiteRede);
      final estado = EstadoSacoServidor.deResposta(res);
      if (estado == null) debugPrint('[SacoViagem] servidor recusou $orderId: $res');
      return estado;
    } catch (e) {
      debugPrint('[SacoViagem] envio $orderId: $e');
      if (eFuncaoEmFalta(e.toString())) {
        return EstadoSacoServidor(
          obrigatorio: true,
          marcado: comprado == true,
          servidorSemFuncao: true,
        );
      }
      return null;
    }
  }

  /// PostgREST sem a função (PGRST202) — não é falta de rede.
  @visibleForTesting
  static bool eFuncaoEmFalta(String erro) =>
      erro.contains('PGRST202') ||
      erro.contains('Could not find the function') ||
      (erro.contains('estafeta_saco_viagem') && erro.contains('does not exist'));
}
