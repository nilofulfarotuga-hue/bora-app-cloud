import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../screens/cleaner/cleaner_home_screen.dart';
import '../screens/washer/washer_home_screen.dart';
import '../services/role_switch_helper.dart';
import '../services/roles_service.dart';
import '../stores/session_store.dart';

import '../l10n/tr.dart';

/// MULTI-PAPEL (2026-07-31) — botão de troca de perfil no cabeçalho.
///
/// Só aparece quando o utilizador tem MAIS DO QUE UM papel (RPC `my_roles()`).
/// Papel ainda por aprovar aparece na lista, mas desactivado e com o estado à
/// vista ("Em análise" / "Recusado") — o utilizador percebe porque não pode
/// entrar ainda.
///
/// [Limpadora presa · 03/10 · Mayra] Passa a mostrar também Limpeza e Lavagem
/// (antes só cliente/estafeta/parceiro): quem ia do modo cliente para a
/// limpeza não tinha botão para voltar, e vice-versa. Limpeza/Lavagem abrem
/// por cima do modo base (cliente/estafeta) — ao reabrir a app a pessoa cai
/// sempre no modo base, nunca trancada.
class ProfileSwitcherButton extends StatefulWidget {
  const ProfileSwitcherButton({super.key, this.modoAtual, this.comTexto = false});

  /// O modo em que a pessoa está AGORA: 'client' | 'driver' | 'partner' |
  /// 'cleaner' | 'washer'. Null = o papel do SessionStore.
  final String? modoAtual;

  /// true → botão com texto "Mudar de modo" (sempre visível, para quem não
  /// percebe ícones); false → só o ícone, como antes.
  final bool comTexto;

  @override
  State<ProfileSwitcherButton> createState() => _ProfileSwitcherButtonState();
}

class _ProfileSwitcherButtonState extends State<ProfileSwitcherButton> {
  List<Map<String, dynamic>> _roles = const [];
  RolesSummary _trabalho = RolesSummary.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await Future.wait<Object>([
      fetchUiRoles(),
      RolesService.mySummary().catchError((_) => RolesSummary.empty()),
    ]);
    if (!mounted) return;
    setState(() {
      _roles = res[0] as List<Map<String, dynamic>>;
      _trabalho = res[1] as RolesSummary;
    });
  }

  int get _total =>
      _roles.length +
      (_trabalho.cleanerApproved ? 1 : 0) +
      (_trabalho.washerApproved ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    if (_total < 2) return const SizedBox.shrink();
    if (widget.comTexto) {
      return TextButton.icon(
        onPressed: _openSheet,
        icon: const Icon(Icons.swap_horiz),
        label: Text('Mudar de modo'.tr),
      );
    }
    return IconButton(
      icon: const Icon(Icons.switch_account_outlined),
      tooltip: 'Trocar de perfil'.tr,
      onPressed: _openSheet,
    );
  }

  void _openSheet() {
    final sessionStore = context.read<SessionStore>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final base = sessionStore.role;
    final atual = widget.modoAtual ??
        switch (base) {
          UserRole.client => 'client',
          UserRole.driver => 'driver',
          UserRole.partner => 'partner',
          null => null,
        };

    void abrirTrabalho(String papel) {
      // Fecha o que estiver por cima (outro ecrã de trabalho).
      nav.popUntil((r) => r.isFirst);
      // [09/10 · Mayra] Grava o modo: ao reabrir a app entra-se nele.
      sessionStore
          .setUltimoModoTrabalho(papel == 'washer' ? 'lavagem' : 'limpeza');
      // Com a base no estafeta, quem troca o ecrã é o portão do prestador
      // (segue o modo guardado) — abrir por cima duplicava o ecrã.
      if (base == UserRole.driver) return;
      nav.push(MaterialPageRoute<void>(
        builder: (_) => papel == 'washer'
            ? const WasherHomeScreen()
            : const CleanerHomeScreen(),
      ));
    }

    Widget linhaTrabalho(String papel, String titulo, IconData icone) {
      final isCurrent = atual == papel;
      return ListTile(
        leading: Icon(icone, color: AppColors.primary),
        title: Text(titulo.tr),
        trailing: isCurrent
            ? const Icon(Icons.check, color: AppColors.primary)
            : null,
        enabled: !isCurrent,
        onTap: isCurrent
            ? null
            : () {
                Navigator.pop(context);
                abrirTrabalho(papel);
              },
      );
    }

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'Mudar de modo'.tr,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final r in _roles)
              Builder(builder: (_) {
                final role = r['role'] as String?;
                final uiRole = uiRoleFor(role)!;
                final (statusText, enabled) =
                    roleStatusLabel(r['approval_status'] as String?);
                final isCurrent = role == atual;
                return ListTile(
                  leading: Icon(
                    roleIcon(role),
                    color: enabled ? AppColors.primary : AppColors.textSubtle,
                  ),
                  title: Text(roleLabel(role)),
                  subtitle: statusText.isEmpty ? null : Text(statusText),
                  trailing: isCurrent
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  enabled: enabled && !isCurrent,
                  onTap: (!enabled || isCurrent)
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          // [09/10 · Mayra] Escolher o estafeta grava o modo
                          // (o portão do prestador volta ao ecrã dele).
                          if (uiRole == UserRole.driver) {
                            // Memória já, disco em fundo (sem esperar: o
                            // contexto é usado logo a seguir).
                            unawaited(
                                sessionStore.setUltimoModoTrabalho('estafeta'));
                          }
                          // Já é o modo base (ex.: está na Limpeza por cima
                          // do modo cliente): basta fechar o que está por cima.
                          if (uiRole == base) {
                            nav.popUntil((r) => r.isFirst);
                            return;
                          }
                          // Troca a conta activa (client/driver/partner) na
                          // mesma sessão Supabase Auth — sem logout — e só
                          // depois muda o SessionStore. _RootNavigator
                          // observa o SessionStore e reconstrói sozinho.
                          final ok = await activateRole(context, uiRole);
                          if (!ok) {
                            messenger.showSnackBar(SnackBar(
                              content: Text(
                                  'Não foi possível trocar de perfil. Tenta novamente.'.tr),
                            ));
                            return;
                          }
                          nav.popUntil((r) => r.isFirst);
                        },
                );
              }),
            if (_trabalho.cleanerApproved)
              linhaTrabalho('cleaner', 'Limpeza', Icons.cleaning_services_outlined),
            if (_trabalho.washerApproved)
              linhaTrabalho('washer', 'Lavagem de carros', Icons.local_car_wash_outlined),
            const SizedBox(height: Spacing.sm),
          ],
        ),
      ),
    );
  }
}
