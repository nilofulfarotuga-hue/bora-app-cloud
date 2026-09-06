import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// L3 (2026-06-12) — login com biometria (digital / rosto), estilo apps de
/// banca: após um login com palavra-passe bem-sucedido o utilizador pode
/// ativar "Entrar com biometria"; a sessão Supabase (refresh token) fica em
/// flutter_secure_storage (encriptado pelo Android Keystore) e no próximo
/// login basta a digital/rosto para restaurar a sessão.
///
/// Segurança (obrigatório — prompt L3):
/// - O refresh token vive APENAS em secure storage, NUNCA SharedPreferences.
/// - A palavra-passe nunca passa por este serviço.
/// - logout() explícito do AuthStore chama disableAll().
/// - O Supabase RODA o refresh token a cada refresh — syncRefreshedToken()
///   (chamado por AuthStore._onAuthStateChange) mantém o guardado atual;
///   sem isto o token envelhecia e o login biométrico falhava.
class BiometricAuthService {
  BiometricAuthService._();
  static final BiometricAuthService instance = BiometricAuthService._();

  final LocalAuthentication _localAuth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kTokenPrefix = 'bora_biometric.refresh_token.';
  static const _kEmailPrefix = 'bora_biometric.email.';
  // Flag "já perguntámos uma vez" — não é segredo, fica em SharedPreferences.
  static const _kAskedPrefix = 'bora_biometric.asked.';

  static const roles = ['client', 'driver', 'partner'];

  /// true quando o aparelho tem biometria configurada (digital/rosto).
  /// Aparelho sem biometria → a opção esconde-se em todo o lado (L3.6).
  Future<bool> get isDeviceCapable async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      if (!await _localAuth.canCheckBiometrics) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (e) {
      debugPrint('[Biometric] capability check failed: $e');
      return false;
    }
  }

  Future<bool> isEnabledFor(String role) async {
    try {
      final token = await _storage.read(key: '$_kTokenPrefix$role');
      return token != null && token.isNotEmpty;
    } catch (e) {
      debugPrint('[Biometric] read failed: $e');
      return false;
    }
  }

  /// Pede a digital/rosto ao utilizador. true = autenticado.
  Future<bool> authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      debugPrint('[Biometric] authenticate error: ${e.code}');
      return false;
    } catch (e) {
      debugPrint('[Biometric] authenticate error: $e');
      return false;
    }
  }

  /// Guarda a sessão Supabase ATUAL para login biométrico futuro de [role].
  /// Chamar apenas com sessão ativa (pós-login / toggle no perfil).
  Future<bool> enableForCurrentSession(String role) async {
    final session = Supabase.instance.client.auth.currentSession;
    final refreshToken = session?.refreshToken;
    final email = session?.user.email;
    if (refreshToken == null || refreshToken.isEmpty || email == null) {
      return false;
    }
    try {
      await _storage.write(key: '$_kTokenPrefix$role', value: refreshToken);
      await _storage.write(key: '$_kEmailPrefix$role', value: email);
      return true;
    } catch (e) {
      debugPrint('[Biometric] enable failed: $e');
      return false;
    }
  }

  /// Refresh token guardado para [role] — ler SÓ depois de authenticate().
  Future<String?> readRefreshToken(String role) async {
    try {
      return await _storage.read(key: '$_kTokenPrefix$role');
    } catch (_) {
      return null;
    }
  }

  Future<void> disableFor(String role) async {
    try {
      await _storage.delete(key: '$_kTokenPrefix$role');
      await _storage.delete(key: '$_kEmailPrefix$role');
    } catch (e) {
      debugPrint('[Biometric] disable failed: $e');
    }
  }

  /// Logout explícito ("Sair"/"Terminar sessão") — apaga TODOS os tokens
  /// biométricos, em linha com AuthStore.logout() que limpa as contas dos
  /// 3 papéis. Trocas de papel/modo passam wipeBiometrics:false e preservam.
  Future<void> disableAll() async {
    for (final role in roles) {
      await disableFor(role);
    }
  }

  /// Mantém o token guardado em dia quando o Supabase o roda. Para cada
  /// papel com biometria ativa cujo email coincide com a sessão, regrava.
  Future<void> syncRefreshedToken(Session session) async {
    final email = session.user.email;
    final refreshToken = session.refreshToken;
    if (email == null || refreshToken == null || refreshToken.isEmpty) return;
    for (final role in roles) {
      try {
        final storedEmail = await _storage.read(key: '$_kEmailPrefix$role');
        if (storedEmail != null &&
            storedEmail.toLowerCase() == email.toLowerCase()) {
          await _storage.write(key: '$_kTokenPrefix$role', value: refreshToken);
        }
      } catch (_) {}
    }
  }

  // ── Flag "perguntar uma vez" (L3.2) ───────────────────────────────────

  Future<bool> wasAsked(String role) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_kAskedPrefix$role') ?? false;
  }

  Future<void> markAsked(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kAskedPrefix$role', true);
  }
}
