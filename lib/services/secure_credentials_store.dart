import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SEC (2026-06-12) — a palavra-passe que o AuthStore usa no auto-login
/// (_initFromPrefs → signInWithPassword) vivia EM CLARO no JSON da conta em
/// SharedPreferences. Este store move esse segredo para flutter_secure_storage
/// (encriptado pelo Android Keystore). O fluxo de restauro é o mesmo — só
/// muda onde o segredo está em repouso. Instalações antigas migram
/// automaticamente no primeiro arranque (campo legado do JSON → secure
/// storage, e o JSON é regravado sem password).
class SecureCredentialsStore {
  SecureCredentialsStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kPrefix = 'bora_secure.password.';
  static const _roles = ['client', 'driver', 'partner'];

  /// Palavra-passe guardada para [role]; '' quando não existe ou em erro.
  static Future<String> read(String role) async {
    try {
      return await _storage.read(key: '$_kPrefix$role') ?? '';
    } catch (e) {
      debugPrint('[SecureCreds] read failed: $e');
      return '';
    }
  }

  static Future<void> write(String role, String password) async {
    // Nunca sobrepor uma password válida com vazio (contas hidratadas por
    // sessão/biometria têm password '' e não devem apagar a guardada).
    if (password.isEmpty) return;
    try {
      await _storage.write(key: '$_kPrefix$role', value: password);
    } catch (e) {
      debugPrint('[SecureCreds] write failed: $e');
    }
  }

  static Future<void> clearAll() async {
    for (final role in _roles) {
      try {
        await _storage.delete(key: '$_kPrefix$role');
      } catch (_) {}
    }
  }
}
