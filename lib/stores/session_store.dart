import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { client, driver, partner }

class SessionStore extends ChangeNotifier {
  static const _roleKey = 'bora_app.user_role';
  static const _homeStreetKey = 'bora_app.home_street';
  static const _homeCityKey = 'bora_app.home_city';
  static const _homeLatKey = 'bora_app.home_lat';
  static const _homeLngKey = 'bora_app.home_lng';

  UserRole? _role;
  bool _isInitialized = false;

  String? _homeStreet;
  String? _homeCity;
  double? _homeLat;
  double? _homeLng;

  UserRole? get role => _role;
  bool get isInitialized => _isInitialized;

  String? get homeStreet => _homeStreet;
  String? get homeCity => _homeCity;
  bool get hasHomeAddress => _homeStreet != null && _homeStreet!.isNotEmpty;
  LatLng? get homeLocation =>
      (_homeLat != null && _homeLng != null) ? LatLng(_homeLat!, _homeLng!) : null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _role = _stringToRole(prefs.getString(_roleKey));
    _homeStreet = prefs.getString(_homeStreetKey);
    _homeCity = prefs.getString(_homeCityKey);
    _homeLat = prefs.getDouble(_homeLatKey);
    _homeLng = prefs.getDouble(_homeLngKey);
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setHomeAddress({
    required String street,
    String city = '',
    LatLng? location,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeStreetKey, street);
    await prefs.setString(_homeCityKey, city);
    if (location != null) {
      await prefs.setDouble(_homeLatKey, location.latitude);
      await prefs.setDouble(_homeLngKey, location.longitude);
    } else {
      await prefs.remove(_homeLatKey);
      await prefs.remove(_homeLngKey);
    }
    _homeStreet = street;
    _homeCity = city;
    _homeLat = location?.latitude;
    _homeLng = location?.longitude;
    notifyListeners();
  }

  Future<void> clearHomeAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeStreetKey);
    await prefs.remove(_homeCityKey);
    await prefs.remove(_homeLatKey);
    await prefs.remove(_homeLngKey);
    _homeStreet = null;
    _homeCity = null;
    _homeLat = null;
    _homeLng = null;
    notifyListeners();
  }

  Future<void> setRole(UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.name);
    _role = role;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> clearRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    _role = null;
    _isInitialized = true;
    notifyListeners();
  }

  UserRole? _stringToRole(String? value) {
    if (value == null) return null;
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
} 