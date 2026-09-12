import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_store.dart';
import '../stores/session_store.dart';

/// MULTI-PAPEL — mapeamento partilhado entre o ecrã de escolha pós-login
/// (`RoleChoiceScreen`) e o botão de troca de perfil (`ProfileSwitcherButton`).
/// Só client/driver/partner têm ecrã próprio no `_RootNavigator`.
UserRole? uiRoleFor(String? role) => switch (role) {
      'client' => UserRole.client,
      'driver' => UserRole.driver,
      'partner' => UserRole.partner,
      _ => null,
    };

String roleLabel(String? role) => switch (role) {
      'client' => 'Cliente',
      'driver' => 'Estafeta',
      'partner' => 'Parceiro',
      _ => role ?? '—',
    };

IconData roleIcon(String? role) => switch (role) {
      'client' => Icons.shopping_bag_outlined,
      'driver' => Icons.two_wheeler_outlined,
      'partner' => Icons.storefront_outlined,
      _ => Icons.person_outline,
    };

/// (texto do estado, se pode entrar já) a partir do `approval_status`.
(String, bool) roleStatusLabel(String? status) => switch (status) {
      'approved' => ('', true),
      'pending' => ('Em análise', false),
      'rejected' => ('Recusado', false),
      null => ('', true),
      _ => (status, false),
    };

/// Lê `my_roles()` e devolve só os papéis com ecrã próprio (client/driver/
/// partner) — usado tanto para decidir se mostra o ecrã de escolha pós-login
/// como para o botão de troca em Perfil.
Future<List<Map<String, dynamic>>> fetchUiRoles() async {
  try {
    final res = await Supabase.instance.client.rpc('my_roles');
    return (res as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .where((r) => uiRoleFor(r['role'] as String?) != null)
            .toList() ??
        const [];
  } catch (e) {
    debugPrint('fetchUiRoles: my_roles falhou => $e');
    return const [];
  }
}

/// Activa [role] na sessão actual — sem novo login, a mesma sessão Supabase
/// Auth serve todos os papéis (ver `AuthStore.switchToRole`) — e troca o
/// `SessionStore`. `_RootNavigator`/`PartnerEntryScreen` reagem sozinhos.
Future<bool> activateRole(BuildContext context, UserRole role) async {
  final authStore = context.read<AuthStore>();
  final sessionStore = context.read<SessionStore>();

  final authRole = switch (role) {
    UserRole.client => AuthRole.client,
    UserRole.driver => AuthRole.driver,
    UserRole.partner => AuthRole.partner,
  };

  final ok = await authStore.switchToRole(authRole);
  if (!ok) return false;
  await sessionStore.setRole(role);
  return true;
}
