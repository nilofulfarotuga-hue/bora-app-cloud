// lib/services/fcm_token_helper.dart
//
// [Paridade 3 plataformas, 2026-09-21] O token FCM no iPhone.
//
// Porque existe: a 21/09 havia 450 aparelhos registados para avisos
// (client/driver/partner/provider/admin_push_tokens) e ZERO eram iPhone, com a
// app na App Store desde 12/09. No iOS o `getToken()` só responde depois de a
// Apple entregar o token APNs ao aparelho; chamado antes, lança
// `[firebase_messaging/apns-token-not-set]` (3× em debug_crash_logs, último
// 20/09 20:46) e cada chamador desistia ao fim de 13–22 s de tentativas.
//
// A ordem certa no iPhone é: pedir permissão → esperar pelo token APNs →
// só então pedir o token FCM. Android e web NÃO passam por aqui: o ramo iOS
// só entra com `!kIsWeb && Platform.isIOS`; nas outras plataformas isto é o
// `getToken()` de sempre, byte-a-byte.
//
// Nota: o registo em APNs propriamente dito é feito pelo plugin
// firebase_messaging ≥ 16.7.0 (o 15.x nunca o fazia numa app com UIScene —
// ver pubspec.yaml). Este helper só garante a ORDEM do lado Dart.

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../utils/io_compat.dart' show Platform;

class FcmTokenHelper {
  FcmTokenHelper._();

  /// iPhone/iPad com a app nativa (não o Safari).
  static bool get isIosNativo {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Espera até `getAPNSToken()` devolver algo — a Apple entrega-o segundos
  /// depois de `registerForRemoteNotifications`. Devolve o token APNs, ou
  /// null se [maxEspera] esgotar. Nunca lança.
  static Future<String?> esperarApns(
    FirebaseMessaging messaging, {
    Duration maxEspera = const Duration(seconds: 60),
  }) async {
    final fim = DateTime.now().add(maxEspera);
    var espera = const Duration(milliseconds: 500);
    while (true) {
      try {
        final t = await messaging.getAPNSToken();
        if (t != null && t.isNotEmpty) return t;
      } catch (e) {
        debugPrint('[FcmTokenHelper] getAPNSToken: $e');
      }
      if (DateTime.now().isAfter(fim)) return null;
      await Future<void>.delayed(espera);
      if (espera < const Duration(seconds: 5)) espera *= 2;
    }
  }

  /// `getToken()` seguro nas três plataformas. No iOS espera primeiro pelo
  /// APNs (até [maxEsperaApns]); sem APNs devolve null em vez de lançar.
  /// Nas outras plataformas é o `getToken()` de sempre (com a chave VAPID na
  /// web). Erros do próprio `getToken()` continuam a subir, como antes, para
  /// os chamadores manterem a sua lógica de retry.
  static Future<String?> getToken(
    FirebaseMessaging messaging, {
    String? vapidKey,
    Duration maxEsperaApns = const Duration(seconds: 60),
  }) async {
    if (isIosNativo) {
      final apns = await esperarApns(messaging, maxEspera: maxEsperaApns);
      if (apns == null) {
        debugPrint('[FcmTokenHelper] iOS: sem token APNs ao fim de '
            '${maxEsperaApns.inSeconds}s — sem token FCM nesta tentativa');
        return null;
      }
      return messaging.getToken();
    }
    return messaging.getToken(vapidKey: vapidKey);
  }
}
