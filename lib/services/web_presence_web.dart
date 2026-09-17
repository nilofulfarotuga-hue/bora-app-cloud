// lib/services/web_presence_web.dart — implementação para o NAVEGADOR.
//
// dart:html / dart:js: é o que o resto da app já usa na web
// (place_autocomplete_service_web.dart, directions_service_web.dart).
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

import 'web_presence.dart';

WebPresence createWebPresenceImpl() => _BrowserPresence();

// Wake Lock API (navigator.wakeLock.request('screen')) por dart:js_interop
// "unsafe" (getProperty/callMethod): dart:html não a expõe, dart:js_util já
// não existe, e declarar extension types exigiria subir o SDK mínimo do
// pubspec (não se mexe no pubspec).
JSObject? _wakeLockApi() {
  final nav = globalContext.getProperty<JSAny?>('navigator'.toJS);
  if (nav == null || nav.isUndefinedOrNull) return null;
  final wl = (nav as JSObject).getProperty<JSAny?>('wakeLock'.toJS);
  if (wl == null || wl.isUndefinedOrNull) return null;
  return wl as JSObject;
}

class _BrowserPresence implements WebPresence {
  _BrowserPresence() {
    html.document.onVisibilityChange.listen((_) {
      final visible = isVisible;
      for (final l in List.of(_listeners)) {
        try {
          l(visible);
        } catch (e) {
          debugPrint('[WebPresence] visibility listener: $e');
        }
      }
      // O wake lock cai sozinho quando a página deixa de estar visível;
      // ao voltar, volta-se a pedir se alguém o tinha pedido.
      if (visible && _wakeLockWanted) {
        unawaited(requestWakeLock());
      }
    });
  }

  final List<void Function(bool)> _listeners = [];
  JSObject? _wakeLock;
  bool _wakeLockWanted = false;

  String get _ua => html.window.navigator.userAgent.toLowerCase();

  bool get _isIosDevice =>
      _ua.contains('iphone') ||
      _ua.contains('ipad') ||
      _ua.contains('ipod') ||
      // iPadOS 13+ apresenta-se como Mac; distingue-se pelo toque.
      (_ua.contains('macintosh') && (html.window.navigator.maxTouchPoints ?? 0) > 1);

  bool get _isAndroidDevice => _ua.contains('android');

  @override
  String get plataforma {
    if (_isIosDevice) return 'web_ios';
    if (_isAndroidDevice) return 'web_android';
    return 'web_desktop';
  }

  @override
  bool get isWeb => true;

  @override
  bool get isIosBrowser => _isIosDevice && !isStandalone;

  @override
  bool get isAndroidBrowser => _isAndroidDevice && !isStandalone;

  @override
  bool get isStandalone {
    try {
      // iOS Safari: navigator.standalone; resto: display-mode standalone.
      final nav = js.context['navigator'];
      final standalone = nav != null ? nav['standalone'] : null;
      if (standalone == true) return true;
      return html.window.matchMedia('(display-mode: standalone)').matches;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isVisible => html.document.visibilityState == 'visible';

  @override
  Map<String, String>? get firebaseConfig {
    try {
      final cfg = js.context['boraFirebaseConfig'];
      if (cfg == null) return null;
      final out = <String, String>{};
      for (final k in const [
        'apiKey', 'appId', 'messagingSenderId', 'projectId',
        'authDomain', 'storageBucket', 'vapidKey', 'measurementId',
      ]) {
        final v = cfg[k];
        if (v is String && v.isNotEmpty && !v.startsWith('<')) out[k] = v;
      }
      // Sem estes três não há Firebase web possível.
      if (!out.containsKey('apiKey') ||
          !out.containsKey('appId') ||
          !out.containsKey('messagingSenderId')) {
        return null;
      }
      return out;
    } catch (e) {
      debugPrint('[WebPresence] firebaseConfig: $e');
      return null;
    }
  }

  @override
  String? get firebaseVapidKey => firebaseConfig?['vapidKey'];

  @override
  String? get notificationPermission {
    try {
      return html.Notification.permission;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestWakeLock() async {
    _wakeLockWanted = true;
    try {
      final api = _wakeLockApi();
      if (api == null) return false;
      final promise = api.callMethod<JSPromise<JSObject>>('request'.toJS, 'screen'.toJS);
      _wakeLock = await promise.toDart;
      return true;
    } catch (e) {
      // Sem suporte (Firefox, iOS < 16.4) ou página escondida: segue sem.
      debugPrint('[WebPresence] wake lock indisponível: $e');
      return false;
    }
  }

  @override
  Future<void> releaseWakeLock() async {
    _wakeLockWanted = false;
    final lock = _wakeLock;
    _wakeLock = null;
    if (lock == null) return;
    try {
      await lock.callMethod<JSPromise<JSAny?>>('release'.toJS).toDart;
    } catch (_) {}
  }

  @override
  bool get iosBannerDismissed {
    try {
      return html.window.localStorage['bora_ios_banner'] == 'fechado';
    } catch (_) {
      return false;
    }
  }

  @override
  void hideNativeIosBanner({bool remember = false}) {
    try {
      final el = html.document.getElementById('bora-ios');
      if (el != null) el.style.display = 'none';
      if (remember) html.window.localStorage['bora_ios_banner'] = 'fechado';
    } catch (e) {
      debugPrint('[WebPresence] banner iOS: $e');
    }
  }

  @override
  void addVisibilityListener(void Function(bool visible) listener) {
    _listeners.add(listener);
  }

  @override
  void removeVisibilityListener(void Function(bool visible) listener) {
    _listeners.remove(listener);
  }
}
