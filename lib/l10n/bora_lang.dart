import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idiomas que a app do cliente fala.
///
/// O painel admin continua em PT-BR e as apps de estafeta/parceiro em PT-PT —
/// este alternador só existe no lado do cliente (ordem 2026-09-01).
enum AppLang { pt, en }

/// Estado GLOBAL do idioma do cliente.
///
/// É um [ValueNotifier] estático (não um provider) de propósito: o texto é
/// traduzido pela extensão `String.tr`, que precisa de funcionar em sítios
/// onde não há `BuildContext` — callbacks, `initState`, helpers estáticos e
/// listas `const` de rótulos. Usar `context.watch` num getter partilhado por
/// callbacks já rebentou aqui antes (lição `licao-context-watch-getter`).
class BoraLang {
  BoraLang._();

  /// Chave em SharedPreferences. Segue o prefixo já usado por `SessionStore`.
  static const prefsKey = 'bora_app.language';

  static final ValueNotifier<AppLang> notifier =
      ValueNotifier<AppLang>(AppLang.pt);

  static AppLang get current => notifier.value;
  static bool get isEnglish => notifier.value == AppLang.en;

  /// Lê o idioma guardado no aparelho.
  ///
  /// O padrão é SEMPRE português, independentemente do idioma do telemóvel:
  /// só muda quando a pessoa toca no alternador. Chamar antes de `runApp`.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      notifier.value =
          prefs.getString(prefsKey) == 'en' ? AppLang.en : AppLang.pt;
    } catch (_) {
      // Sem preferências acessíveis a app abre em português — nunca falha aqui.
      notifier.value = AppLang.pt;
    }
  }

  /// Muda o idioma e grava a escolha no aparelho.
  static Future<void> set(AppLang lang) async {
    if (notifier.value == lang) return;
    notifier.value = lang;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, lang == AppLang.en ? 'en' : 'pt');
    } catch (_) {
      // A troca vale para esta sessão mesmo que a gravação falhe.
    }
  }

  static Future<void> toggle() =>
      set(isEnglish ? AppLang.pt : AppLang.en);

  /// Locale para o `MaterialApp` — manda nos widgets do próprio Flutter
  /// (calendário, `showDatePicker`, menu de copiar/colar).
  static Locale get locale =>
      isEnglish ? const Locale('en') : const Locale('pt', 'PT');
}
