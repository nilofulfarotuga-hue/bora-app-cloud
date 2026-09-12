import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../stores/consent_store.dart';

import '../l10n/tr.dart';
import 'language_toggle.dart';

/// Wraps the whole app with a first-open privacy/cookies banner (BR §20.3).
///
/// Shows the banner as a modal sheet above [child] until the user answers.
/// The child is still present underneath so the app state builds up in the
/// background while the banner is on screen.
class ConsentBanner extends StatelessWidget {
  const ConsentBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Consumer<ConsentStore>(
      builder: (ctx, store, _) {
        return Stack(
          children: [
            child,
            if (!store.answered)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: _BannerSheet(store: store),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BannerSheet extends StatelessWidget {
  const _BannerSheet({required this.store});
  final ConsentStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // O alternador vive AQUI, e não só na home, porque este painel é
          // modal e aparece antes de tudo o resto: sem ele nesta linha, quem
          // não lê português ficava preso a decidir sobre privacidade num
          // idioma que não percebe.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Privacidade e Cookies'.tr,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const LanguageToggle(onDark: false),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A Bora usa dados para te entregar o serviço: localização do estafeta, análise de uso da app e notificações de pedidos. Podes aceitar tudo, rejeitar, ou escolher o que preferes.'.tr
                .tr,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: store.acceptAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Aceitar tudo'.tr,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: store.rejectAll,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Rejeitar'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _openPreferences(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Gerir preferências'.tr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openPreferences(BuildContext context) async {
    final result = await showDialog<_PrefsResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PreferencesDialog(),
    );
    if (result != null) {
      await store.savePreferences(
        location: result.location,
        analytics: result.analytics,
        notifications: result.notifications,
      );
    }
  }
}

class _PrefsResult {
  const _PrefsResult({
    required this.location,
    required this.analytics,
    required this.notifications,
  });
  final bool location;
  final bool analytics;
  final bool notifications;
}

class _PreferencesDialog extends StatefulWidget {
  const _PreferencesDialog();

  @override
  State<_PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<_PreferencesDialog> {
  bool _location = false;
  bool _analytics = false;
  bool _notifications = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Gerir preferências'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Localização'.tr),
            subtitle: Text(
                'Mostrar estafeta no mapa e calcular rotas em tempo real.'.tr),
            value: _location,
            onChanged: (v) => setState(() => _location = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Análise de uso'.tr),
            subtitle: Text('Ajuda-nos a melhorar a app.'.tr),
            value: _analytics,
            onChanged: (v) => setState(() => _analytics = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Notificações'.tr),
            subtitle: Text('Avisos de pedidos, entregas e reservas.'.tr),
            value: _notifications,
            onChanged: (v) => setState(() => _notifications = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const _PrefsResult(
            location: false,
            analytics: false,
            notifications: false,
          )),
          child: Text('Rejeitar tudo'.tr),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_PrefsResult(
            location: _location,
            analytics: _analytics,
            notifications: _notifications,
          )),
          child: Text('Guardar'.tr),
        ),
      ],
    );
  }
}
