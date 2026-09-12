import 'package:shared_preferences/shared_preferences.dart';

/// L1 (2026-06-12) — lembra o último email usado POR PAPEL (client/driver/
/// partner) para pré-preencher o campo de email no ecrã de login: o
/// utilizador só digita a palavra-passe.
///
/// Segurança: guarda APENAS o email (identificador público). A palavra-passe
/// NUNCA passa por aqui — autofill (L2) e biometria (L3) tratam disso de
/// forma segura.
class LoginPrefs {
  LoginPrefs._();

  static const _kLastEmailPrefix = 'bora_login.last_email.';

  /// Último email com login bem-sucedido para [role], ou null.
  static Future<String?> lastEmail(String role) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('$_kLastEmailPrefix$role');
    return (value == null || value.isEmpty) ? null : value;
  }

  static Future<void> saveLastEmail(String role, String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kLastEmailPrefix$role', normalized);
  }

  static Future<void> clearLastEmail(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kLastEmailPrefix$role');
  }
}
