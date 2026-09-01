import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../stores/session_store.dart';
import '../services/role_switch_helper.dart';
import '../widgets/bora/bora_mascot.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/language_toggle.dart';

import '../l10n/tr.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        // Stack só por causa do "PT | EN": este é o PRIMEIRO ecrã que alguém
        // vê ao instalar a app. Se o alternador só existisse na home, quem não
        // lê português ficava preso aqui, antes sequer de conseguir entrar.
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xxxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // ── Logo ──────────────────────────────────────────────────
                  const BoraMascot(
                    variant: BoraMascotVariant.logo,
                    size: 88,
                    semanticLabel: 'BORA',
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
                    child: Text(
                      'Entregas rápidas em Portugal'.tr,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── As três portas ────────────────────────────────────────
                  //
                  // UMA CONTA, TODOS OS PERFIS (2026-08-29). Até aqui, cada um
                  // destes botões fazia `logout()` — **mesmo com sessão aberta**.
                  // Quem já estava dentro e queria só mudar de perfil era posto
                  // fora e obrigado a escrever a palavra-passe outra vez. Era a
                  // segunda causa da mesma queixa: a primeira era o login de
                  // cliente expulsar quem também é estafeta.
                  //
                  // Agora, com sessão aberta, troca-se o perfil por dentro
                  // (`activateRole`, que reaproveita o mesmo JWT). Só quem não
                  // tem sessão é que vai parar ao ecrã de entrar.
                  _PortaDoPerfil(
                    rotulo: 'Sou Cliente'.tr,
                    paraQuem: 'Pedir comida, compras e serviços'.tr,
                    icone: Icons.person_outline,
                    cor: AppColors.primary,
                    papel: UserRole.client,
                  ),
                  const SizedBox(height: Spacing.md),
                  _PortaDoPerfil(
                    rotulo: 'Sou Estafeta'.tr,
                    paraQuem:
                        'Entregar, fazer corridas, limpezas ou lavagens'.tr,
                    icone: Icons.delivery_dining,
                    cor: AppColors.accent,
                    papel: UserRole.driver,
                  ),
                  const SizedBox(height: Spacing.md),
                  _PortaDoPerfil(
                    rotulo: 'Sou Parceiro'.tr,
                    paraQuem: 'Tenho restaurante, loja ou salão no Bora'.tr,
                    icone: Icons.storefront_outlined,
                    cor: AppColors.info,
                    papel: UserRole.partner,
                  ),

                  const Spacer(flex: 1),
                  Text(
                    'v1.0 · boraappbora@gmail.com'.tr,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                ],
              ),
            ),
            const Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(top: Spacing.sm, right: Spacing.sm),
                child: LanguageToggle(onDark: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma das três portas do arranque.
///
/// Diz **a quem se destina** por baixo do nome — um cliente real caiu nas três
/// numa noite só, porque "Sou Estafeta" e "Sou Parceiro" não explicavam nada.
class _PortaDoPerfil extends StatelessWidget {
  const _PortaDoPerfil({
    required this.rotulo,
    required this.paraQuem,
    required this.icone,
    required this.cor,
    required this.papel,
  });

  final String rotulo;
  final String paraQuem;
  final IconData icone;
  final Color cor;
  final UserRole papel;

  Future<void> _entrar(BuildContext context) async {
    final authStore = context.read<AuthStore>();
    final sessionStore = context.read<SessionStore>();

    // Com sessão aberta, troca-se por dentro: a mesma conta serve todos os
    // perfis e o JWT actual já vale para todos.
    if (Supabase.instance.client.auth.currentUser != null) {
      final ok = await activateRole(context, papel);
      if (ok) return;
      // Não tem esse perfil (ou faltam-lhe os dados neste aparelho): cai para
      // o ecrã de entrar desse perfil, que explica o que falta.
    }

    // L3 — troca de papel, não "Sair": preserva biometria.
    authStore.logout(wipeBiometrics: false);
    await sessionStore.setRole(papel);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoraPrimaryButton(
          label: rotulo,
          icon: icone,
          color: cor,
          onPressed: () => _entrar(context),
        ),
        const SizedBox(height: 4),
        Text(
          paraQuem,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
