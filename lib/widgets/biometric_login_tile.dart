import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/biometric_auth_service.dart';

import '../l10n/tr.dart';

/// L3.5 (2026-06-12) — SwitchListTile "Login com biometria" para o Perfil/
/// Definições de cada papel.
/// - Aparelho sem biometria configurada → o tile esconde-se (L3.6).
/// - Ligar: pede a digital/rosto e guarda a sessão ATUAL em secure storage
///   (por isso só faz sentido em ecrãs onde o utilizador está autenticado).
/// - Desligar: apaga o token biométrico do papel.
class BiometricLoginTile extends StatefulWidget {
  const BiometricLoginTile({super.key, required this.role, this.margin});

  /// 'client' | 'driver' | 'partner'
  final String role;

  /// Margem do Card envolvente — por defeito alinha com as gutters de 16
  /// usadas nos ecrãs de perfil/dashboard.
  final EdgeInsetsGeometry? margin;

  @override
  State<BiometricLoginTile> createState() => _BiometricLoginTileState();
}

class _BiometricLoginTileState extends State<BiometricLoginTile> {
  bool _capable = false;
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bio = BiometricAuthService.instance;
    final capable = await bio.isDeviceCapable;
    final enabled = capable && await bio.isEnabledFor(widget.role);
    if (!mounted) return;
    setState(() {
      _capable = capable;
      _enabled = enabled;
    });
  }

  Future<void> _toggle(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final bio = BiometricAuthService.instance;
    final messenger = ScaffoldMessenger.of(context);

    if (value) {
      final ok = await bio.authenticate(
          'Confirma a tua identidade para ativar o login com biometria'.tr);
      final saved = ok && await bio.enableForCurrentSession(widget.role);
      if (saved) await bio.markAsked(widget.role);
      if (!mounted) return;
      setState(() {
        _enabled = saved;
        _busy = false;
      });
      if (!saved) {
        messenger.showSnackBar(SnackBar(
          content: Text('Não foi possível ativar o login com biometria.'.tr),
        ));
      }
    } else {
      await bio.disableFor(widget.role);
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_capable) return const SizedBox.shrink();
    return Card(
      margin: widget.margin ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwitchListTile(
        secondary: const Icon(Icons.fingerprint, color: AppColors.primary),
        title: Text('Login com biometria'.tr),
        subtitle:
            Text('Entra com a digital ou rosto, sem palavra-passe'.tr),
        value: _enabled,
        onChanged: _busy ? null : _toggle,
      ),
    );
  }
}
