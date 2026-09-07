import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regista de que plataforma a conta está a usar a app: `android`, `ios` ou `web`.
///
/// Serve o painel de gestão: sem isto não há forma de saber de onde vêm os
/// pedidos, e o iPhone vai passar a ser uma origem nova que interessa medir
/// desde o primeiro dia.
///
/// Escreve só em `users.platform`. Não toca na criação do pedido, que é zona
/// protegida — quem preenche `orders.platform` é um gatilho na base de dados,
/// que lê daqui. Assim esta camada nunca pode alterar um pedido.
class PlatformTagService {
  PlatformTagService._();

  static String get plataformaActual {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        // macOS, Windows, Linux: só existem em desenvolvimento. Não se inventa
        // um valor novo — a coluna tem uma restrição de três valores.
        return 'web';
    }
  }

  /// Fire-and-forget: nunca bloqueia o arranque e nunca deixa passar exceção.
  /// Se falhar, a app segue exactamente como antes — isto é telemetria, não
  /// funcionalidade.
  static Future<void> registar() async {
    try {
      final cliente = Supabase.instance.client;
      final uid = cliente.auth.currentUser?.id;
      if (uid == null) return;
      await cliente
          .from('users')
          .update({'platform': plataformaActual}).eq('id', uid);
    } catch (e) {
      debugPrint('[PlatformTagService] não registou a plataforma: $e');
    }
  }
}
