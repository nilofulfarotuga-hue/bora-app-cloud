import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/driver_model.dart';
import '../models/restaurant_model.dart';

enum AuthRole { client, driver, partner }

class ClientAccount {
  const ClientAccount({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
  });

  final String name;
  final String email;
  final String phone;
  final String password;
}

class DriverAccount {
  const DriverAccount({
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicleType,
    required this.licensePlate,
    required this.password,
  });

  final String name;
  final String email;
  final String phone;
  final VehicleType vehicleType;
  final String licensePlate;
  final String password;
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
    _ensureAnonymousSession();
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

  RestaurantModel? get partnerRestaurant => _partnerRestaurant;

  void setPartnerRestaurant(RestaurantModel restaurant) {
    _partnerRestaurant = restaurant;
    notifyListeners();
  }

  bool get isLogged =>
      _currentClient != null ||
      _currentDriver != null ||
      _currentPartner != null;

  /// Alias for [isLogged] — convenience for callers that prefer this name.
  bool get isLoggedIn => isLogged;

  /// Supabase Auth user ID — available for both real and anonymous sessions.
  String? get userId => _supabase.auth.currentUser?.id;

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

  bool get hasClientAccounts => _clientsByEmail.isNotEmpty;
  bool get hasDriverAccounts => _driversByEmail.isNotEmpty;
  bool get hasPartnerAccounts => _partnersByEmail.isNotEmpty;

  void _onAuthStateChange(AuthState state) {
    final session = state.session;

    if (session == null) {
      _currentClient = null;
      _currentDriver = null;
      _currentPartner = null;
      _partnerRestaurant = null;
      notifyListeners();
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
        debugPrint('AuthStore: unknown bora_role "$boraRole"');
    }
  }

  Future<void> _ensureAnonymousSession() async {
    if (_supabase.auth.currentUser != null) return;
    try {
      await _supabase.auth.signInAnonymously();
      debugPrint('AuthStore: anonymous session created');
    } catch (e) {
      debugPrint('AuthStore: anonymous sign-in error => $e');
    }
  }

  Future<void> _signUpBackground({
    required String email,
    required String password,
    required Map<String, dynamic> data,
    required String tag,
  }) async {
    try {
      await _supabase.auth.signUp(email: email, password: password, data: data);
      debugPrint('AuthStore: $tag signed up');
    } catch (e) {
      debugPrint('AuthStore: $tag signUp error => $e');
    }
  }

