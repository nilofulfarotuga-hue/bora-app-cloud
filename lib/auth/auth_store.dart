import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/driver_model.dart';
import '../models/restaurant_model.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

enum AuthRole { client, driver, partner }

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
    _clientsByEmail['cliente@bora.app'] = const ClientAccount(
      name: 'Cliente Demo',
      email: 'cliente@bora.app',
      phone: '910000001',
      password: '123456',
    );

    const driverDemo = DriverAccount(
      name: 'Estafeta Demo',
      email: 'driver@bora.app',
      phone: '910000000',
      vehicleType: VehicleType.car,
      licensePlate: 'AB-12-CD',
      password: '123456',
    );
    _driversByEmail['driver@bora.app'] = driverDemo;
    _driversByPhone['910000000'] = driverDemo;

    _authSubscription =
        _supabase.auth.onAuthStateChange.listen(_onAuthStateChange);

    _initFromPrefs();
    // Guest session is deferred — _initFromPrefs may re-auth as real user first.
  }

  final _supabase = Supabase.instance.client;
  StreamSubscription<AuthState>? _authSubscription;

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
          .eq('id', uid)
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

    if (_currentClient != null ||
        _currentDriver != null ||
        _currentPartner != null) {
      return;
    }

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
          vehicleType: VehicleType.values.firstWhere(
            (v) => v.name == vtStr,
            orElse: () => VehicleType.car,
          ),
          licensePlate: meta[_kLicensePlate] as String? ?? '',
          password: '',
        );
        _driversByEmail[email] = account;
        if (phone.isNotEmpty) _driversByPhone[phone] = account;
        _currentDriver = account;
        notifyListeners();
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
          'vehicle_type': vehicleType.name,
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
      try {
        final row = await _supabase
            .from('drivers')
            .select('approval_status')
            .eq('id', user.id)
            .maybeSingle();
        final statusStr = row?['approval_status'] as String? ?? 'approved';
        driverStatus = DriverStatus.values.firstWhere(
          (s) => s.name == statusStr,
          orElse: () => DriverStatus.approved,
        );
      } catch (_) {}

      final account = DriverAccount(
        name: meta[_kName] as String? ?? '',
        email: normalizedEmail,
        phone: phone,
        vehicleType: VehicleType.values.firstWhere(
          (v) => v.name == vtStr,
          orElse: () => VehicleType.car,
        ),
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

  Future<void> resetDriverPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email.trim().toLowerCase());
    } catch (e) {
      debugPrint('AuthStore: resetDriverPassword error => $e');
    }
  }

  /// Generic password-reset email — works for any role (partner + driver).
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email.trim().toLowerCase());
    } catch (e) {
      debugPrint('AuthStore: resetPassword error => $e');
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
      // Surface Supabase errors (e.g. "User already registered") as-is.
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
      return null; // Erro já foi retornado ao caller
    }

    // Step 2: Invoca Edge Function register-partner c/ service_role
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
        },
      );

      if (response.status != 201) {
        debugPrint('[AuthStore] register-partner EF returned ${response.status}: ${response.data}');
        return null;
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      return {
        'restaurant_id': data['restaurant_id'],
        'approval_status': data['status'],
        'message': data['message'],
      };
    } catch (e) {
      debugPrint('[AuthStore] registerPartnerWithDocumentsAsync: register-partner EF failed => $e');
      return null;
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
      _signInBackground(
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

  void logout() {
    // Clear FCM binding BEFORE wiping state so the previous user stops
    // receiving pushes on this device. Fire-and-forget — logout must not
    // block on network failure.
    NotificationService.instance.clearTokenForCurrentUser().ignore();
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
      final clientJson = prefs.getString(_kClientAccount);
      if (clientJson != null) {
        try {
          final map = jsonDecode(clientJson) as Map<String, dynamic>;
          final email = map['email'] as String? ?? '';
          final account = ClientAccount(
            name: map['name'] as String? ?? '',
            email: email,
            phone: map['phone'] as String? ?? '',
            password: map['password'] as String? ?? '',
            photoUrl: map['photoUrl'] as String? ?? '',
          );
          if (email.isNotEmpty) _clientsByEmail[email] = account;
        } catch (_) {}
      }

      final driverJson = prefs.getString(_kDriverAccount);
      if (driverJson != null) {
        final map = jsonDecode(driverJson) as Map<String, dynamic>;
        final phone = map['phone'] as String? ?? '';
        final email = map['email'] as String? ?? '';
        final account = DriverAccount(
          name: map['name'] as String? ?? '',
          email: email,
          phone: phone,
          vehicleType: VehicleType.values.firstWhere(
            (v) => v.name == (map['vehicleType'] as String? ?? 'car'),
            orElse: () => VehicleType.car,
          ),
          licensePlate: map['licensePlate'] as String? ?? '',
          password: map['password'] as String? ?? '',
          photoUrl: map['photoUrl'] as String? ?? '',
        );
        if (email.isNotEmpty) _driversByEmail[email] = account;
        if (phone.isNotEmpty) _driversByPhone[phone] = account;
      }

      final partnerJson = prefs.getString(_kPartnerAccount);
      if (partnerJson != null) {
        final map = jsonDecode(partnerJson) as Map<String, dynamic>;
        final email = map['email'] as String;
        final account = PartnerAccount(
          restaurantName: map['restaurantName'] as String,
          address: map['address'] as String,
          phone: map['phone'] as String,
          email: email,
          password: map['password'] as String,
          photoUrl: map['photoUrl'] as String,
          cuisineType: map['cuisineType'] as String,
        );
        _partnersByEmail[email] = account;
      }

      // ── Restore active session ────────────────────────────────────────
      roleStr = prefs.getString('bora_app.user_role');
      bool restoredRealSession = false;

      if (roleStr == 'driver' && driverJson != null) {
        final map = jsonDecode(driverJson) as Map<String, dynamic>;
        final email = map['email'] as String? ?? '';
        final password = map['password'] as String? ?? '';
        final phone = map['phone'] as String? ?? '';
        _currentDriver = _driversByEmail[email] ?? _driversByPhone[phone];

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
          final password = map['password'] as String? ?? '';
          _currentClient = _clientsByEmail[email];

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
        final password = map['password'] as String? ?? '';
        _currentPartner = _partnersByEmail[email];

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
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        _kClientAccount,
        jsonEncode({
          'email': account.email,
          'phone': account.phone,
          'name': account.name,
          'password': account.password,
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
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        _kDriverAccount,
        jsonEncode({
          'email': account.email,
          'phone': account.phone,
          'name': account.name,
          'vehicleType': account.vehicleType.name,
          'licensePlate': account.licensePlate,
          'password': account.password,
          'photoUrl': account.photoUrl,
        }),
      );
    });
  }

  void _persistPartner(PartnerAccount account) {
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
          'password': account.password,
        }),
      );
    });
  }

  void _clearPersistedAccounts() {
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
