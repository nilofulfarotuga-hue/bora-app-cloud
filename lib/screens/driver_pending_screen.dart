import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/role_switch_helper.dart';
import '../stores/session_store.dart';
import '../widgets/bora/bora_mascot.dart';

class DriverPendingScreen extends StatelessWidget {
  const DriverPendingScreen({super.key});

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
              const BoraMascot(
                variant: BoraMascotVariant.icon,
                size: 96,
                semanticLabel: 'BORA',
              ),
              const SizedBox(height: Spacing.xxxl),
              const Text(
                'Candidatura em análise',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.md),
              const Text(
                'A tua candidatura foi submetida com sucesso.\n\nA nossa equipa irá rever os teus documentos e entrar em contacto em breve.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.lg),
              // PEDIDO PENDENTE NAO BLOQUEIA (2026-08-29). Este ecra so fala
              // do perfil de estafeta. Enquanto a candidatura e revista, a
              // pessoa continua a poder usar a app como cliente — e antes
              // daqui so tinha o botao "Sair", o que a mandava embora da app
              // inteira por causa de um perfil so.
              const Text(
                'Entretanto podes usar a app normalmente para fazer os teus '
                'pedidos. A analise continua na mesma.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.lg),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  onPressed: () async {
                    // Sem palavra-passe outra vez: a sessao ja e a mesma para
                    // todos os perfis.
                    final ok = await activateRole(context, UserRole.client);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Nao foi possivel abrir o teu perfil de cliente. '
                              'Tenta de novo.')));
                    }
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Usar a app como cliente'),
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
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(
                        color: AppColors.warning, width: 1.5),
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
