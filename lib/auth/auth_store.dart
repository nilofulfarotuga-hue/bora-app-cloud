import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_links.dart';
import '../models/driver_model.dart';
import '../models/restaurant_model.dart';
import '../services/biometric_auth_service.dart';
import '../services/notification_service.dart';
import '../services/secure_credentials_store.dart';
import '../utils/constants.dart';

enum AuthRole { client, driver, partner }

/// Desfecho de um pedido de email de recuperação de palavra-passe.
///
/// [ok] NÃO significa "a conta existe" — o Supabase responde 200 mesmo para
/// emails desconhecidos, de propósito, para não revelar quem tem conta.
enum PasswordResetOutcome {
  /// Pedido aceite pelo servidor. Mostrar sempre a mesma frase neutra.
  ok,

  /// 429 — o utilizador pediu outra vez cedo demais.
  rateLimited,

  /// O servidor aceitou o pedido mas falhou a enviar o email (SMTP).
  emailNotSent,

  /// Falha genérica (rede, servidor em baixo).
  failed,
}

class ClientAccount {
  const ClientAccount({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    this.photoUrl = '',
  });

  final String name;
  final String email;
  final String phone;
  final String password;
  final String photoUrl;

  ClientAccount copyWith({String? photoUrl}) => ClientAccount(
        name: name,
        email: email,
        phone: phone,
        password: password,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}

class DriverAccount {
  const DriverAccount({
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicleType,
    required this.licensePlate,
    required this.password,
    this.photoUrl = '',
  });

  final String name;
  final String email;
  final String phone;
  final VehicleType vehicleType;
  final String licensePlate;
  final String password;
  final String photoUrl;

  DriverAccount copyWith({String? photoUrl}) => DriverAccount(
        name: name,
        email: email,
        phone: phone,
        vehicleType: vehicleType,
        licensePlate: licensePlate,
        password: password,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}

class PartnerAccount {
  const PartnerAccount({
    required this.restaurantName,
    required this.address,
    required this.phone,
    required this.email,
    required this.password,
    required this.photoUrl,
    required this.cuisineType,
  });

  final String restaurantName;
  final String address;
  final String phone;
  final String email;
  final String password;
  final String photoUrl;
  final String cuisineType;

  PartnerAccount copyWith({String? photoUrl}) => PartnerAccount(
        restaurantName: restaurantName,
        address: address,
        phone: phone,
        email: email,
        password: password,
        photoUrl: photoUrl ?? this.photoUrl,
        cuisineType: cuisineType,
      );
}

class AuthStore extends ChangeNotifier {
  AuthStore() {
    // 2026-07-31 (varredura de lançamento) — REMOVIDAS as contas de demo
    // hard-coded `cliente@bora.app` e `driver@bora.app` / telefone 910000000,
    // ambas com password '123456'. Viviam em memória e funcionavam OFFLINE,
    // logo eram porta de entrada em RELEASE para quem soubesse as credenciais.
    //
    // Continuam válidas (e intocadas) as duas contas de sistema, que são
    // contas REAIS no Supabase Auth, não hard-coded aqui:
    //   · guest@bora.com — modo convidado
    //   · demo@bora.app  — credencial de revisão da Google Play
    _authSubscription =
        _supabase.auth.onAuthStateChange.listen(_onAuthStateChange);

    _initFromPrefs();
    // Guest session is deferred — _initFromPrefs may re-auth as real user first.
  }

  final _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSubscription;

  /// Mensagem devolvida quando o email já tem conta confirmada no Supabase
  /// Auth — comparação por identidade (==) permite ao caller distinguir este
  /// caso de outros erros sem re-parsear texto.
  static const String duplicatePartnerEmailMessage =
      'Este email já tem uma conta. Faz login em vez de criar uma nova conta.';

  static const _kRole = 'bora_role';
  static const _kName = 'bora_name';
  static const _kPhone = 'bora_phone';
  static const _kEmail = 'bora_email';
  static const _kVehicleType = 'bora_vehicle_type';
  static const _kLicensePlate = 'bora_license_plate';
  static const _kRestaurantName = 'bora_restaurant_name';
  static const _kAddress = 'bora_address';
  static const _kPhotoUrl = 'bora_photo_url';
  static const _kCuisineType = 'bora_cuisine_type';
  static const _kConsentAcceptedAt = 'bora_consent_accepted_at';
  static const _kConsentVersion = 'bora_consent_version';

  /// Version of the Terms + Privacy text currently shown at signup (BR §20.1).
  /// Bump when the legal text changes to trigger re-consent in future flows.
  static const String currentConsentVersion = '1.0';

  static const _kClientAccount = 'bora_auth.client_account';
  static const _kDriverAccount = 'bora_auth.driver_account';
  static const _kPartnerAccount = 'bora_auth.partner_account';

  final Map<String, ClientAccount> _clientsByEmail = {};
  final Map<String, DriverAccount> _driversByEmail = {};
  final Map<String, DriverAccount> _driversByPhone = {};
  final Map<String, PartnerAccount> _partnersByEmail = {};

  ClientAccount? _currentClient;
  DriverAccount? _currentDriver;
  PartnerAccount? _currentPartner;
  RestaurantModel? _partnerRestaurant;
  // Anomalia #5 (fail-safe): default `pending` em vez de `approved`.
  // Se algum caller lê o status antes de loginDriverAsync popular, vê
  // 'pending' (UI bloqueia ir online) em vez de 'approved' (UI aberta).
  DriverStatus _currentDriverStatus = DriverStatus.pending;

  RestaurantModel? get partnerRestaurant => _partnerRestaurant;

  void setPartnerRestaurant(RestaurantModel restaurant) {
    _partnerRestaurant = restaurant;
    notifyListeners();
  }

  bool get isLogged =>
      _currentClient != null ||
      _currentDriver != null ||
      _currentPartner != null;

  bool get isLoggedIn => isLogged;

  String? get userId => _supabase.auth.currentUser?.id;

  /// True when the current Supabase session is the anonymous guest account
  /// (`_guestEmail`). Used by OrderStore to refuse writing orders with the
  /// guest UID, which would otherwise collapse all demo orders into a single
  /// "Cliente Demo" row and break user-scoped RLS / history queries.
  bool get isGuestSession =>
      _supabase.auth.currentUser?.email == _guestEmail;

  AuthRole? get role {
    if (_currentClient != null) return AuthRole.client;
    if (_currentDriver != null) return AuthRole.driver;
    if (_currentPartner != null) return AuthRole.partner;
    return null;
  }

  String? get displayName =>
      _currentClient?.name ??
      _currentDriver?.name ??
      _currentPartner?.restaurantName;

  ClientAccount? get currentClient => _currentClient;
  DriverAccount? get currentDriver => _currentDriver;
  PartnerAccount? get currentPartner => _currentPartner;
  DriverStatus get currentDriverStatus => _currentDriverStatus;

