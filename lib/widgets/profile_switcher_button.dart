import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
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
    try {
      final res = await Supabase.instance.client.rpc('my_roles');
      if (!mounted) return;
      setState(() {
        _roles = (res as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .where((r) => _uiRoleFor(r['role'] as String?) != null)
                .toList() ??
            const [];
      });
    } catch (e) {
      debugPrint('ProfileSwitcherButton: my_roles falhou => $e');
    }
  }

  /// Só client/driver/partner têm um separador próprio no `_RootNavigator`.
  static UserRole? _uiRoleFor(String? role) => switch (role) {
        'client' => UserRole.client,
        'driver' => UserRole.driver,
        'partner' => UserRole.partner,
        _ => null,
      };

  static String _label(String? role) => switch (role) {
        'client' => 'Cliente',
        'driver' => 'Estafeta',
        'partner' => 'Parceiro',
        _ => role ?? '—',
      };

  static IconData _icon(String? role) => switch (role) {
        'client' => Icons.shopping_bag_outlined,
        'driver' => Icons.two_wheeler_outlined,
        'partner' => Icons.storefront_outlined,
        _ => Icons.person_outline,
      };

  static (String, bool) _statusLabel(String? status) => switch (status) {
        'approved' => ('', true),
        'pending' => ('Em análise', false),
        'rejected' => ('Recusado', false),
        null => ('', true),
        _ => (status, false),
      };

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
                final uiRole = _uiRoleFor(role)!;
                final (statusText, enabled) =
                    _statusLabel(r['approval_status'] as String?);
                final isCurrent = uiRole == current;
                return ListTile(
                  leading: Icon(
                    _icon(role),
                    color: enabled ? AppColors.primary : AppColors.textSubtle,
                  ),
                  title: Text(_label(role)),
                  subtitle: statusText.isEmpty ? null : Text(statusText),
                  trailing: isCurrent
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  enabled: enabled && !isCurrent,
                  onTap: (!enabled || isCurrent)
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          // _RootNavigator observa o SessionStore e reconstrói
                          // sozinho — não há push/pushReplacement aqui.
                          await sessionStore.setRole(uiRole);
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
