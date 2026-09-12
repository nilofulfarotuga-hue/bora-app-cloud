// Sessão 5A-2 B11 — SupportSettingsProvider (3-state)
// Carrega support_settings on app start + refresh on AppLifecycleState.resumed.
// FAB lê este provider — kill switch instantâneo.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SupportSettingsState { loading, loaded, error }

class SupportSettingsProvider extends ChangeNotifier {
  SupportSettingsState _state = SupportSettingsState.loading;
  bool _supportAgentEnabled = false;
  String _whatsappNumber = '+351937501673';
  String _supportEmail = 'boraappbora@gmail.com';
  int _slaHours = 24;
  String? _lastError;

  SupportSettingsState get state => _state;
  bool get supportAgentEnabled => _supportAgentEnabled;
  String get whatsappNumber => _whatsappNumber;
  String get supportEmail => _supportEmail;
  int get slaHours => _slaHours;
  String? get lastError => _lastError;

  bool get shouldShowFab =>
      _state == SupportSettingsState.loaded ||
      _state == SupportSettingsState.error;

  bool get shouldShowAiCard =>
      _state == SupportSettingsState.loaded && _supportAgentEnabled;

  Future<void> load() async {
    if (_state == SupportSettingsState.loading) {
      // mantém loading até primeira resposta
    } else {
      _state = SupportSettingsState.loading;
      notifyListeners();
    }
    try {
      final row = await Supabase.instance.client
          .from('support_settings')
          .select(
              'whatsapp_number, support_email, sla_hours, support_agent_enabled')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) {
        _state = SupportSettingsState.error;
        _lastError = 'support_settings row missing';
      } else {
        _whatsappNumber =
            (row['whatsapp_number'] as String?) ?? _whatsappNumber;
        _supportEmail = (row['support_email'] as String?) ?? _supportEmail;
        _slaHours = (row['sla_hours'] as int?) ?? _slaHours;
        _supportAgentEnabled =
            (row['support_agent_enabled'] as bool?) ?? false;
        _state = SupportSettingsState.loaded;
        _lastError = null;
      }
    } catch (e) {
      _state = SupportSettingsState.error;
      _lastError = e.toString();
      debugPrint('[SupportSettingsProvider] load error: $e');
    }
    notifyListeners();
  }
}
