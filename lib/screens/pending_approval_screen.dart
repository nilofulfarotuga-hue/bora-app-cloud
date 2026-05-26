import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'partner_login_screen.dart';

/// Tela mostrada APÓS parceiro submeter o signup com sucesso.
/// Status: ⏳ Pendente de aprovação admin (análise típica 24-48h).
///
/// Correcção Sessão 2026-05-26:
/// - Botão "Gerir a minha loja" leva direto ao painel partner (com badge "Pendente")
/// - Não apenas "Voltar ao Login"
class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionStore = context.watch<SessionStore>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Spacing.xxl),
              // Ícone de sucesso
              const Icon(
                Icons.hourglass_bottom_rounded,
                size: 72,
                color: AppColors.accent,
              ),
              const SizedBox(height: Spacing.xl),

              // Título
              Text(
                'Submetido para Análise',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: Spacing.lg),

              // Subtítulo
              Text(
                'Obrigado por se registar!',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: Spacing.xl),

              // Card com detalhes
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outlined,
                            size: 20,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              'O teu restaurante está sob análise',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        'Verificaremos os teus documentos e dados (24-48h típico).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        'Receberás uma notificação assim que formos aprovados.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.xxl),

              // Botão: Gerir a minha loja
              BoraPrimaryButton(
                label: 'Gerir a Minha Loja',
                color: AppColors.primary,
                onPressed: () {
                  sessionStore.setRole(UserRole.partner);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
              const SizedBox(height: Spacing.md),

              // Botão secundário: Voltar ao Login
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const PartnerLoginScreen(),
                    ),
                  );
                },
                child: const Text('Voltar ao Login'),
              ),

              const SizedBox(height: Spacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
