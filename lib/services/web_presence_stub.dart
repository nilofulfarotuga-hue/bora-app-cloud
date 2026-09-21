// lib/services/web_presence_stub.dart — implementação para Android/iOS/desktop
// (tudo o que NÃO é navegador). Sem wake lock (o foreground service trata),
// sempre visível, sem config Firebase web.
import 'package:flutter/foundation.dart';

import 'web_presence.dart';

WebPresence createWebPresenceImpl() => _NativePresence();

class _NativePresence implements WebPresence {
  @override
  String get plataforma {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios_app';
      case TargetPlatform.android:
        return 'android_app';
      default:
        return 'web_desktop';
    }
  }

  @override
  bool get isWeb => false;
  @override
  bool get isIosBrowser => false;
  @override
  bool get isAndroidBrowser => false;
  @override
  bool get isStandalone => false;
  @override
  bool get isVisible => true;
  @override
  Map<String, String>? get firebaseConfig => null;
  @override
  String? get firebaseVapidKey => null;
  @override
  String? get notificationPermission => null;

  @override
  Future<bool> requestWakeLock() async => false;
  @override
  Future<void> releaseWakeLock() async {}
  @override
  void addVisibilityListener(void Function(bool visible) listener) {}
  @override
  void removeVisibilityListener(void Function(bool visible) listener) {}
  @override
  bool get iosBannerDismissed => false;
  @override
  void hideNativeIosBanner({bool remember = false}) {}
  @override
  String? get userAgent => null;
  @override
  String? get buildCommit => null;
}
