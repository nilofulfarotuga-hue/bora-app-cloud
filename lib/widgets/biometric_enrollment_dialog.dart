import 'package:flutter/material.dart';

import '../services/biometric_auth_service.dart';

import '../l10n/tr.dart';

/// L3.2 (2026-06-12) — pergunta UMA vez, logo após um login com
/// palavra-passe bem-sucedido: "Queres entrar com a tua digital/rosto da
/// próxima vez?". Chamar ANTES de setRole (o ecrã de login ainda está vivo).
///
/// - Aparelho sem biometria configurada → nunca pergunta (L3.6).
/// - Biometria já ativa para o papel → apenas re-vincula à conta que acabou
///   de entrar (mantém o token atual; cobre troca de conta no mesmo papel).
/// - Recusa ("Agora não") → não volta a perguntar; o toggle no perfil fica
///   como caminho para ativar mais tarde.
Future<void> maybeOfferBiometricEnrollment(
  BuildContext context,
  String role,
) async {
  final bio = BiometricAuthService.instance;
  if (!await bio.isDeviceCapable) return;

  if (await bio.isEnabledFor(role)) {
    await bio.enableForCurrentSession(role);
    return;
  }

  if (await bio.wasAsked(role)) return;
  await bio.markAsked(role);

  if (!context.mounted) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Entrar com biometria?'.tr),
      content: Text(
        'Queres entrar com a tua digital ou rosto da próxima vez? Podes ligar ou desligar isto no perfil quando quiseres.'.tr,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Agora não'.tr),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Ativar'.tr),
        ),
      ],
    ),
  );
  if (accepted != true) return;

  final ok = await bio.authenticate(
    'Confirma a tua identidade para ativar o login com biometria'.tr,
  );
  if (!ok) return;

  final saved = await bio.enableForCurrentSession(role);
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Login com biometria ativado.'.tr)),
    );
  }
}
