import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/partner_appointments_store.dart';
import '../stores/restaurant_store.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_primary_button.dart';
import 'partner_login_screen.dart';

/// Tela mostrada APÓS parceiro submeter o signup com sucesso.
/// Status: ⏳ Pendente de aprovação admin (análise típica 24-48h).
///
/// Correcção Sessão 2026-05-26:
/// - Botão "Gerir a minha loja" leva direto ao painel partner (com badge "Pendente")
/// - Não apenas "Voltar ao Login"
///
/// Correcção 2026-07-18 (BUG parceiro-serviços preso neste ecrã pós-aprovação):
/// - O botão nunca confiava num valor local — agora reconsulta sempre o
///   `approval_status` fresco (service_providers ou restaurants, conforme a
///   categoria) antes de decidir se navega para o painel ou se avisa que
///   ainda está em análise/foi recusado.
class PendingApprovalScreen extends StatefulWidget {
  /// Nome da categoria escolhida no registo (`BusinessCategory.name`: restaurant,
  /// store, pharmacy, supermarket, beauty). Usado só para o texto refletir o tipo
  /// de negócio. Null → texto genérico ("O teu negócio").
  final String? categoryName;

  const PendingApprovalScreen({super.key, this.categoryName});

  /// PT-PT: "O teu salão / A tua loja / …" conforme a categoria.
  static String _businessNoun(String? category) {
    switch (category) {
      case 'beauty':
        return 'O teu salão';
      case 'store':
        return 'A tua loja';
      case 'pharmacy':
        return 'A tua farmácia';
      case 'supermarket':
        return 'O teu supermercado';
      case 'restaurant':
        return 'O teu restaurante';
      default:
        return 'O teu negócio';
    }
  }

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _isChecking = false;

  /// Reconsulta o estado de aprovação FRESCO (nunca confia num valor local
  /// antigo) e só navega para o painel de gestão se estiver realmente
  /// aprovado. Se ainda pending/rejected, avisa e mantém o utilizador aqui.
  Future<void> _handleManageStore() async {
    setState(() => _isChecking = true);

    try {
      final isRestaurant =
          widget.categoryName == null || widget.categoryName == 'restaurant';

      String? status;
      if (isRestaurant) {
        final userId = context.read<AuthStore>().userId;
        if (userId != null) {
          status =
              await context.read<RestaurantStore>().ownRestaurantApprovalStatus(userId);
        }
      } else {
        final provider = await context
            .read<PartnerAppointmentsStore>()
            .loadMyProvider(force: true);
        status = provider?.approvalStatus;
      }

      if (!mounted) return;

      if (status == 'approved') {
        await context.read<SessionStore>().setRole(UserRole.partner);
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      setState(() => _isChecking = false);
      final message = status == 'rejected'
          ? 'A candidatura foi recusada. Contacta o suporte para mais informação.'
          : 'Ainda em análise. Tenta novamente dentro de algum tempo.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível verificar o estado. Tenta novamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryName = widget.categoryName;

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
                              '${PendingApprovalScreen._businessNoun(categoryName)} está sob análise',
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
                label: _isChecking ? 'A verificar...' : 'Gerir a Minha Loja',
                color: AppColors.primary,
                onPressed: _isChecking ? null : _handleManageStore,
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
