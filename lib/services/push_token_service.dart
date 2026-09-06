// 5G — PushTokenService
//
// Multi-device FCM token registration (Decisão A).
// Registers the current FCM token in `client_push_tokens` or
// `driver_push_tokens` via the `register_push_token` RPC (UPSERT).
//
// NÃO substitui `NotificationService` legacy (que escreve em
// `users.fcm_token`, `drivers.fcm_token`, `restaurants.fcm_token`) — corre
// em paralelo durante a transição. Ambos são idempotentes.
//
// Multi-device: re-registo nunca apaga tokens antigos (cada device tem
// linha própria). Edge Fns enviam para TODOS os tokens activos do user.
//
// Decisão C: tokens inválidos (FCM 4xx UNREGISTERED/INVALID_ARGUMENT) são
// marcados active=false após fail_count>=3 via RPC mark_token_failed
// (chamada server-side pelas Edge Fns; nunca pelo cliente).

import 'dart:async';
import '../utils/io_compat.dart' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class PushTokenService {
  PushTokenService._();

  /// Papéis que podem ter aparelho registado para receber avisos.
  ///
  /// Tem de bater certo com o que a RPC `register_push_token` aceita — se
  /// divergirem, um lado rejeita em silêncio e ninguém dá por isso. Foi
  /// exactamente o que aconteceu com o faxineiro durante meses.
  static const Set<String> papeisComPush = {
    'client',
    'driver',
    'partner',
    'cleaner',
    'washer',
  };

  /// Onde é que o token deste papel vai parar.
  ///
  /// Os três papéis antigos têm tabela própria, cada um com o seu nome de
  /// coluna de dono. Os papéis de prestador partilham `provider_push_tokens`,
  /// onde o papel é uma coluna — foi assim de propósito, para o papel seguinte
  /// não obrigar a mais uma tabela, mais políticas e mais um ramo em cada
  /// função que envia. Serve para o registo dizer a verdade.
  static String tabelaDoPapel(String role) =>
      (role == 'cleaner' || role == 'washer')
          ? 'provider_push_tokens (role=$role)'
          : '${role}_push_tokens';

  static StreamSubscription<String>? _refreshSub;
  static bool _registering = false;
  static String? _lastRegisteredToken;
  static String? _lastRegisteredRole;

  /// Todos os papéis já registados nesta sessão. É preciso um conjunto e não
  /// um só: quando o FCM renova o token do aparelho, TODOS os papéis da pessoa
  /// têm de receber o valor novo. Com uma variável única, quem acumulasse
  /// motorista e faxineiro ficava mudo num deles a partir da primeira
  /// renovação — e uma renovação não avisa ninguém.
  static final Set<String> _papeisRegistados = <String>{};

  /// [Serviços 2026-07-28] BUG: o dedup de sessão era só (token, role). Num
  /// device partilhado — logout do parceiro A, login do parceiro B — o token
  /// FCM e o role são os mesmos, o UPSERT era saltado, e o parceiro B nunca
  /// chegava a `partner_push_tokens` (ficava sem pushes de marcação). A chave
  /// de dedup passa a incluir o utilizador autenticado.
  static String? _lastRegisteredUserId;

  /// BUG E (sessão exec 2026-05-12) — Log helper visível em release builds.
  /// debugPrint é stripped em release; usar print() para sair em logcat/Xcode.
  static void _log(String msg) {
    // ignore: avoid_print
    print('[PushTokenService] $msg');
  }

  /// Registers the current device for the given [role]
  /// ('client' | 'driver' | 'partner').
  /// Idempotent: safe to call multiple times. Re-uses the FCM token from
  /// [NotificationService.instance.fcmToken] when available.
  ///
  /// BUG E — retry 3x com backoff (1s, 3s, 9s) quando getToken() retorna null
  /// ou RPC falha por race condition (auth não settled).
  ///
  /// B2 (2026-06-11): 'partner' aceite — o RPC register_push_token sempre
  /// suportou partner_push_tokens (partner_id = auth.uid()), mas este guard
  /// rejeitava o role e a tabela ficava vazia → notify-service-provider
  /// (push de marcação nova à barbearia) não tinha tokens para enviar.
  ///
  /// [2026-08-28] 'cleaner' e 'washer' aceites. Antes desta data este guarda
  /// rejeitava-os e a RPC também — resultado: a limpeza estava no ar e **nunca
  /// conseguiu chamar ninguém**, porque nenhum faxineiro tinha token guardado.
  /// Não havia sequer caminho antigo: ao contrário de `drivers`, as tabelas
  /// `cleaners` e `washers` não têm coluna `fcm_token`. Ver a migration
  /// `20260828120000_push_tokens_faxineiro_lavador.sql`.
  ///
  /// Skips silently se:
  ///   • Not authenticated (após retries)
  ///   • Role fora de [papeisComPush]
  ///   • No FCM token available após 3 retries
  static Future<void> registerForRole(String role) async {
    if (_registering) return;
    if (!papeisComPush.contains(role)) {
      _log('skip — invalid role: $role');
      return;
    }

    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) {
      _log('skip — not authenticated');
      return;
    }

    _registering = true;
    try {
      // BUG E — retry getToken com backoff 1s/3s/9s.
      String? token = NotificationService.instance.fcmToken;
      const delays = [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 9)];
      var attempt = 0;
      while ((token == null || token.isEmpty) && attempt < delays.length) {
        try {
          token = await FirebaseMessaging.instance.getToken();
          if (token != null && token.isNotEmpty) break;
        } catch (e) {
          _log('getToken() attempt ${attempt + 1} failed: $e');
        }
        _log('token null — waiting ${delays[attempt].inSeconds}s (attempt ${attempt + 1}/3)');
        await Future.delayed(delays[attempt]);
        attempt++;
      }
      if (token == null || token.isEmpty) {
        _log('no FCM token after 3 retries — skipping');
        return;
      }

      await _registerRpc(role: role, token: token);

      // Wire token-refresh exactly once per session, keyed by role.
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (newToken) async {
          for (final papel in _papeisRegistados.toList()) {
            await _registerRpc(role: papel, token: newToken);
          }
        },
      );
    } finally {
      _registering = false;
    }
  }

  /// Regista este aparelho em TODOS os papéis que a pessoa tem.
  ///
  /// Antes lia-se `userMetadata['bora_role']`, que guarda **um** valor só. Quem
  /// é motorista e faxineiro ao mesmo tempo ficava registado num papel e mudo
  /// no outro — e a regra do Danilo é que os papéis se acumulam e que a pessoa
  /// tem de ser chamada esteja no ecrã em que estiver.
  ///
  /// A verdade sobre quem acumula o quê está em `user_roles`, que é o que a
  /// RPC `meus_papeis()` lê. O metadata fica como recurso para as contas
  /// antigas que ainda não têm linha em `user_roles` — há-as, e ficar sem
  /// registo nenhum era pior do que registar um papel.
  static Future<void> registerCurrentDeviceAutoDetect() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _log('autodetect skip — no auth user');
      return;
    }

    final papeis = <String>{};
    try {
      final res = await Supabase.instance.client.rpc('meus_papeis');
      if (res is List) {
        papeis.addAll(res
            .map((e) => e.toString().toLowerCase())
            .where(papeisComPush.contains));
      }
    } catch (e) {
      // Não engolir em silêncio: se a RPC falhar queremos saber, senão
      // voltamos a ter avisos que não tocam e ninguém percebe porquê.
      _log('autodetect — meus_papeis() falhou: $e');
    }

    if (papeis.isEmpty) {
      final meta = user.userMetadata ?? <String, dynamic>{};
      final doMeta = (meta['bora_role'] as String?)?.toLowerCase();
      if (doMeta != null && papeisComPush.contains(doMeta)) {
        _log('autodetect — sem user_roles, a usar o metadata: $doMeta');
        papeis.add(doMeta);
      }
    }

    if (papeis.isEmpty) {
      _log('autodetect skip — a pessoa não tem papel nenhum com push');
      return;
    }

    _log('autodetect → ${papeis.length} papel(is): ${papeis.join(", ")}');
    for (final papel in papeis) {
      await registerForRole(papel);
    }
  }

  static Future<void> _registerRpc({
    required String role,
    required String token,
  }) async {
    // Skip duplicate registration if same user+role+token within session.
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (_lastRegisteredToken == token &&
        _lastRegisteredRole == role &&
        _lastRegisteredUserId == uid) {
      return;
    }
    try {
      await Supabase.instance.client.rpc(
        'register_push_token',
        params: {
          'p_role':         role,
          'p_fcm_token':    token,
          'p_device_label': _deviceLabel(),
          'p_platform':     _platform(),
        },
      );
      _lastRegisteredToken = token;
      _lastRegisteredRole = role;
      _papeisRegistados.add(role);
      _lastRegisteredUserId = Supabase.instance.client.auth.currentUser?.id;
      _log('✓ token registado para $role '
          '(tabela: ${tabelaDoPapel(role)})');
    } catch (e) {
      _log('✗ register_push_token RPC failed for role=$role: $e');
    }
  }

  /// Decisão A — Multi-device: NÃO apaga tokens em logout. O token deste
  /// device continua activo para receber pushes futuros se o user
  /// re-autenticar. Tokens só ficam inactivos via mark_token_failed após
  /// 3 falhas FCM consecutivas.
  ///
  /// Esta função é um no-op explícito — exposta apenas por simetria com
  /// AdminPushService API. Reset local apenas.
  static void resetSessionState() {
    _lastRegisteredToken = null;
    _lastRegisteredRole = null;
    _lastRegisteredUserId = null;
    _papeisRegistados.clear();
  }

  static String? _deviceLabel() {
    if (kIsWeb) return 'web';
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return null;
    }
  }

  static String? _platform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {/* fall through */}
    return null;
  }
}
