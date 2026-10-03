import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/role_switch_helper.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_mascot.dart';

import '../l10n/tr.dart';

/// MULTI-PAPEL (2026-08-05) — mostrado logo após o login quando `my_roles()`
/// devolve mais do que um papel utilizável (ex.: mr.kebab@bora.app é parceiro
/// E cliente). Depois de escolher, dá para trocar outra vez em Perfil (botão
/// "Trocar de perfil"), sempre sem fazer logout.
class RoleChoiceScreen extends StatefulWidget {
  const RoleChoiceScreen({super.key, required this.roles});

  final List<Map<String, dynamic>> roles;

  @override
  State<RoleChoiceScreen> createState() => _RoleChoiceScreenState();
}

class _RoleChoiceScreenState extends State<RoleChoiceScreen> {
  bool _isProcessing = false;

  Future<void> _choose(UserRole role) async {
    setState(() => _isProcessing = true);
    final ok = await activateRole(context, role);
    if (!mounted) return;
    if (!ok) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível entrar nesse perfil. Tenta novamente.'.tr),
        ),
      );
      return;
    }
    // _RootNavigator observa o SessionStore e troca de ecrã sozinho.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Center(
                child: BoraMascot(
                  variant: BoraMascotVariant.logo,
                  size: 64,
                  semanticLabel: 'BORA',
                ),
              ),
              const SizedBox(height: Spacing.xl),
              Text(
                'Como queres entrar?'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                'Esta conta tem mais do que um perfil no Bora. Depois dá para trocar em Perfil, sem sair da conta.'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: Spacing.xxl),
              for (final r in widget.roles)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: _RoleButton(
                    role: r,
                    enabled: !_isProcessing,
                    onTap: _choose,
                  ),
                ),
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.only(top: Spacing.md),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  const _RoleButton({
    required this.role,
    required this.enabled,
    required this.onTap,
  });

  final Map<String, dynamic> role;
  final bool enabled;
  final ValueChanged<UserRole> onTap;

  @override
  Widget build(BuildContext context) {
    final roleStr = role['role'] as String?;
    final uiRole = uiRoleFor(roleStr);
    if (uiRole == null) return const SizedBox.shrink();
    final (statusText, statusEnabled) =
        roleStatusLabel(role['approval_status'] as String?);
    final canTap = enabled && statusEnabled;

    return OutlinedButton.icon(
      onPressed: canTap ? () => onTap(uiRole) : null,
      icon: Icon(roleIcon(roleStr)),
      label: Text(
        statusText.isEmpty ? roleLabel(roleStr) : '${roleLabel(roleStr)} · $statusText',
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}