  Future<void> _signInBackground({
    required String email,
    required String password,
    required String tag,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      debugPrint('AuthStore: $tag token refreshed');
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
    _signUpBackground(
      email: normalizedEmail,
      password: password,
      data: {_kRole: 'client', _kName: name.trim(), _kPhone: phone.trim()},
      tag: 'client',
    );
    return null;
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

    final local = _clientsByEmail[normalizedEmail];
    if (local != null && local.password == password) {
      _currentClient = local;
      _currentDriver = null;
      _currentPartner = null;
      notifyListeners();
      _persistClient(local);
      _signInBackground(
          email: normalizedEmail,
          password: password,
          tag: 'loginClientAsync-local');
      return true;
    }

    try {
      final res = await _supabase.auth
          .signInWithPassword(email: normalizedEmail, password: password);
      final user = res.user;
      if (user == null) return false;

      final meta = user.userMetadata ?? {};
      if ((meta[_kRole] as String?) != 'client') return false;

      final account = ClientAccount(
        name: meta[_kName] as String? ?? '',
        email: normalizedEmail,
        phone: meta[_kPhone] as String? ?? '',
        password: password,
      );
      _currentClient = account;
      _currentDriver = null;
      _currentPartner = null;
      notifyListeners();
      _clientsByEmail[normalizedEmail] = account;
      _persistClient(account);
      return true;
    } catch (e) {
      debugPrint('AuthStore: loginClientAsync error => $e');
      return false;
    }
  }

  // ─── Driver ───────────────────────────────────────────────────────────────

  /// Register a new driver account via Supabase Auth.
  /// Returns null on success or an error message string.
  Future<String?> registerDriverAsync({
    required String name,
    required String email,
    required String phone,
    required VehicleType vehicleType,
    required String licensePlate,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = phone.trim();

    if (name.trim().isEmpty || normalizedEmail.isEmpty || password.isEmpty) {
      return 'Preencha todos os campos obrigatórios.';
    }
    if (_driversByEmail.containsKey(normalizedEmail)) {
      return 'Já existe uma conta com este email.';
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
        },
      );

      final user = res.user;
      if (user == null) {
        return 'Não foi possível criar a conta. Tente novamente.';
      }

      // Upsert into drivers table using the real auth user ID.
      try {
        await _supabase.from('drivers').upsert({
          'id': user.id,
          'name': name.trim(),
          'phone': normalizedPhone,
          'email': normalizedEmail,
          'vehicle_type': vehicleType.name,
          'license_plate': licensePlate.trim(),
          'is_online': false,
          'lat': 38.7223,
          'lng': -9.1393,
        });
      } catch (e) {
        debugPrint(
            'AuthStore: registerDriverAsync - drivers upsert error => $e');
        // Non-fatal: auth created, continue.
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
      if (normalizedPhone.isNotEmpty) _driversByPhone[normalizedPhone] = account;
      _currentDriver = account;
      _currentClient = null;
      _currentPartner = null;
      notifyListeners();
      _persistDriver(account);
      return null;
    } on AuthException catch (e) {
      debugPrint('AuthStore: registerDriverAsync AuthException => ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('AuthStore: registerDriverAsync error => $e');
      return 'Erro ao criar conta. Tente novamente.';
    }
  }

  /// Login with email + password (aligned with client/partner flow).
  Future<bool> loginDriverAsync(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();

    // Check local memory first (includes demo account).
    final local = _driversByEmail[normalizedEmail];
    if (local != null && local.password == password) {
      _currentDriver = local;
      _currentClient = null;
      _currentPartner = null;
      notifyListeners();
      _signInBackground(
          email: normalizedEmail,
          password: password,
          tag: 'loginDriverAsync-local');
      return true;
    }

    try {
      final res = await _supabase.auth
          .signInWithPassword(email: normalizedEmail, password: password);
      final user = res.user;
      if (user == null) return false;

      final meta = user.userMetadata ?? {};
      if ((meta[_kRole] as String?) != 'driver') return false;

      final vtStr = meta[_kVehicleType] as String? ?? 'car';
      final phone = meta[_kPhone] as String? ?? '';
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
      _currentClient = null;
      _currentPartner = null;
      notifyListeners();
      _driversByEmail[normalizedEmail] = account;
      if (phone.isNotEmpty) _driversByPhone[phone] = account;
      _persistDriver(account);
      return true;
    } catch (e) {
      debugPrint('AuthStore: loginDriverAsync error => $e');
      return false;
    }
  }

  /// Sends a password-reset email for the given driver email.
  Future<void> resetDriverPassword(String email) async {
    try {
      await _supabase.auth
          .resetPasswordForEmail(email.trim().toLowerCase());
      debugPrint('AuthStore: password reset email sent to $email');
    } catch (e) {
      debugPrint('AuthStore: resetDriverPassword error => $e');
    }
  }

  // Legacy sync login kept for backward compat (checks by phone).
  bool loginDriver(String phone, String password) {
    final account = _driversByPhone[phone.trim()];
    if (account == null || account.password != password) return false;
    _currentDriver = account;
    _currentClient = null;
    _currentPartner = null;
    notifyListeners();
    _persistDriver(account);
    _signInBackground(
        email: account.email,
        password: password,
        tag: 'loginDriver');
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
    _signUpBackground(
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
      },
      tag: 'partner',
    );
    return null;
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
    _currentClient = null;
    _currentDriver = null;
    _currentPartner = null;
    _partnerRestaurant = null;
    notifyListeners();
    _clearPersistedAccounts();
    _signOutBackground();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SharedPreferences persistence
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

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

      // Restore active session based on the role persisted by SessionStore.
      final roleStr = prefs.getString('bora_app.user_role');
      if (roleStr == 'client' && clientJson != null) {
        try {
          final email =
              (jsonDecode(clientJson) as Map<String, dynamic>)['email']
                  as String? ??
                  '';
          _currentClient = _clientsByEmail[email];
        } catch (_) {}
      } else if (roleStr == 'driver' && driverJson != null) {
        final map = jsonDecode(driverJson) as Map<String, dynamic>;
        final email = map['email'] as String? ?? '';
        final phone = map['phone'] as String? ?? '';
        _currentDriver = _driversByEmail[email] ?? _driversByPhone[phone];
      } else if (roleStr == 'partner' && partnerJson != null) {
        final email =
            (jsonDecode(partnerJson) as Map<String, dynamic>)['email'] as String;
        _currentPartner = _partnersByEmail[email];
      }

      if (clientJson != null || driverJson != null || partnerJson != null) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AuthStore: _initFromPrefs error => $e');
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
        }),
      );
    });
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
