// lib/services/web_presence.dart
//
// [Estafeta web 2026-09-16] Presença do estafeta no NAVEGADOR (PWA).
//
// Porque existe: a 16/09 um estafeta real usava a Bora pelo Safari do iPhone
// e NUNCA ficava disponível para o dispatch — zero chamadas a
// driver_heartbeat/driver_update_location em 24 h, sem token de push, sem
// plataforma registada. No navegador não há foreground service, não há
// wake lock automático, e o ecrã bloqueado suspende tudo.
//
// Esta fachada dá ao resto da app o que é do navegador, com implementação
// condicional (mesmo padrão do place_autocomplete_service):
//   • plataforma        — android_app | ios_app | web_ios | web_android | web_desktop
//                         (vai no heartbeat para o painel admin: "como usa a Bora")
//   • wake lock         — Wake Lock API com fallback silencioso
//   • visibilidade      — para pedir "voltar a ficar online?" quando a página volta
//   • instalado (PWA)   — para explicar "adicionar ao ecrã principal" no iPhone
//   • config Firebase   — lida de web/firebase-config.js (única fonte, partilhada
//                         com o service worker firebase-messaging-sw.js)
import 'web_presence_stub.dart'
    if (dart.library.html) 'web_presence_web.dart' as impl;

abstract class WebPresence {
  static final WebPresence instance = impl.createWebPresenceImpl();

  /// android_app | ios_app | web_ios | web_android | web_desktop
  String get plataforma;

  bool get isWeb;

  /// iPhone/iPad no navegador (não instalada no ecrã principal).
  bool get isIosBrowser;

  /// Android no navegador.
  bool get isAndroidBrowser;

  /// PWA aberta a partir do ecrã principal (display standalone).
  bool get isStandalone;

  /// Página visível agora (document.visibilityState == 'visible').
  bool get isVisible;

  /// Config Firebase da web (apiKey, appId, messagingSenderId, projectId,
  /// authDomain, storageBucket) ou null se não estiver preenchida.
  Map<String, String>? get firebaseConfig;

  /// Chave VAPID (Web Push) do projecto Firebase, ou null.
  String? get firebaseVapidKey;

  /// Permissão de notificações do navegador: 'granted' | 'denied' | 'default' | null.
  String? get notificationPermission;

  /// Mantém o ecrã ligado enquanto o estafeta está online. Devolve true se
  /// conseguiu; false (sem lançar) quando o navegador não suporta.
  Future<bool> requestWakeLock();

  Future<void> releaseWakeLock();

  void addVisibilityListener(void Function(bool visible) listener);

  void removeVisibilityListener(void Function(bool visible) listener);

  /// O index.html tem um banner HTML "Adiciona o Bora ao ecrã principal"
  /// (para todos os papéis). No ecrã do estafeta o cartão Flutter substitui-o
  /// — regra dos gémeos: nunca dois vivos ao mesmo tempo.
  bool get iosBannerDismissed;

  void hideNativeIosBanner({bool remember = false});
}
