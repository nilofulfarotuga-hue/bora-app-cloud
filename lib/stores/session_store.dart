import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum UserRole { client, driver, partner }

class SessionStore extends ChangeNotifier {
  static const _roleKey = 'bora_app.user_role';

  UserRole? _role;
  bool _isInitialized = false;

  UserRole? get role => _role;
  bool get isInitialized => _isInitialized;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _role = _stringToRole(prefs.getString(_roleKey));
    _isInitialized = true;
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