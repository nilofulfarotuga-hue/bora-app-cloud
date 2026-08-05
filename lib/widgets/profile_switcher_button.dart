import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../services/role_switch_helper.dart';
import '../stores/session_store.dart';

/// MULTI-PAPEL (2026-07-31) — botão de troca de perfil no cabeçalho.
///
/// Só aparece quando o utilizador tem MAIS DO QUE UM papel (RPC `my_roles()`).
/// Papel ainda por aprovar aparece na lista, mas desactivado e com o estado à
/// vista ("Em análise" / "Recusado") — o utilizador percebe porque não pode
/// entrar ainda.
class ProfileSwitcherButton extends StatefulWidget {
  const ProfileSwitcherButton({super.key});

  @override
  State<ProfileSwitcherButton> createState() => _ProfileSwitcherButtonState();
}

class _ProfileSwitcherButtonState extends State<ProfileSwitcherButton> {
  List<Map<String, dynamic>> _roles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final roles = await fetchUiRoles();
    if (!mounted) return;
    setState(() => _roles = roles);
  }

  @override
  Widget build(BuildContext context) {
    if (_roles.length < 2) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.switch_account_outlined),
      tooltip: 'Trocar de perfil',
      onPressed: _openSheet,
    );
  }

  void _openSheet() {
    final sessionStore = context.read<SessionStore>();
    final messenger = ScaffoldMessenger.of(context);
    final current = sessionStore.role;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: Text(
                'Trocar de perfil',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final r in _roles)
              Builder(builder: (_) {
                final role = r['role'] as String?;
                final uiRole = uiRoleFor(role)!;
                final (statusText, enabled) =
                    roleStatusLabel(r['approval_status'] as String?);
                final isCurrent = uiRole == current;
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
                          // Troca a conta activa (client/driver/partner) na
                          // mesma sessão Supabase Auth — sem logout — e só
                          // depois muda o SessionStore. _RootNavigator
                          // observa o SessionStore e reconstrói sozinho.
                          final ok = await activateRole(context, uiRole);
                          if (!ok) {
                            messenger.showSnackBar(const SnackBar(
                              content: Text(
                                  'Não foi possível trocar de perfil. Tenta novamente.'),
                            ));
                          }
                        },
                );
              }),
            const SizedBox(height: Spacing.sm),
          ],
        ),
      ),
    );
  }
}
