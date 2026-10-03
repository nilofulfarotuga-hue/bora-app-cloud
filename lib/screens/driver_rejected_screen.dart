import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_accent_button.dart';
import 'driver_signup_screen.dart';

class DriverRejectedScreen extends StatelessWidget {
  const DriverRejectedScreen({super.key, this.reason = ''});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(Spacing.xxl),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cancel_rounded,
                  size: 72,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: Spacing.xxxl),
              const Text(
                'Candidatura rejeitada',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: Spacing.lg),
                Container(
                  padding: const EdgeInsets.all(Spacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          'Motivo: $reason',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Spacing.huge),
              BoraAccentButton(
                label: 'Submeter novamente',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const DriverSignupScreen()),
                ),
              ),
              const SizedBox(height: Spacing.md),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    context.read<AuthStore>().logout();
                    context.read<SessionStore>().clearRole();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(
                        color: AppColors.error, width: 1.5),
                  ),
                  child: const Text('Sair'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
