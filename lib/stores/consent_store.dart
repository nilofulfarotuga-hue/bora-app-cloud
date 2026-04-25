import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/location_service.dart';
import '../services/notification_service.dart';

/// Persistent store for GDPR/ePrivacy consent choices (BR §20.3).
///
/// The banner shown on first app open lets the user choose between:
///   • Accept all
///   • Reject
///   • Manage preferences (3 fine-grained toggles)
///
/// Covered trackings:
///   • location       — background location / geolocator
///   • analytics      — usage analytics
///   • notifications  — push notifications
///
/// Technical enforcement: opt-out disables FCM token persistence and blocks OS
/// location permission requests via service-level flags ([NotificationService]
/// and [LocationService]).
class ConsentStore extends ChangeNotifier {
  /// Current consent schema version. Bump to re-prompt all users after a
  /// material change in the banner text or scope.
  static const String currentVersion = '1.0';

  static const _kAnswered = 'bora_app.consent_answered';
  static const _kVersion = 'bora_app.consent_version';
  static const _kLocation = 'bora_app.consent_location';
  static const _kAnalytics = 'bora_app.consent_analytics';
  static const _kNotifications = 'bora_app.consent_notifications';

  bool _answered = false;
  bool _locationConsent = false;
  bool _analyticsConsent = false;
  bool _notificationsConsent = false;

  bool get answered => _answered;
  bool get locationConsent => _locationConsent;
  bool get analyticsConsent => _analyticsConsent;
  bool get notificationsConsent => _notificationsConsent;

  /// Loads the previously-saved choice from SharedPreferences. On error, the
  /// store fails open (answered = true) so a platform failure never blocks
  /// the app behind the banner.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getString(_kVersion);
      final answered = prefs.getBool(_kAnswered) ?? false;

      if (!answered || savedVersion != currentVersion) {
        _answered = false;
        _locationConsent = false;
        _analyticsConsent = false;
        _notificationsConsent = false;
      } else {
        _answered = true;
        _locationConsent = prefs.getBool(_kLocation) ?? false;
        _analyticsConsent = prefs.getBool(_kAnalytics) ?? false;
        _notificationsConsent = prefs.getBool(_kNotifications) ?? false;
      }
    } catch (_) {
      // Fail open — never block the UI because of a platform hiccup.
      _answered = true;
    }

    // Apply saved consent to services so enforcement survives app restarts.
    if (_answered) {
      NotificationService.instance.applyNotificationConsent(_notificationsConsent);
      LocationService.applyLocationConsent(_locationConsent);
    }

    notifyListeners();
  }

  Future<void> acceptAll() => _persist(
        location: true,
        analytics: true,
        notifications: true,
      );

  Future<void> rejectAll() => _persist(
        location: false,
        analytics: false,
        notifications: false,
      );

  Future<void> savePreferences({
    required bool location,
    required bool analytics,
    required bool notifications,
  }) =>
      _persist(
        location: location,
        analytics: analytics,
        notifications: notifications,
      );

  Future<void> _persist({
    required bool location,
    required bool analytics,
    required bool notifications,
  }) async {
    _locationConsent = location;
    _analyticsConsent = analytics;
    _notificationsConsent = notifications;
    _answered = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAnswered, true);
      await prefs.setString(_kVersion, currentVersion);
      await prefs.setBool(_kLocation, location);
      await prefs.setBool(_kAnalytics, analytics);
      await prefs.setBool(_kNotifications, notifications);
    } catch (_) {
      // Notify listeners anyway — the in-memory choice holds until next launch.
    }

    // Enforce consent choices technically so the user's choice takes effect
    // immediately without requiring an app restart.
    NotificationService.instance.applyNotificationConsent(notifications);
    LocationService.applyLocationConsent(location);

    notifyListeners();
  }
}
