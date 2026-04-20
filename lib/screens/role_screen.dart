import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // ── Logo ──────────────────────────────────────────────────
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'BO',
                      style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 3,
                      ),
                    ),
                    TextSpan(
                      text: 'RA',
                      style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                        color: AppColors.accent,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.xs + 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.xl),
                ),
                child: const Text(
                  'Entregas rápidas em Portugal',
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // ── Buttons ───────────────────────────────────────────────
              BoraPrimaryButton(
                label: 'Sou Cliente',
                icon: Icons.person_outline,
                color: AppColors.primary,
                onPressed: () async {
                  final authStore = context.read<AuthStore>();
                  final sessionStore = context.read<SessionStore>();
                  authStore.logout();
                  await sessionStore.setRole(UserRole.client);
                },
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Sou Estafeta',
                icon: Icons.delivery_dining,
                color: AppColors.accent,
                onPressed: () async {
                  final authStore = context.read<AuthStore>();
                  final sessionStore = context.read<SessionStore>();
                  authStore.logout();
                  await sessionStore.setRole(UserRole.driver);
                },
              ),
              const SizedBox(height: Spacing.md),
              BoraPrimaryButton(
                label: 'Sou Parceiro',
                icon: Icons.storefront_outlined,
                color: AppColors.info,
                onPressed: () async {
                  final authStore = context.read<AuthStore>();
                  final sessionStore = context.read<SessionStore>();
                  authStore.logout();
                  await sessionStore.setRole(UserRole.partner);
                },
              ),

              const Spacer(flex: 1),
              const Text(
                'v1.0 · boraappbora@gmail.com',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
