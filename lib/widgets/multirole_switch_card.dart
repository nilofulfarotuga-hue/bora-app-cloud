import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/roles_service.dart';

import '../l10n/tr.dart';

/// MULTI-PAPEL — card de convite/troca para o OUTRO papel (estafeta ⇄ limpeza).
/// Reutilizável nos dois lados. O texto e a ação dependem do estado do outro
/// papel (via [crossRoleStateFor]): convidar / em análise / abrir-trocar.
class MultiRoleSwitchCard extends StatelessWidget {
  const MultiRoleSwitchCard({
    super.key,
    required this.icon,
    required this.otherStatus,
    required this.inviteTitle,
    required this.inviteSubtitle,
    required this.activeTitle,
    required this.pendingTitle,
    required this.onInvite,
    required this.onOpen,
  });

  final IconData icon;

  /// `approval_status` do outro papel (null = ainda não tem).
  final String? otherStatus;
  final String inviteTitle;
  final String inviteSubtitle;
  final String activeTitle;
  final String pendingTitle;

  /// Candidatar-se ao outro papel (estado invite).
  final VoidCallback onInvite;

  /// Abrir/trocar para o outro papel já aprovado (estado active).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final state = crossRoleStateFor(otherStatus);
    final (title, subtitle, onTap, showChevron) = switch (state) {
      CrossRoleCardState.invite => (
          inviteTitle,
          inviteSubtitle,
          onInvite,
          true,
        ),
      CrossRoleCardState.active => (
          activeTitle,
          'Toca para abrir.'.tr,
          onOpen,
          true,
        ),
      CrossRoleCardState.pending => (
          pendingTitle,
          'Candidatura em análise pela equipa Bora.'.tr,
          null,
          false,
        ),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.primaryWash,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5,
                          height: 1.3)),
                ],
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