  /// Re-fetches `drivers.approval_status` for the currently logged-in driver
  /// and updates [_currentDriverStatus] / notifies listeners. Safe to call
  /// repeatedly. Returns true if the local state changed (callers can use
  /// this to refresh dependent UI).
  ///
  /// Used by driver_home_screen on initState and AppLifecycleState.resumed
  /// to reflect admin approve/reject/ban without forcing logout-login (BUG 3).
  /// Fail-open: on any error, keeps cached value and logs.
  Future<bool> refreshApprovalStatus() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return false;
    if (_currentDriver == null) return false;
    try {
      final row = await _supabase
          .from('drivers')
          .select('approval_status')
          // Chave correta = user_id (= auth.uid()). Nos motoristas reais
          // id <> user_id; filtrar por id devolvia NULL → gate preso "em análise".
          .eq('user_id', uid)
          .maybeSingle();
      final statusStr = row?['approval_status'] as String? ?? 'pending';
      final fresh = DriverStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => DriverStatus.pending,
      );
      if (fresh == _currentDriverStatus) return false;
      _currentDriverStatus = fresh;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AuthStore] refreshApprovalStatus failed: $e');
      return false;
    }
  }

  bool get hasClientAccounts => _clientsByEmail.isNotEmpty;
  bool get hasDriverAccounts => _driversByEmail.isNotEmpty;
  bool get hasPartnerAccounts => _partnersByEmail.isNotEmpty;

  /// Current user's avatar URL (empty string when not set). Reads from the
  /// local account object so it survives Supabase session cache staleness.
  String get currentPhotoUrl =>
      _currentClient?.photoUrl ??
      _currentDriver?.photoUrl ??
      _currentPartner?.photoUrl ??
      '';

  /// Persists a new avatar URL for the currently logged-in user.
  /// Writes to: (1) in-memory account, (2) SharedPreferences, (3) Supabase
  /// user_metadata. notifyListeners() is called so UI widgets rebuild.
  ///
  /// [url] may be empty to clear the photo.
  Future<void> updateCurrentUserPhoto(String url) async {
    if (_currentClient != null) {
      final updated = _currentClient!.copyWith(photoUrl: url);
      _currentClient = updated;
      if (updated.email.isNotEmpty) _clientsByEmail[updated.email] = updated;
      _persistClient(updated);
    } else if (_currentDriver != null) {
      final updated = _currentDriver!.copyWith(photoUrl: url);
      _currentDriver = updated;
      if (updated.email.isNotEmpty) _driversByEmail[updated.email] = updated;
      if (updated.phone.isNotEmpty) _driversByPhone[updated.phone] = updated;
      _persistDriver(updated);
    } else if (_currentPartner != null) {
      final updated = _currentPartner!.copyWith(photoUrl: url);
      _currentPartner = updated;
      if (updated.email.isNotEmpty) _partnersByEmail[updated.email] = updated;
      _persistPartner(updated);
    } else {
      return;
    }

    // Push to Supabase user_metadata (best-effort — local state is already
    // saved so a server failure doesn't lose the change on restart).
    try {
      await _supabase.auth.updateUser(
        UserAttributes(data: {_kPhotoUrl: url}),
      );
    } catch (e) {
      debugPrint('AuthStore: updateUser photoUrl failed => $e');
    }

    // Push to public tables so other devices and admin screens see the photo.
    // UPSERT for users (row may not exist — no auto-create trigger from auth).
    // UPDATE for drivers/restaurants (row always exists after signup/onboarding).
    final uid = _supabase.auth.currentUser?.id;
    if (uid != null) {
      try {
        if (_currentClient != null) {
          await _supabase
              .from('users')
              .upsert({'id': uid, 'photo_url': url});
        } else if (_currentDriver != null) {
          await _supabase
              .from('drivers')
              .update({'photo_url': url})
              .eq('user_id', uid);
        } else if (_currentPartner != null) {
          final restaurantId = _partnerRestaurant?.id;
          if (restaurantId != null) {
            await _supabase
                .from('restaurants')
                .update({'photo_url': url})
                .eq('id', restaurantId);
          }
        }
      } catch (e) {
        debugPrint('AuthStore: updateCurrentUserPhoto public table => $e');
      }
    }

    notifyListeners();
  }

  void _onAuthStateChange(AuthState state) {
    final session = state.session;

    if (session == null) {
      // Only clear local state if this is a real sign-out, not a token hiccup.
      // _ensureGuestSession will re-establish a session immediately after.
      return;
    }

    // Recuperação de palavra-passe: o Supabase cria uma sessão temporária ao
    // abrir o link do email. NÃO hidratar conta aqui — isso "logaria" o
    // utilizador direto no ecrã principal do seu papel antes de escolher a
    // nova palavra-passe. main.dart escuta este evento à parte e abre o
    // ResetPasswordScreen.
    if (state.event == AuthChangeEvent.passwordRecovery) return;

    // L3 — o Supabase roda o refresh token a cada refresh; mantém o token
    // biométrico guardado em dia (só para papéis com biometria ativa e
    // email coincidente). Fire-and-forget.
    if (state.event == AuthChangeEvent.tokenRefreshed ||
        state.event == AuthChangeEvent.signedIn) {
      BiometricAuthService.instance.syncRefreshedToken(session).ignore();
    }

    if (_currentClient != null ||
        _currentDriver != null ||
        _currentPartner != null) {
      return;
    }

    _hydrateAccountFromSession(session);
  }

  /// Constrói a conta em memória a partir dos metadados da sessão Supabase.
  /// Usado pelo listener onAuthStateChange e pelo restauro biométrico (L3).
  void _hydrateAccountFromSession(Session session) {
    final meta = session.user.userMetadata ?? {};
    final boraRole = meta[_kRole] as String?;

    switch (boraRole) {
      case 'client':
        final email = session.user.email ?? '';
        final account = ClientAccount(
          name: meta[_kName] as String? ?? '',
          email: email,
          phone: meta[_kPhone] as String? ?? '',
          password: '',
          photoUrl: meta[_kPhotoUrl] as String? ?? '',
        );
        _clientsByEmail[email] = account;
        _currentClient = account;
        notifyListeners();
        break;

      case 'driver':
        final email = session.user.email ?? '';
        final phone = meta[_kPhone] as String? ?? '';
        final vtStr = meta[_kVehicleType] as String? ?? 'car';
        final account = DriverAccount(
          name: meta[_kName] as String? ?? '',
          email: email,
          phone: phone,
          // fromDb aceita nomes do enum E o canónico da DB ('carro_passageiros').
          vehicleType: VehicleTypeDb.fromDb(vtStr),
          licensePlate: meta[_kLicensePlate] as String? ?? '',
          password: '',
        );
        _driversByEmail[email] = account;
        if (phone.isNotEmpty) _driversByPhone[phone] = account;
        _currentDriver = account;
        notifyListeners();
        // [TVDE P0 2026-07-02] Fonte de verdade = coluna DB. O metadata pode
        // estar desatualizado (ex.: admin mudou para 'carro_passageiros') e
        // sem isto a aba TVDE desaparecia ao reabrir o app (hydrate só lia o
        // metadata). Fire-and-forget: corrige e notifica quando chegar.
        unawaited(_refreshDriverVehicleTypeFromDb(session.user.id, email));
        break;

      case 'partner':
        final email = session.user.email ?? '';
        final account = PartnerAccount(
          restaurantName: meta[_kRestaurantName] as String? ?? '',
          address: meta[_kAddress] as String? ?? '',
          phone: meta[_kPhone] as String? ?? '',
          email: email,
          password: '',
          photoUrl: meta[_kPhotoUrl] as String? ?? '',
          cuisineType: meta[_kCuisineType] as String? ?? '',
        );
        _partnersByEmail[email] = account;
        _currentPartner = account;
        notifyListeners();
        break;

      default:
        break;
    }
  }

  /// [TVDE P0 2026-07-02] Reconcilia o vehicleType do driver em memória com a
  /// coluna `drivers.vehicle_type` (fonte de verdade, chave = user_id). O
  /// hydrate por metadata podia devolver 'car'/'motorcycle' num motorista
  /// 'carro_passageiros' → _RootNavigator não mostrava o modo TVDE.
  Future<void> _refreshDriverVehicleTypeFromDb(
      String userId, String email) async {
    try {
      final row = await _supabase
          .from('drivers')
          .select('vehicle_type')
          .eq('user_id', userId)
          .maybeSingle();
      final vtDb = row?['vehicle_type'] as String?;
      if (vtDb == null || vtDb.isEmpty) return;
      final current = _currentDriver;
      if (current == null || current.email != email) return;
      final resolved = VehicleTypeDb.fromDb(vtDb);
      if (resolved == current.vehicleType) return;
      final account = DriverAccount(
        name: current.name,
        email: current.email,
        phone: current.phone,
        vehicleType: resolved,
        licensePlate: current.licensePlate,
        password: current.password,
        photoUrl: current.photoUrl,
      );
      _driversByEmail[email] = account;
      if (current.phone.isNotEmpty) _driversByPhone[current.phone] = account;
      _currentDriver = account;
      notifyListeners();
    } catch (_) {
      // Sem rede/na dúvida mantém o que o metadata deu — não bloqueia o login.
    }
  }

  /// L3 — restaura a sessão Supabase a partir do refresh token guardado em
  /// secure storage (login biométrico). Devolve null em sucesso, 'invalid'
  /// quando o token foi revogado/expirou ou o papel não bate (o ecrã deve
  /// apagar o token e cair para a palavra-passe), 'error' em falha de rede.
  Future<String?> restoreSessionWithRefreshToken(
    String refreshToken, {
    required String expectedRole,
  }) async {
    try {
      // Igual aos logins por palavra-passe: limpa sessão guest/obsoleta
      // antes, para auth.currentUser nunca ficar com UID errado.
      try {
        await _supabase.auth.signOut();
      } catch (_) {}

      final res = await _supabase.auth.setSession(refreshToken);
      final user = res.user;
      final session = res.session;
      if (user == null || session == null) return 'invalid';

      final meta = user.userMetadata ?? {};
      final role = meta[_kRole] as String?;
      // Contas legadas/demo de cliente podem não ter role nos metadados —
      // mesma tolerância do loginClientAsync.
      final roleOk =
          role == expectedRole || (expectedRole == 'client' && role == null);
      if (!roleOk) {
        debugPrint(
            'AuthStore: restoreSession wrong role "$role" (expected "$expectedRole")');
        try {
          await _supabase.auth.signOut();
        } catch (_) {}
        return 'invalid';
      }

      _hydrateAccountFromSession(session);
      debugPrint(
          'AuthStore: biometric session restored — uid=${user.id} role=$expectedRole');
      return null;
    } on AuthException catch (e) {
      debugPrint('AuthStore: restoreSession AuthException => ${e.message}');
      return 'invalid';
    } catch (e) {
      debugPrint('AuthStore: restoreSession error => $e');
      return 'error';
    }
  }

  // ── Guest session ─────────────────────────────────────────────────────────

  static const _guestEmail = 'guest@bora.com';
  static const _guestPassword = '123456';

  Future<void> _ensureGuestSession() async {
    if (_supabase.auth.currentUser != null) return;

    try {
      await _supabase.auth.signInWithPassword(
        email: _guestEmail,
        password: _guestPassword,
      );
      debugPrint(
          'AuthStore: guest session OK — uid=${_supabase.auth.currentUser?.id}');
      return;
    } catch (e) {
      debugPrint('AuthStore: guest sign-in failed, trying signUp => $e');
    }

    try {
      await _supabase.auth.signUp(
        email: _guestEmail,
        password: _guestPassword,
      );
      if (_supabase.auth.currentUser != null) {
        debugPrint(
            'AuthStore: guest account created — uid=${_supabase.auth.currentUser?.id}');
        return;
      }
      await _supabase.auth.signInWithPassword(
        email: _guestEmail,
        password: _guestPassword,
      );
    } catch (e) {
      debugPrint('AuthStore: guest session FAILED => $e');
    }
  }

  /// Public wrapper — ensures a valid Supabase session exists before order
  /// insertion. No-op if already authenticated. Re-signs-in as guest if not.
  Future<void> ensureSessionForOrder() => _ensureGuestSession();

  Future<void> _signInBackground({
    required String email,
    required String password,
    required String tag,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      debugPrint(
          'AuthStore: $tag signed in — uid=${_supabase.auth.currentUser?.id}');
    } catch (e) {
      debugPrint('AuthStore: $tag signIn error => $e');
    }
  }

  Future<void> _signOutBackground() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('AuthStore: signOut error => $e');
    }
    // No guest fallback after logout — driver flow must not inherit a guest
    // UID as driverId. Client anonymous ordering uses auth_service.dart instead.
  }

  // ─── Client ───────────────────────────────────────────────────────────────

  String? registerClient({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }
    if (_clientsByEmail.containsKey(normalizedEmail)) {
      return 'Já existe uma conta com este e-mail.';
    }
    final account = ClientAccount(
      name: name.trim(),
      email: normalizedEmail,
      phone: phone.trim(),
      password: password,
    );
    _clientsByEmail[normalizedEmail] = account;
    _currentClient = account;
    _currentDriver = null;
    _currentPartner = null;
    notifyListeners();
    _persistClient(account);
    unawaited(
      _supabase.auth
          .signUp(
            email: normalizedEmail,
            password: password,
            data: {
              _kRole: 'client',
              _kName: name.trim(),
              _kPhone: phone.trim()
            },
          )
          .then<void>((_) {})
          .catchError((e) {
            debugPrint(
                'AuthStore: registerClient background signUp error => $e');
          }),
    );
    return null;
  }

  Future<String?> registerClientAsync({
    required String name,
    required String email,
    required String phone,
    required String password,
    DateTime? consentAcceptedAt,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = name.trim();
    final normalizedPhone = phone.trim();

    if (normalizedEmail.isEmpty || password.isEmpty || normalizedName.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }

    try {
      final res = await _supabase.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          _kRole: 'client',
          _kName: normalizedName,
          _kPhone: normalizedPhone,
          if (consentAcceptedAt != null)
            _kConsentAcceptedAt: consentAcceptedAt.toUtc().toIso8601String(),
          if (consentAcceptedAt != null) _kConsentVersion: currentConsentVersion,
        },
      );

      final user = res.user;
      if (user == null) {
        return 'Não foi possível criar a conta. Tente novamente.';
      }

      if (res.session == null) {
        try {
          await _supabase.auth.signInWithPassword(
            email: normalizedEmail,
            password: password,
          );
        } catch (_) {}
      }

      final account = ClientAccount(
        name: normalizedName,
        email: normalizedEmail,
        phone: normalizedPhone,
        password: password,
      );
      _clientsByEmail[normalizedEmail] = account;
      _currentClient = account;
      _currentDriver = null;
      _currentPartner = null;
      notifyListeners();
      _persistClient(account);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erro ao criar conta. Tente novamente.';
    }
  }

  bool loginClient(String email, String password) {
    final account = _clientsByEmail[email.trim().toLowerCase()];
    if (account == null || account.password != password) return false;
    _currentClient = account;
    _currentDriver = null;
    _currentPartner = null;
    notifyListeners();
    _persistClient(account);
    _signInBackground(
        email: email.trim().toLowerCase(),
        password: password,
        tag: 'loginClient');
    return true;
  }

  Future<bool> loginClientAsync(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

    debugPrint(
        '[AuthStore] loginClientAsync → normalizedEmail=$normalizedEmail');

    // Clear any stale or guest session BEFORE attempting login. Without this,
    // auth.currentUser.id keeps returning the guest UID while Supabase
    // signInWithPassword is awaited — any order created in between would be
    // persisted with the guest UID (root cause of 39/42 orders tagged as
    // 'f9ad894e-42a2-44ca-a4b0-2546bdb11cb9' / 'Cliente Demo' in the DB).
    try {
      await _supabase.auth.signOut();
    } catch (_) {}

    try {
      final res = await _supabase.auth
          .signInWithPassword(email: normalizedEmail, password: password);
      final user = res.user;
      if (user == null) {
        debugPrint('[AuthStore] loginClientAsync → signIn returned null user');
        return false;
      }

      final meta = user.userMetadata ?? {};
      final metaRole = meta[_kRole] as String?;
      // Accept accounts with role 'client' OR legacy/demo accounts with no
      // role metadata. Reject anything explicitly tagged as driver/partner.
      if (metaRole != null && metaRole != 'client') {
        debugPrint(
            '[AuthStore] loginClientAsync → wrong role: "$metaRole" — signing out');
        try {
          await _supabase.auth.signOut();
        } catch (_) {}
        return false;
      }

      final local = _clientsByEmail[normalizedEmail];
      final account = local ??
          ClientAccount(
            name: meta[_kName] as String? ?? '',
            email: normalizedEmail,
            phone: meta[_kPhone] as String? ?? '',
            password: password,
            photoUrl: meta[_kPhotoUrl] as String? ?? '',
          );
      _currentClient = account;
      _currentDriver = null;
      _currentPartner = null;
      notifyListeners();
      _clientsByEmail[normalizedEmail] = account;
      _persistClient(account);
      debugPrint(
          '[AuthStore] loginClientAsync → SUCCESS uid=${user.id} email=$normalizedEmail');
      return true;
    } catch (e) {
      debugPrint('AuthStore: loginClientAsync error => $e');
      return false;
    }
  }

  // ─── Driver ───────────────────────────────────────────────────────────────

  /// Legacy shortcut: creates driver + auto-logs in without approval.
  /// Bypasses BR §7 (admin approval with documents + IBAN).
  /// Production flow: use DriverSignupScreen → DriverPendingScreen.
  /// Kept for admin tooling / tests.
  @Deprecated('Use DriverSignupScreen flow (BR §7). This bypasses approval.')
  Future<String?> registerDriverAsync({
    required String name,
    required String email,
    required String phone,
    required VehicleType vehicleType,
    required String licensePlate,
    required String password,
    DateTime? consentAcceptedAt,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = phone.trim();

    if (name.trim().isEmpty || normalizedEmail.isEmpty || password.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }

    try {
      final res = await _supabase.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          _kRole: 'driver',
          _kName: name.trim(),
          _kEmail: normalizedEmail,
          _kPhone: normalizedPhone,
          _kVehicleType: vehicleType.name,
          _kLicensePlate: licensePlate.trim(),
          if (consentAcceptedAt != null)
            _kConsentAcceptedAt: consentAcceptedAt.toUtc().toIso8601String(),
          if (consentAcceptedAt != null) _kConsentVersion: currentConsentVersion,
        },
      );

      final user = res.user;
      if (user == null) {
        return 'Não foi possível criar a conta. Tente novamente.';
      }

      if (res.session == null) {
        try {
          await _supabase.auth.signInWithPassword(
            email: normalizedEmail,
            password: password,
          );
        } catch (_) {}
      }

      try {
        await _supabase.from('drivers').upsert({
          'id': user.id,
          'user_id': user.id,
          'name': name.trim(),
          'phone': normalizedPhone,
          'email': normalizedEmail,
          // Canónico da DB (carPassengers → 'carro_passageiros'); .name daria
          // uma 5.ª grafia e o dispatch/aba TVDE não reconheciam (P0 2026-07-02).
          'vehicle_type': vehicleType.dbValue,
          'license_plate': licensePlate.trim(),
          'is_online': false,
          'lat': kGuardaLat,
          'lng': kGuardaLng,
          'status': 'pending',
          if (consentAcceptedAt != null)
            'consent_accepted_at': consentAcceptedAt.toUtc().toIso8601String(),
          if (consentAcceptedAt != null)
            'consent_version': currentConsentVersion,
        });
      } catch (e) {
        debugPrint(
            'AuthStore: registerDriverAsync - drivers upsert error => $e');
      }

      final account = DriverAccount(
        name: name.trim(),
        email: normalizedEmail,
        phone: normalizedPhone,
        vehicleType: vehicleType,
        licensePlate: licensePlate.trim(),
        password: password,
      );
      _driversByEmail[normalizedEmail] = account;
      if (normalizedPhone.isNotEmpty) {
        _driversByPhone[normalizedPhone] = account;
      }
      _currentDriver = account;
      _currentClient = null;
      _currentPartner = null;
      notifyListeners();
      _persistDriver(account);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Erro ao criar conta. Tente novamente.';
    }
  }

  Future<bool> loginDriverAsync(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

    debugPrint(
        '[AuthStore] loginDriverAsync → normalizedEmail=$normalizedEmail');

    // Clear any stale or guest session BEFORE attempting login.
    // Without this, if signInWithPassword throws (user not found, wrong
    // password), the old/guest session stays active and auth.currentUser.id
    // would return the wrong UID for all subsequent driver operations.
    try {
      await _supabase.auth.signOut();
      debugPrint(
          '[AuthStore] loginDriverAsync → signOut OK (cleared previous session)');
    } catch (_) {}

    try {
      final res = await _supabase.auth
          .signInWithPassword(email: normalizedEmail, password: password);
      final user = res.user;

      if (user == null) {
        debugPrint('[AuthStore] loginDriverAsync → signIn returned null user');
        return false;
      }

      debugPrint(
          '[AuthStore] loginDriverAsync → auth.currentUser.id=${user.id}');

      final meta = user.userMetadata ?? {};
      final role = meta[_kRole] as String?;
      if (role != 'driver') {
        debugPrint(
            '[AuthStore] loginDriverAsync → wrong role: "$role" (expected "driver") — signing out');
        // Sign out immediately so the non-driver session is not left active.
        try {
          await _supabase.auth.signOut();
        } catch (_) {}
        return false;
      }

      debugPrint(
          '[AuthStore] loginDriverAsync → SUCCESS uid=${user.id} role=$role');

      final vtStr = meta[_kVehicleType] as String? ?? 'car';
      final phone = meta[_kPhone] as String? ?? '';
      // Fetch driver status from DB to enforce approval gate.
      DriverStatus driverStatus = DriverStatus.approved;
      // Fonte de verdade do tipo de veículo = coluna DB (canónica, p.ex.
      // 'carro_passageiros'). Necessária para rotear o motorista TVDE para o
      // modo passageiros. Fallback para o metadata se a coluna vier vazia.
      String? vtDb;
      try {
        final row = await _supabase
            .from('drivers')
            .select('approval_status, vehicle_type')
            // Chave correta = user_id (= auth.uid()). Por id, no motorista TVDE
            // (id <> user_id) vinha NULL → vehicle_type não detetado → não roteava
            // para o modo passageiros.
            .eq('user_id', user.id)
            .maybeSingle();
        final statusStr = row?['approval_status'] as String? ?? 'approved';
        vtDb = row?['vehicle_type'] as String?;
        driverStatus = DriverStatus.values.firstWhere(
          (s) => s.name == statusStr,
          orElse: () => DriverStatus.approved,
        );
      } catch (_) {}

      final account = DriverAccount(
        name: meta[_kName] as String? ?? '',
        email: normalizedEmail,
        phone: phone,
        vehicleType: (vtDb != null && vtDb.isNotEmpty)
            ? VehicleTypeDb.fromDb(vtDb)
            // fromDb aceita nomes do enum e grafias legadas ('carPassengers').
            : VehicleTypeDb.fromDb(vtStr),
        licensePlate: meta[_kLicensePlate] as String? ?? '',
        password: password,
      );
      _currentDriver = account;
      _currentDriverStatus = driverStatus;
      _currentClient = null;
      _currentPartner = null;
      notifyListeners();
      _driversByEmail[normalizedEmail] = account;
      if (phone.isNotEmpty) _driversByPhone[phone] = account;
      _persistDriver(account);
      return true;
    } catch (e) {
      debugPrint('[AuthStore] loginDriverAsync → FAILED: $e');
      return false;
    }
  }

  /// Página para onde o Supabase reencaminha depois do clique no email de
  /// recuperação. Fonte única em `lib/config/auth_links.dart` — tem de estar
  /// na allow-list "Redirect URLs" do Supabase Auth (dashboard).
  static const String _passwordResetRedirect = passwordResetRedirect;

  Future<PasswordResetOutcome> resetDriverPassword(String email) =>
      resetPassword(email);

  /// Pede o email de recuperação. Serve os três papéis (cliente, estafeta,
  /// parceiro) — do lado do Supabase é sempre a mesma operação `/recover`.
  ///
  /// Devolve o desfecho em vez de o engolir: o ecrã precisa de distinguir
  /// "pedimos demasiadas vezes seguidas" de "o servidor de email está em
  /// baixo", senão o utilizador fica à espera de um email que nunca chega
  /// sem perceber porquê. Nunca revela se a conta existe — isso é decidido
  /// pelo ecrã, que mostra sempre a mesma frase em [PasswordResetOutcome.ok].
  Future<PasswordResetOutcome> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email.trim().toLowerCase(),
        redirectTo: _passwordResetRedirect,
      );
      return PasswordResetOutcome.ok;
    } on AuthException catch (e) {
      debugPrint('AuthStore: resetPassword AuthException => ${e.statusCode} ${e.message}');
      // 429 = demasiados pedidos seguidos (limite do Supabase Auth).
      if (e.statusCode == '429' ||
          e.message.toLowerCase().contains('rate limit') ||
          e.message.toLowerCase().contains('security purposes')) {
        return PasswordResetOutcome.rateLimited;
      }
      // 500 + "error sending" = SMTP mal configurado no dashboard. Para o
      // utilizador é indistinguível de avaria — mas o log diz a verdade.
      if (e.message.toLowerCase().contains('sending')) {
        return PasswordResetOutcome.emailNotSent;
      }
      return PasswordResetOutcome.failed;
    } catch (e) {
      debugPrint('AuthStore: resetPassword error => $e');
      return PasswordResetOutcome.failed;
    }
  }

  bool loginDriver(String phone, String password) {
    final account = _driversByPhone[phone.trim()];
    if (account == null || account.password != password) return false;
    _currentDriver = account;
    _currentClient = null;
    _currentPartner = null;
    notifyListeners();
    _persistDriver(account);
    _signInBackground(
        email: account.email, password: password, tag: 'loginDriver');
    return true;
  }

  // ─── Partner ──────────────────────────────────────────────────────────────

  String? registerPartner({
    required String restaurantName,
    required String address,
    required String phone,
    required String email,
    required String password,
    required String photoUrl,
    required String cuisineType,
    DateTime? consentAcceptedAt,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    if (restaurantName.trim().isEmpty ||
        normalizedEmail.isEmpty ||
        password.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }
    if (_partnersByEmail.containsKey(normalizedEmail)) {
      return 'Já existe um parceiro registado com este email.';
    }
    final partner = PartnerAccount(
      restaurantName: restaurantName.trim(),
      address: address.trim(),
      phone: phone.trim(),
      email: normalizedEmail,
      password: password,
      photoUrl: photoUrl.trim(),
      cuisineType: cuisineType.trim(),
    );
    _partnersByEmail[normalizedEmail] = partner;
    _persistPartner(partner);
    _currentPartner = partner;
    _currentClient = null;
    _currentDriver = null;
    notifyListeners();
    unawaited(
      _supabase.auth
          .signUp(
            email: normalizedEmail,
            password: password,
            data: {
              _kRole: 'partner',
              _kName: restaurantName.trim(),
              _kRestaurantName: restaurantName.trim(),
              _kAddress: address.trim(),
              _kPhone: phone.trim(),
              _kPhotoUrl: photoUrl.trim(),
              _kCuisineType: cuisineType.trim(),
              if (consentAcceptedAt != null)
                _kConsentAcceptedAt:
                    consentAcceptedAt.toUtc().toIso8601String(),
              if (consentAcceptedAt != null)
                _kConsentVersion: currentConsentVersion,
            },
          )
          .then<void>((_) {})
          .catchError((e) {
            debugPrint(
                'AuthStore: registerPartner background signUp error => $e');
          }),
    );
    return null;
  }

  /// Async version of registerPartner — awaits Supabase signUp before
  /// committing local state. Required for production onboarding: the sync
  /// version (registerPartner) races Supabase and can leave a partner logged-in
  /// locally with no real account in the DB.
  ///
  /// [photoUrl] is optional — pass empty string to register without photo.
  /// Returns null on success, human-readable error message on failure.
  Future<String?> registerPartnerAsync({
    required String restaurantName,
    required String address,
    required String phone,
    required String email,
    required String password,
    required String photoUrl,
    required String cuisineType,
    DateTime? consentAcceptedAt,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (restaurantName.trim().isEmpty ||
        normalizedEmail.isEmpty ||
        password.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }
    if (_partnersByEmail.containsKey(normalizedEmail)) {
      return 'Já existe um parceiro registado com este email.';
    }
    try {
      final res = await _supabase.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          _kRole: 'partner',
          _kName: restaurantName.trim(),
          _kRestaurantName: restaurantName.trim(),
          _kAddress: address.trim(),
          _kPhone: phone.trim(),
          _kPhotoUrl: photoUrl.trim(),
          _kCuisineType: cuisineType.trim(),
          if (consentAcceptedAt != null)
            _kConsentAcceptedAt:
                consentAcceptedAt.toUtc().toIso8601String(),
          if (consentAcceptedAt != null)
            _kConsentVersion: currentConsentVersion,
        },
      );

      final user = res.user;
      if (user == null) {
        return 'Não foi possível criar a conta. Tente novamente.';
      }

      // Supabase devolve um user "fantasma" com identities vazio quando o
      // email já tem conta confirmada (proteção anti-enumeração) — não
      // lança AuthException, por isso é preciso detetar aqui explicitamente.
      if (user.identities == null || user.identities!.isEmpty) {
        return duplicatePartnerEmailMessage;
      }

      // Ensure session is active (some Supabase configs require email confirm).
      if (res.session == null) {
        try {
          await _supabase.auth.signInWithPassword(
            email: normalizedEmail,
            password: password,
          );
        } catch (_) {}
      }

      final partner = PartnerAccount(
        restaurantName: restaurantName.trim(),
        address: address.trim(),
        phone: phone.trim(),
        email: normalizedEmail,
        password: password,
        photoUrl: photoUrl.trim(),
        cuisineType: cuisineType.trim(),
      );
      _partnersByEmail[normalizedEmail] = partner;
      _currentPartner = partner;
      _currentClient = null;
      _currentDriver = null;
      notifyListeners();
      _persistPartner(partner);
      return null;
    } on AuthException catch (e) {
      // Caso real (validado ao vivo contra este projecto Supabase): conta já
      // confirmada => 422 code=user_already_exists, NÃO o "user fantasma"
      // de identities vazio. Sem este check, o erro chegava em inglês e sem
      // isDuplicateEmail, e o ecrã não voltava ao passo "Conta de Acesso".
      if (e.code == 'user_already_exists') {
        return duplicatePartnerEmailMessage;
      }
      // Restantes erros do Supabase (ex.: password fraca) — mostra tal qual.
      return e.message;
    } catch (e) {
      return 'Erro ao criar conta. Tente novamente.';
    }
  }

  /// Novo: registra parceiro com documentos (NIF, IBAN, owner_doc_url, activity_doc_url).
  /// Documentos são OPCIONAIS — validação de formato só se preenchidos.
  /// Workflow: 1) registerPartnerAsync (cria auth user) → 2) invocar Edge Function
  /// register-partner (insere restaurants com approval_status='pending').
  /// Retorna { restaurantId, approvalStatus } ou erro.
  Future<Map<String, dynamic>?> registerPartnerWithDocumentsAsync({
    required String restaurantName,
    required String address,
    required String phone,
    required String email,
    required String password,
    required String cuisineType,
    required String category,
    double? lat,
    double? lng,
    String? nif,
    String? iban,
    String? ownerDocUrl,
    String? activityDocUrl,
    String? photoUrl,
    String? coverUrl,
    bool reservationsEnabled = false,
    bool takeawayEnabled = false,
    DateTime? consentAcceptedAt,
  }) async {
    // Step 1: Cria auth user via registerPartnerAsync
    final authError = await registerPartnerAsync(
      restaurantName: restaurantName,
      address: address,
      phone: phone,
      email: email,
      password: password,
      photoUrl: '',
      cuisineType: cuisineType,
      consentAcceptedAt: consentAcceptedAt,
    );

    if (authError != null) {
      debugPrint('[AuthStore] registerPartnerWithDocumentsAsync: registerPartnerAsync failed => $authError');
      return {
        'error': authError,
        'isDuplicateEmail': authError == duplicatePartnerEmailMessage,
      };
    }

    return _submitRestaurantEdgeFunction(
      restaurantName: restaurantName,
      address: address,
      phone: phone,
      email: email,
      cuisineType: cuisineType,
      category: category,
      lat: lat,
      lng: lng,
      nif: nif,
      iban: iban,
      ownerDocUrl: ownerDocUrl,
      activityDocUrl: activityDocUrl,
      photoUrl: photoUrl,
      coverUrl: coverUrl,
      reservationsEnabled: reservationsEnabled,
      takeawayEnabled: takeawayEnabled,
    );
  }

  /// Retoma o registo de um parceiro que JÁ está autenticado (login com conta
  /// existente) mas ainda não tem `restaurants`/`service_providers` — caso da
  /// conta de acesso criada numa tentativa anterior cuja submissão falhou.
  /// Ao contrário de [registerPartnerWithDocumentsAsync], NÃO chama
  /// [registerPartnerAsync] (isso tentaria criar de novo o auth user e falha
  /// sempre com "email já existe", prendendo o utilizador num loop mesmo já
  /// autenticado). Usa a sessão Supabase corrente — a Edge Function
  /// register-partner só precisa do JWT (extrai o user_id de lá).
  Future<Map<String, dynamic>?> resumePartnerRegistrationAsync({
    required String restaurantName,
    required String address,
    required String phone,
    required String cuisineType,
    required String category,
    double? lat,
    double? lng,
    String? nif,
    String? iban,
    String? ownerDocUrl,
    String? activityDocUrl,
    String? photoUrl,
    String? coverUrl,
    bool reservationsEnabled = false,
    bool takeawayEnabled = false,
  }) async {
    final partner = _currentPartner;
    if (partner == null) {
      return {
        'error': 'Sessão expirada. Faz login novamente.',
        'isDuplicateEmail': false,
      };
    }
    return _submitRestaurantEdgeFunction(
      restaurantName: restaurantName,
      address: address,
      phone: phone,
      email: partner.email,
      cuisineType: cuisineType,
      category: category,
      lat: lat,
      lng: lng,
      nif: nif,
      iban: iban,
      ownerDocUrl: ownerDocUrl,
      activityDocUrl: activityDocUrl,
      photoUrl: photoUrl,
      coverUrl: coverUrl,
      reservationsEnabled: reservationsEnabled,
      takeawayEnabled: takeawayEnabled,
    );
  }

  /// Invoca a Edge Function register-partner c/ service_role (Step 2 do
  /// workflow de registo). Extraído para ser partilhado por
  /// [registerPartnerWithDocumentsAsync] (fluxo novo, cria conta primeiro) e
  /// [resumePartnerRegistrationAsync] (fluxo de retomada, já autenticado).
  Future<Map<String, dynamic>?> _submitRestaurantEdgeFunction({
    required String restaurantName,
    required String address,
    required String phone,
    required String email,
    required String cuisineType,
    required String category,
    double? lat,
    double? lng,
    String? nif,
    String? iban,
    String? ownerDocUrl,
    String? activityDocUrl,
    String? photoUrl,
    String? coverUrl,
    bool reservationsEnabled = false,
    bool takeawayEnabled = false,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'register-partner',
        body: {
          'restaurantName': restaurantName,
          'address': address,
          'phone': phone,
          'email': email,
          'cuisineType': cuisineType,
          'category': category,
          'lat': lat,
          'lng': lng,
          'nif': nif,
          'iban': iban,
          'ownerDocUrl': ownerDocUrl,
          'activityDocUrl': activityDocUrl,
          'photoUrl': photoUrl,
          'coverUrl': coverUrl,
          'reservationsEnabled': reservationsEnabled,
          'takeawayEnabled': takeawayEnabled,
        },
      );

      if (response.status != 201) {
        debugPrint('[AuthStore] register-partner EF returned ${response.status}: ${response.data}');
        // A conta de acesso (email+senha) JÁ foi criada no passo anterior —
        // não é um problema de email/password. O backend já devolve uma
        // mensagem específica em `error` (ex.: "NIF formato inválido") —
        // mostra-a em vez do texto genérico, para o utilizador saber o que
        // corrigir sem contactar o suporte.
        final responseData = response.data;
        final backendError =
            responseData is Map ? responseData['error']?.toString() : null;
        return {
          'error': (backendError != null && backendError.trim().isNotEmpty)
              ? backendError
              : 'A tua conta de acesso foi criada, mas houve um erro ao registar o estabelecimento. Contacta o suporte — não precisas de repetir o email/senha.',
          'isDuplicateEmail': false,
        };
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      return {
        'restaurant_id': data['restaurant_id'],
        'provider_id': data['provider_id'],
        'approval_status': data['status'],
        'message': data['message'],
      };
    } catch (e) {
      debugPrint('[AuthStore] _submitRestaurantEdgeFunction failed => $e');
      return {
        'error':
            'A tua conta de acesso foi criada, mas houve um erro de ligação ao registar o estabelecimento. Contacta o suporte — não precisas de repetir o email/senha.',
        'isDuplicateEmail': false,
      };
    }
  }

  bool loginPartner(String email, String password) {
    final account = _partnersByEmail[email.trim().toLowerCase()];
    if (account == null || account.password != password) return false;
    _currentPartner = account;
    _currentClient = null;
    _currentDriver = null;
    notifyListeners();
    _persistPartner(account);
    _signInBackground(
        email: email.trim().toLowerCase(),
        password: password,
        tag: 'loginPartner');
    return true;
  }

  Future<bool> loginPartnerAsync(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

    final local = _partnersByEmail[normalizedEmail];
    if (local != null && local.password == password) {
      _currentPartner = local;
      _currentClient = null;
      _currentDriver = null;
      notifyListeners();
      // BUG 3 (2026-07-17): esperar a sessão real do Supabase Auth aqui —
      // sem isto, o dashboard do parceiro abre com auth.uid() ainda nulo e
      // os toggles (reservationsEnabled/takeawayEnabled/curbsideEnabled)
      // falham em silêncio contra a RLS "auth.uid() IS NOT NULL" da tabela
      // restaurants, revertendo ao reabrir a app.
      await _signInBackground(
          email: normalizedEmail,
          password: password,
          tag: 'loginPartnerAsync-local');
      return true;
    }

    try {
      final res = await _supabase.auth
          .signInWithPassword(email: normalizedEmail, password: password);
      final user = res.user;
      if (user == null) return false;

      final meta = user.userMetadata ?? {};
      if ((meta[_kRole] as String?) != 'partner') return false;

      final account = PartnerAccount(
        restaurantName: meta[_kRestaurantName] as String? ?? '',
        address: meta[_kAddress] as String? ?? '',
        phone: meta[_kPhone] as String? ?? '',
        email: normalizedEmail,
        password: password,
        photoUrl: meta[_kPhotoUrl] as String? ?? '',
        cuisineType: meta[_kCuisineType] as String? ?? '',
      );
      _currentPartner = account;
      _currentClient = null;
      _currentDriver = null;
      notifyListeners();
      _partnersByEmail[normalizedEmail] = account;
      _persistPartner(account);
      return true;
    } catch (e) {
      debugPrint('AuthStore: loginPartnerAsync error => $e');
      return false;
    }
  }

  // ─── Lookups ──────────────────────────────────────────────────────────────

  PartnerAccount? partnerAccountByEmail(String email) =>
      _partnersByEmail[email.trim().toLowerCase()];

  DriverAccount? driverAccountByPhone(String phone) =>
      _driversByPhone[phone.trim()];

  DriverAccount? driverAccountByEmail(String email) =>
      _driversByEmail[email.trim().toLowerCase()];

  // ─── Logout ───────────────────────────────────────────────────────────────

  /// [wipeBiometrics]: true (default) em logout explícito ("Sair"/"Terminar
  /// sessão") — apaga também os tokens biométricos (L3, regra de segurança).
  /// Trocas de papel/modo (RoleScreen, "Mudar modo", gates de aprovação)
  /// passam false para o login biométrico continuar disponível.
  void logout({bool wipeBiometrics = true}) {
    // Clear FCM binding BEFORE wiping state so the previous user stops
    // receiving pushes on this device. Fire-and-forget — logout must not
    // block on network failure.
    NotificationService.instance.clearTokenForCurrentUser().ignore();
    if (wipeBiometrics) {
      BiometricAuthService.instance.disableAll().ignore();
    }
    _currentClient = null;
    _currentDriver = null;
    _currentPartner = null;
    _partnerRestaurant = null;
    _currentDriverStatus = DriverStatus.pending; // fail-safe default (anomalia #5)
    notifyListeners();
    _clearPersistedAccounts();
    _signOutBackground();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SharedPreferences persistence
  // ─────────────────────────────────────────────────────────────────────────

  // ── FIX: _initFromPrefs now RE-AUTHENTICATES with Supabase after
  // restoring a session from SharedPreferences. Previously it only
  // restored the local account objects without touching the Supabase
  // auth session. If the token had expired, _ensureGuestSession would
  // create a guest session, making auth.currentUser?.id return the
  // guest uid instead of the driver's real uid. This broke:
  //   - DriverStore.syncDriverWithAuth (wrong uid)
  //   - toggleAvailability (DB update on wrong row, 0 rows affected)
  //   - DispatchEngine.findEligibleDrivers (driver appears offline)
  //
  // Now: restore local state → re-auth with Supabase → guest only if
  // no real account was restored.
  Future<void> _initFromPrefs() async {
    // Declared outside try so the catch block can access it for role-aware
    // decisions about whether to create a guest session.
    String? roleStr;
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── Restore local account objects ─────────────────────────────────
      // SEC (2026-06-12) — a password vem do secure storage (Keystore);
      // o campo 'password' no JSON é LEGADO (instalações antigas) e, quando
      // presente, é migrado: re-persistimos a conta, o que grava a password
      // no secure storage e regrava o JSON sem ela.
      final clientJson = prefs.getString(_kClientAccount);
      if (clientJson != null) {
        try {
          final map = jsonDecode(clientJson) as Map<String, dynamic>;
          final email = map['email'] as String? ?? '';
          final legacyPassword = map['password'] as String? ?? '';
          var password = await SecureCredentialsStore.read('client');
          if (password.isEmpty) password = legacyPassword;
          final account = ClientAccount(
            name: map['name'] as String? ?? '',
            email: email,
            phone: map['phone'] as String? ?? '',
            password: password,
            photoUrl: map['photoUrl'] as String? ?? '',
          );
          if (email.isNotEmpty) _clientsByEmail[email] = account;
          if (legacyPassword.isNotEmpty) _persistClient(account);
        } catch (_) {}
      }

      final driverJson = prefs.getString(_kDriverAccount);
      if (driverJson != null) {
        final map = jsonDecode(driverJson) as Map<String, dynamic>;
        final phone = map['phone'] as String? ?? '';
        final email = map['email'] as String? ?? '';
        final legacyPassword = map['password'] as String? ?? '';
        var password = await SecureCredentialsStore.read('driver');
        if (password.isEmpty) password = legacyPassword;
        final account = DriverAccount(
          name: map['name'] as String? ?? '',
          email: email,
          phone: phone,
          // fromDb aceita nomes do enum e grafias legadas ('carPassengers').
          vehicleType:
              VehicleTypeDb.fromDb(map['vehicleType'] as String? ?? 'car'),
          licensePlate: map['licensePlate'] as String? ?? '',
          password: password,
          photoUrl: map['photoUrl'] as String? ?? '',
        );
        if (email.isNotEmpty) _driversByEmail[email] = account;
        if (phone.isNotEmpty) _driversByPhone[phone] = account;
        if (legacyPassword.isNotEmpty) _persistDriver(account);
      }

      final partnerJson = prefs.getString(_kPartnerAccount);
      if (partnerJson != null) {
        final map = jsonDecode(partnerJson) as Map<String, dynamic>;
        final email = map['email'] as String;
        final legacyPassword = map['password'] as String? ?? '';
        var password = await SecureCredentialsStore.read('partner');
        if (password.isEmpty) password = legacyPassword;
        final account = PartnerAccount(
          restaurantName: map['restaurantName'] as String,
          address: map['address'] as String,
          phone: map['phone'] as String,
          email: email,
          password: password,
          photoUrl: map['photoUrl'] as String? ?? '',
          cuisineType: map['cuisineType'] as String? ?? '',
        );
        _partnersByEmail[email] = account;
        if (legacyPassword.isNotEmpty) _persistPartner(account);
      }

      // ── Restore active session ────────────────────────────────────────
      roleStr = prefs.getString('bora_app.user_role');
      bool restoredRealSession = false;

      if (roleStr == 'driver' && driverJson != null) {
        final map = jsonDecode(driverJson) as Map<String, dynamic>;
        final email = map['email'] as String? ?? '';
        final phone = map['phone'] as String? ?? '';
        _currentDriver = _driversByEmail[email] ?? _driversByPhone[phone];
        // SEC — a conta já traz a password do secure storage (ou legada).
        final password = _currentDriver?.password ?? '';

        if (_currentDriver != null && email.isNotEmpty && password.isNotEmpty) {
          // ── FIX CRITICAL: Re-authenticate with Supabase so that
          // auth.currentUser?.id returns the DRIVER's real uid, not
          // the guest uid. Without this, DriverStore gets the wrong id,
          // toggleAvailability writes to the wrong DB row, and the
          // DispatchEngine never finds an online driver.
          final currentUid = _supabase.auth.currentUser?.id;
          final meta = _supabase.auth.currentUser?.userMetadata ?? {};
          final isAlreadyDriver = meta[_kRole] == 'driver' &&
              _supabase.auth.currentUser?.email == email;

          if (!isAlreadyDriver) {
            debugPrint(
                'AuthStore: restoring driver Supabase session for $email');
            try {
              await _supabase.auth.signInWithPassword(
                email: email,
                password: password,
              );
              debugPrint(
                  'AuthStore: driver session restored — uid=${_supabase.auth.currentUser?.id}');
              restoredRealSession = true;
            } catch (e) {
              debugPrint('AuthStore: driver session restore failed => $e');
              // Cannot verify driver identity — clear local state so
              // _RootNavigator routes to DriverLoginScreen.
              _currentDriver = null;
              // Sign out any partial/wrong session so auth.currentUser is
              // null, not a guest or other user's UID.
              try {
                await _supabase.auth.signOut();
              } catch (_) {}
            }
          } else {
            debugPrint(
                'AuthStore: Supabase already has driver session — uid=$currentUid');
            restoredRealSession = true;
          }
        }
      } else if (roleStr == 'client' && clientJson != null) {
        try {
          final map = jsonDecode(clientJson) as Map<String, dynamic>;
          final email = map['email'] as String? ?? '';
          _currentClient = _clientsByEmail[email];
          // SEC — a conta já traz a password do secure storage (ou legada).
          final password = _currentClient?.password ?? '';

          if (_currentClient != null &&
              email.isNotEmpty &&
              password.isNotEmpty) {
            final isAlreadyClient = _supabase.auth.currentUser?.email == email;
            if (!isAlreadyClient) {
              try {
                await _supabase.auth.signInWithPassword(
                  email: email,
                  password: password,
                );
                restoredRealSession = true;
              } catch (_) {}
            } else {
              restoredRealSession = true;
            }
          }
        } catch (_) {}
      } else if (roleStr == 'partner' && partnerJson != null) {
        final map = jsonDecode(partnerJson) as Map<String, dynamic>;
        final email = map['email'] as String;
        _currentPartner = _partnersByEmail[email];
        // SEC — a conta já traz a password do secure storage (ou legada).
        final password = _currentPartner?.password ?? '';

        if (_currentPartner != null &&
            email.isNotEmpty &&
            password.isNotEmpty) {
          final isAlreadyPartner = _supabase.auth.currentUser?.email == email;
          if (!isAlreadyPartner) {
            try {
              await _supabase.auth.signInWithPassword(
                email: email,
                password: password,
              );
              restoredRealSession = true;
            } catch (_) {}
          } else {
            restoredRealSession = true;
          }
        }
      }

      // Only fall back to guest session for client/anonymous flow.
      // Driver flow must NEVER use a guest UID — doing so makes
      // auth.currentUser?.id return a guest UUID instead of the driver's
      // real Supabase UID, which breaks DB queries, availability toggle,
      // and dispatch stream subscriptions.
      if (!restoredRealSession && roleStr != 'driver') {
        await _ensureGuestSession();
      }

      if (_currentClient != null ||
          _currentDriver != null ||
          _currentPartner != null) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AuthStore: _initFromPrefs error => $e');
      // Never create a guest session for driver role — it would make
      // auth.currentUser?.id return a guest UID, corrupting driverId.
      if (roleStr != 'driver') {
        await _ensureGuestSession();
      }
    }
  }

  void _persistClient(ClientAccount account) {
    // SEC — password no Keystore (write ignora vazias); JSON sem segredos.
    SecureCredentialsStore.write('client', account.password).ignore();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        _kClientAccount,
        jsonEncode({
          'email': account.email,
          'phone': account.phone,
          'name': account.name,
          'photoUrl': account.photoUrl,
        }),
      );
    });
  }

  void persistDriverFromSignup(DriverAccount account) {
    _currentDriver = account;
    _driversByEmail[account.email] = account;
    if (account.phone.isNotEmpty) _driversByPhone[account.phone] = account;
    _persistDriver(account);
    notifyListeners();
  }

  void _persistDriver(DriverAccount account) {
    // SEC — password no Keystore (write ignora vazias); JSON sem segredos.
    SecureCredentialsStore.write('driver', account.password).ignore();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        _kDriverAccount,
        jsonEncode({
          'email': account.email,
          'phone': account.phone,
          'name': account.name,
          'vehicleType': account.vehicleType.name,
          'licensePlate': account.licensePlate,
          'photoUrl': account.photoUrl,
        }),
      );
    });
  }

  void _persistPartner(PartnerAccount account) {
    // SEC — password no Keystore (write ignora vazias); JSON sem segredos.
    SecureCredentialsStore.write('partner', account.password).ignore();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        _kPartnerAccount,
        jsonEncode({
          'email': account.email,
          'restaurantName': account.restaurantName,
          'address': account.address,
          'phone': account.phone,
          'photoUrl': account.photoUrl,
          'cuisineType': account.cuisineType,
        }),
      );
    });
  }

  void _clearPersistedAccounts() {
    // SEC — limpa também as passwords no secure storage.
    SecureCredentialsStore.clearAll().ignore();
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_kClientAccount);
      prefs.remove(_kDriverAccount);
      prefs.remove(_kPartnerAccount);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
