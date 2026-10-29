import 'package:flutter/foundation.dart';

import '../models/client_address.dart';
import 'client_address_service.dart';

/// Andar, porta ou código da morada de entrega (paridade pequena, 29/10/2026).
///
/// O cliente escreve-o uma vez em "As minhas moradas" e fica guardado em
/// `client_addresses.details`. No pagamento, a morada do carrinho é comparada
/// com as moradas guardadas: se for uma delas e tiver complemento, o texto
/// vai à frente da nota do pedido (ver `NotaDoPedido`).
class ComplementoMorada {
  ComplementoMorada._();

  /// Máximo de caracteres (o servidor também impõe 80).
  static const int maxCaracteres = 80;

  static String _chave(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Complemento da morada [ruaDoCarrinho] entre as moradas [guardadas].
  /// Compara a linha inteira e, em segundo lugar, a linha sem a cidade.
  static String? encontrar(List<ClientAddress> guardadas, String ruaDoCarrinho) {
    final alvo = _chave(ruaDoCarrinho);
    if (alvo.isEmpty) return null;
    for (final a in guardadas) {
      final d = (a.details ?? '').trim();
      if (d.isEmpty) continue;
      final candidata = _chave(a.address);
      if (candidata == alvo) return d;
      final comCidade = _chave('${a.address}, ${a.city ?? ''}');
      if (comCidade == alvo) return d;
    }
    return null;
  }

  /// Vai ao servidor buscar as moradas e devolve o complemento (ou null).
  /// Nunca lança: sem rede, o pedido segue sem a linha.
  static Future<String?> paraMorada(String ruaDoCarrinho) async {
    try {
      final lista = await ClientAddressService.instance.list();
      return encontrar(lista, ruaDoCarrinho);
    } catch (e) {
      debugPrint('[ComplementoMorada] $e');
      return null;
    }
  }

  /// Texto limpo para gravar: sem espaços a mais e no máximo 80 caracteres.
  /// Vazio → null (apaga o complemento).
  static String? normalizar(String? bruto) {
    final t = (bruto ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return null;
    return t.length <= maxCaracteres ? t : t.substring(0, maxCaracteres);
  }
}
