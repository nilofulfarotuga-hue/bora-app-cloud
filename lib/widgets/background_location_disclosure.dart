import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';

/// Declaração em destaque (prominent disclosure) de LOCALIZAÇÃO EM SEGUNDO PLANO.
///
/// Google Play — "User Data / Consent request & Prominent disclosure": uma app
/// que acede a `ACCESS_BACKGROUND_LOCATION` tem de mostrar, DENTRO da app e
/// ANTES do acesso, uma declaração em destaque que:
///   • diz que recolhe localização;
///   • diz explicitamente que o faz mesmo quando a app está fechada / não em uso;
///   • indica a finalidade;
///   • exige uma ação afirmativa do utilizador para consentir.
///
/// O estafeta acede à localização em segundo plano porque o stream de GPS
/// (Geolocator, main isolate) continua enquanto está Online e a app está
/// minimizada — mantido vivo pelo foreground service. Por isso esta declaração
/// é mostrada antes de o estafeta ficar Online.
///
/// NÃO substitui o banner GDPR do [ConsentStore] (esse é consentimento
/// ePrivacy geral); esta é a disclosure específica exigida pela política de
/// localização em segundo plano do Google Play.
class BackgroundLocationDisclosure {
  static const String _kAccepted =
      'bora_app.bg_location_disclosure_accepted_v1';

  /// Garante que o utilizador viu e aceitou a declaração em destaque de
  /// localização em segundo plano antes de o rastreio começar.
  ///
  /// Devolve `true` se já tinha aceitado antes (sem mostrar nada) ou se aceita
  /// agora; `false` se recusa (nesse caso o chamador NÃO deve ficar Online).
  static Future<bool> ensureAccepted(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kAccepted) == true) return true;
    } catch (_) {
      // Falha a ler prefs → mostra a declaração à mesma (fail-safe: mais vale
      // mostrar uma vez a mais do que nunca declarar).
    }

    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const _DisclosureDialog(),
        ) ??
        false;

    if (accepted) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kAccepted, true);
      } catch (_) {
        // Aceitação em memória chega para esta sessão; volta a perguntar no
        // próximo arranque se a persistência falhar.
      }
    }
    return accepted;
  }
}

class _DisclosureDialog extends StatelessWidget {
  const _DisclosureDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      icon: const Icon(Icons.location_on, color: AppColors.primary, size: 40),
      title: const Text(
        'Localização em segundo plano',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'O Bora recolhe a tua localização — incluindo quando a app está '
              'fechada ou não está a ser usada — para:',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 10),
            _Bullet('mostrar a tua posição em tempo real ao cliente e à '
                'central durante entregas e corridas;'),
            _Bullet('te enviar pedidos e corridas próximos enquanto estás '
                'Online.'),
            SizedBox(height: 12),
            Text(
              'A recolha só acontece enquanto estás Online e para assim que '
              'ficas Offline. Podes recusar — só não vais poder ficar Online.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Aceitar e continuar'),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 14, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
