import 'package:shared_preferences/shared_preferences.dart';

/// Destino guardado quando alguém chega de fora — do site, de um QR, de um
/// link partilhado — a uma ficha de loja ou de serviço **sem sessão iniciada**.
///
/// Porque é que isto não pode viver na pilha de navegação: depois do registo,
/// o `WelcomeAddressScreen` faz `popUntil((r) => r.isFirst)` e tudo o que
/// estivesse empilhado desaparece. Se o regresso à ficha dependesse da pilha,
/// a pessoa acabava sempre na home genérica — que é exactamente o que se quer
/// evitar.
///
/// Quem consome é o `ClientMainScreen`, mal a home do cliente aparece.
class DestinoPendente {
  const DestinoPendente({required this.tipo, required this.id});

  /// 'loja' ou 'servico'.
  final String tipo;
  final String id;

  static const String _chave = 'bora_app.destino_pendente';

  static Future<void> guardar(String tipo, String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chave, '$tipo|$id');
  }

  /// Lê **e apaga**: só se volta à ficha uma vez.
  static Future<DestinoPendente?> consumir() async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(_chave);
    if (bruto == null) return null;
    await prefs.remove(_chave);
    final corte = bruto.indexOf('|');
    if (corte <= 0 || corte == bruto.length - 1) return null;
    return DestinoPendente(
      tipo: bruto.substring(0, corte),
      id: bruto.substring(corte + 1),
    );
  }

  static Future<void> limpar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chave);
  }
}
