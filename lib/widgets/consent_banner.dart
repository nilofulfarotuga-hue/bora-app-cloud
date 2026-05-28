import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../stores/consent_store.dart';

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
          const Text(
            'Privacidade e Cookies',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'A Bora usa dados para te entregar o serviço: localização do '
            'estafeta, análise de uso da app e notificações de pedidos. '
            'Podes aceitar tudo, rejeitar, ou escolher o que preferes.',
            style: TextStyle(fontSize: 14, color: Colors.black87),
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
              child: const Text('Aceitar tudo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                  child: const Text('Rejeitar'),
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
                  child: const Text('Gerir preferências'),
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
      title: const Text('Gerir preferências'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Localização'),
            subtitle: const Text(
                'Mostrar estafeta no mapa e calcular rotas em tempo real.'),
            value: _location,
            onChanged: (v) => setState(() => _location = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Análise de uso'),
            subtitle: const Text('Ajuda-nos a melhorar a app.'),
            value: _analytics,
            onChanged: (v) => setState(() => _analytics = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notificações'),
            subtitle: const Text(
                'Avisos de pedidos, entregas e reservas.'),
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
          child: const Text('Rejeitar tudo'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_PrefsResult(
            location: _location,
            analytics: _analytics,
            notifications: _notifications,
          )),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
