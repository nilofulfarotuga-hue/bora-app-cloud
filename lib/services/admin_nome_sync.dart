import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// manha-15-11 bloco B1: depois de o painel mudar o nome de um cliente
/// (editar contacto ou aprovar um ACCOUNT_UPDATE), copia-o para o login
/// (`user_metadata.bora_name`), que é o nome que a app e a lista de clientes
/// mostram. Antes só `public.users.name` mudava e a app ficava com o antigo.
///
/// Passa [userId] (editar contacto) ou [actionId] (pedido do suporte
/// aprovado; o servidor descobre o cliente). Devolve true quando o nome do
/// login ficou igual ao da base.
Future<bool> sincronizarNomeNoLogin({String? userId, String? actionId}) async {
  try {
    final res = await Supabase.instance.client.functions.invoke(
      'admin-sync-user-name',
      body: {
        if (userId != null) 'user_id': userId,
        if (actionId != null) 'action_id': actionId,
      },
    );
    final m = res.data;
    return m is Map && m['ok'] == true;
  } catch (e) {
    debugPrint('[admin] sincronizarNomeNoLogin($userId/$actionId) falhou: $e');
    return false;
  }
}
